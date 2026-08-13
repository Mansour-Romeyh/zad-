import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// DNS-over-HTTPS fallback for devices whose network resolver is broken.
///
/// Some ISP resolvers fail to resolve recently-created hostnames long after
/// public DNS has them (seen in the field as `SocketException: Failed host
/// lookup` while the same phone's Chrome — which ships its own Secure DNS —
/// loads the site fine). [DohResolver] gives the app the same resilience:
/// the device resolver is tried first, and on failure the name is resolved
/// through Cloudflare's and Google's JSON DNS APIs, reached by IP literal so
/// the query itself needs no working DNS. Answers are cached per-host for
/// their TTL so only the first request on a broken network pays the
/// fallback cost.
///
/// [DnsFallbackHttpOverrides] plugs the resolver into every `dart:io`
/// [HttpClient] in the app (Dio and `Image.network` alike) via
/// `HttpOverrides.global`. TLS keeps full certificate validation: sockets
/// are opened against the resolved IP but upgraded with the original
/// hostname for SNI and cert checks.
class DohResolver {
  DohResolver({
    Future<List<InternetAddress>> Function(String host)? systemLookup,
    Future<String> Function(Uri url, Map<String, String> headers)? fetchJson,
    DateTime Function()? now,
    this.systemLookupTimeout = const Duration(seconds: 4),
    Map<String, List<String>> staticFallbacks = const {},
  }) : _systemLookup = systemLookup ?? InternetAddress.lookup,
       _fetchJson = fetchJson ?? _httpGet,
       _now = now ?? DateTime.now,
       _staticFallbacks = {
         for (final entry in staticFallbacks.entries)
           entry.key: entry.value.map(InternetAddress.new).toList(),
       };

  final Future<List<InternetAddress>> Function(String host) _systemLookup;
  final Future<String> Function(Uri url, Map<String, String> headers) _fetchJson;
  final DateTime Function() _now;

  /// Build-time host→IP pins, used only after the device resolver AND every
  /// DoH endpoint have failed — seen on networks that both break DNS and
  /// null-route the public resolvers. Certificate validation still runs
  /// against the hostname, so a wrong/hijacked pin cannot impersonate the
  /// backend; the request just fails TLS.
  final Map<String, List<InternetAddress>> _staticFallbacks;

  /// How long a pinned answer is served from cache before the live paths
  /// (which may have recovered, or may point at a moved server) are retried.
  static const _staticPinTtl = Duration(minutes: 30);

  /// Cap on how long a device-resolver attempt may stall before DoH takes
  /// over. Kept under typical request timeouts so the fallback still has
  /// time to run inside the same request.
  final Duration systemLookupTimeout;

  /// Kept tight: on networks that null-route the resolver IPs these queries
  /// only ever time out, and their sum bounds how long the first request
  /// stalls before the static pin takes over.
  static const _dohTimeout = Duration(seconds: 4);

  /// JSON DNS endpoints, addressed by IP literal on purpose: resolving them
  /// must not itself require DNS. Both certificates carry IP SANs, so TLS
  /// validation stays strict. Cloudflare needs the `accept` header; Google's
  /// `/resolve` endpoint defaults to JSON.
  static const _endpoints = [
    ('https://1.1.1.1/dns-query', {'accept': 'application/dns-json'}),
    ('https://8.8.8.8/resolve', <String, String>{}),
  ];

  final _cache = <String, ({List<InternetAddress> addresses, DateTime expires})>{};

  Future<List<InternetAddress>> resolve(String host) async {
    // IP literals (including the DoH endpoints themselves) need no lookup.
    final literal = InternetAddress.tryParse(host);
    if (literal != null) return [literal];

    // A fresh DoH answer beats re-trying a resolver already known to fail.
    final cached = _cache[host];
    if (cached != null && _now().isBefore(cached.expires)) {
      return cached.addresses;
    }

    try {
      final addresses = await _systemLookup(host).timeout(systemLookupTimeout);
      if (addresses.isNotEmpty) return addresses;
    } on Object {
      // Device resolver failed or stalled — fall through to DoH.
    }

    for (final (base, headers) in _endpoints) {
      try {
        final url = Uri.parse('$base?name=$host&type=A');
        final body = await _fetchJson(url, headers).timeout(_dohTimeout);
        final parsed = parse(body);
        if (parsed.addresses.isNotEmpty) {
          _cache[host] = (
            addresses: parsed.addresses,
            expires: _now().add(parsed.ttl),
          );
          return parsed.addresses;
        }
      } on Object {
        // Endpoint unreachable/blocked or gave no usable answer — try next.
      }
    }

    // Every live path is dead. Fall back to the build-time pin (cached so
    // only the first request pays the dead-path timeouts).
    final pinned = _staticFallbacks[host];
    if (pinned != null && pinned.isNotEmpty) {
      _cache[host] = (addresses: pinned, expires: _now().add(_staticPinTtl));
      return pinned;
    }
    throw SocketException(
      'Failed host lookup: "$host" (device DNS and DNS-over-HTTPS)',
    );
  }

  /// Parses a Cloudflare/Google JSON DNS body into A-record addresses and
  /// the minimum answer TTL (clamped to 60s..3600s). Lenient: anything
  /// malformed — captive-portal HTML, block pages, missing keys — yields an
  /// empty answer rather than an exception.
  @visibleForTesting
  static ({List<InternetAddress> addresses, Duration ttl}) parse(String body) {
    const empty = (addresses: <InternetAddress>[], ttl: Duration(seconds: 60));
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return empty;
      final answers = decoded['Answer'];
      if (answers is! List) return empty;

      final addresses = <InternetAddress>[];
      var minTtl = 3600;
      for (final answer in answers) {
        // Type 1 = A record; CNAME hops (type 5) etc. carry no address.
        if (answer is! Map || answer['type'] != 1) continue;
        final address = InternetAddress.tryParse(answer['data'] as String? ?? '');
        if (address == null) continue;
        addresses.add(address);
        final ttl = answer['TTL'];
        if (ttl is int && ttl < minTtl) minTtl = ttl;
      }
      return (
        addresses: addresses,
        ttl: Duration(seconds: minTtl.clamp(60, 3600)),
      );
    } on Object {
      return empty;
    }
  }

  /// Plain-`HttpClient` GET used for the DoH queries themselves. The
  /// endpoints are IP literals, so this never recurses into a lookup.
  static Future<String> _httpGet(Uri url, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.getUrl(url);
      headers.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('DoH query returned ${response.statusCode}', uri: url);
      }
      return response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }
}

/// Installs [DohResolver] into every `HttpClient` the app creates. Set once
/// in `main()`: `HttpOverrides.global = DnsFallbackHttpOverrides();`
class DnsFallbackHttpOverrides extends HttpOverrides {
  DnsFallbackHttpOverrides({DohResolver? resolver})
    : resolver = resolver ?? DohResolver();

  final DohResolver resolver;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionFactory = (url, proxyHost, proxyPort) =>
          _connect(url, proxyHost, proxyPort, context);
  }

  Future<ConnectionTask<Socket>> _connect(
    Uri url,
    String? proxyHost,
    int? proxyPort,
    SecurityContext? context,
  ) async {
    // A configured proxy resolves hostnames itself — hand it the socket.
    if (proxyHost != null && proxyPort != null) {
      return Socket.startConnect(proxyHost, proxyPort);
    }

    final host = url.host;
    final addresses = await resolver.resolve(host);
    final isSecure = url.scheme == 'https' || url.scheme == 'wss';

    var cancelled = false;
    Socket? active;
    final socketFuture = () async {
      Object lastError = SocketException('Cannot connect to $host:${url.port}');
      for (final address in addresses) {
        if (cancelled) break;
        try {
          final socket = await Socket.connect(
            address,
            url.port,
            timeout: const Duration(seconds: 10),
          );
          active = socket;
          if (!isSecure) return socket;
          // The socket targets a resolved IP; hand TLS the original
          // hostname so SNI and certificate validation stay strict.
          final tls = await SecureSocket.secure(
            socket,
            host: host,
            context: context,
          );
          active = tls;
          return tls;
        } on Object catch (error) {
          lastError = error;
          active?.destroy();
          active = null;
        }
      }
      throw lastError;
    }();

    return ConnectionTask.fromSocket(socketFuture, () {
      cancelled = true;
      active?.destroy();
    });
  }
}
