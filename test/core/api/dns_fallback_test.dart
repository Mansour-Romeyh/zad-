import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/dns_fallback.dart';

/// Cloudflare/Google JSON-DNS shaped answer: a CNAME hop followed by two A
/// records with a 120s TTL.
const _answerWithCname =
    '{"Status":0,"Question":[{"name":"zad.example.net","type":1}],'
    '"Answer":['
    '{"name":"zad.example.net","type":5,"TTL":300,"data":"edge.example.net."},'
    '{"name":"edge.example.net","type":1,"TTL":120,"data":"91.98.78.28"},'
    '{"name":"edge.example.net","type":1,"TTL":120,"data":"91.98.78.29"}]}';

const _nxdomain = '{"Status":3,"Question":[{"name":"missing.example.net","type":1}]}';

List<InternetAddress> _addrs(List<String> ips) =>
    ips.map(InternetAddress.new).toList();

void main() {
  group('DohResolver.parse', () {
    test('extracts only A records, skipping CNAME hops', () {
      final parsed = DohResolver.parse(_answerWithCname);

      expect(
        parsed.addresses.map((a) => a.address),
        ['91.98.78.28', '91.98.78.29'],
      );
    });

    test('uses the minimum A-record TTL', () {
      final parsed = DohResolver.parse(_answerWithCname);

      expect(parsed.ttl, const Duration(seconds: 120));
    });

    test('clamps TTL into the 60s..3600s band', () {
      const tiny =
          '{"Status":0,"Answer":[{"name":"a","type":1,"TTL":5,"data":"1.2.3.4"}]}';
      const huge =
          '{"Status":0,"Answer":[{"name":"a","type":1,"TTL":999999,"data":"1.2.3.4"}]}';

      expect(DohResolver.parse(tiny).ttl, const Duration(seconds: 60));
      expect(DohResolver.parse(huge).ttl, const Duration(seconds: 3600));
    });

    test('returns empty for NXDOMAIN (no Answer key)', () {
      expect(DohResolver.parse(_nxdomain).addresses, isEmpty);
    });

    test('returns empty for a non-JSON body (captive portal, blocked page)', () {
      expect(DohResolver.parse('<html>blocked</html>').addresses, isEmpty);
    });
  });

  group('DohResolver.resolve', () {
    test('returns the system lookup result without touching DoH', () async {
      var fetches = 0;
      final resolver = DohResolver(
        systemLookup: (host) async => _addrs(['10.0.0.7']),
        fetchJson: (url, headers) async {
          fetches++;
          return _answerWithCname;
        },
      );

      final result = await resolver.resolve('zad.example.net');

      expect(result.map((a) => a.address), ['10.0.0.7']);
      expect(fetches, 0);
    });

    test('short-circuits IP literals without any lookup', () async {
      var lookups = 0;
      var fetches = 0;
      final resolver = DohResolver(
        systemLookup: (host) async {
          lookups++;
          return const [];
        },
        fetchJson: (url, headers) async {
          fetches++;
          return _answerWithCname;
        },
      );

      final result = await resolver.resolve('1.1.1.1');

      expect(result.single.address, '1.1.1.1');
      expect(lookups, 0);
      expect(fetches, 0);
    });

    test('falls back to DoH when the system lookup throws', () async {
      final resolver = DohResolver(
        systemLookup: (host) async =>
            throw const SocketException('Failed host lookup'),
        fetchJson: (url, headers) async => _answerWithCname,
      );

      final result = await resolver.resolve('zad.example.net');

      expect(
        result.map((a) => a.address),
        ['91.98.78.28', '91.98.78.29'],
      );
    });

    test('caches a DoH answer and serves it without re-fetching', () async {
      var fetches = 0;
      final resolver = DohResolver(
        systemLookup: (host) async =>
            throw const SocketException('Failed host lookup'),
        fetchJson: (url, headers) async {
          fetches++;
          return _answerWithCname;
        },
      );

      await resolver.resolve('zad.example.net');
      await resolver.resolve('zad.example.net');

      expect(fetches, 1);
    });

    test('expires the cache after the answer TTL', () async {
      var fetches = 0;
      var current = DateTime(2026, 7, 17);
      final resolver = DohResolver(
        systemLookup: (host) async =>
            throw const SocketException('Failed host lookup'),
        fetchJson: (url, headers) async {
          fetches++;
          return _answerWithCname;
        },
        now: () => current,
      );

      await resolver.resolve('zad.example.net');
      current = current.add(const Duration(seconds: 119));
      await resolver.resolve('zad.example.net');
      expect(fetches, 1, reason: 'inside the 120s TTL — cache must hold');

      current = current.add(const Duration(seconds: 2));
      await resolver.resolve('zad.example.net');
      expect(fetches, 2, reason: 'past the TTL — cache must refresh');
    });

    test('tries the next DoH endpoint when the first fails', () async {
      final tried = <String>[];
      final resolver = DohResolver(
        systemLookup: (host) async =>
            throw const SocketException('Failed host lookup'),
        fetchJson: (url, headers) async {
          tried.add(url.host);
          if (tried.length == 1) throw const SocketException('blocked');
          return _answerWithCname;
        },
      );

      final result = await resolver.resolve('zad.example.net');

      expect(result, isNotEmpty);
      expect(tried, hasLength(2));
      expect(tried.first, isNot(tried.last));
    });

    test('throws SocketException when system DNS and every endpoint fail', () {
      final resolver = DohResolver(
        systemLookup: (host) async =>
            throw const SocketException('Failed host lookup'),
        fetchJson: (url, headers) async =>
            throw const SocketException('blocked'),
      );

      expect(
        resolver.resolve('zad.example.net'),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('DohResolver static fallback', () {
    DohResolver blockedNetworkResolver({
      Map<String, List<String>> staticFallbacks = const {},
      void Function()? onSystemLookup,
    }) {
      return DohResolver(
        systemLookup: (host) async {
          onSystemLookup?.call();
          throw const SocketException('Failed host lookup');
        },
        fetchJson: (url, headers) async =>
            throw const SocketException('resolver IP blocked by ISP'),
        staticFallbacks: staticFallbacks,
      );
    }

    test('serves the pinned IP when system DNS and DoH all fail', () async {
      final resolver = blockedNetworkResolver(
        staticFallbacks: const {
          'zad.example.net': ['91.98.78.28'],
        },
      );

      final result = await resolver.resolve('zad.example.net');

      expect(result.single.address, '91.98.78.28');
    });

    test('caches the pinned answer so later lookups skip the dead paths',
        () async {
      var systemLookups = 0;
      final resolver = blockedNetworkResolver(
        staticFallbacks: const {
          'zad.example.net': ['91.98.78.28'],
        },
        onSystemLookup: () => systemLookups++,
      );

      await resolver.resolve('zad.example.net');
      await resolver.resolve('zad.example.net');

      expect(systemLookups, 1,
          reason: 'second lookup must come from the cache');
    });

    test('prefers a DoH answer over the pin', () async {
      final resolver = DohResolver(
        systemLookup: (host) async =>
            throw const SocketException('Failed host lookup'),
        fetchJson: (url, headers) async => _answerWithCname,
        staticFallbacks: const {
          'zad.example.net': ['203.0.113.9'],
        },
      );

      final result = await resolver.resolve('zad.example.net');

      expect(
        result.map((a) => a.address),
        ['91.98.78.28', '91.98.78.29'],
        reason: 'live DNS answers must win over the build-time pin',
      );
    });

    test('still throws for hosts without a pin', () {
      final resolver = blockedNetworkResolver(
        staticFallbacks: const {
          'zad.example.net': ['91.98.78.28'],
        },
      );

      expect(
        resolver.resolve('other.example.net'),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
