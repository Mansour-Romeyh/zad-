import 'dart:convert';

import 'package:dio/dio.dart';

import 'api_exceptions.dart';
import 'token_store.dart';

/// Thin dio wrapper for the Frappe backend.
///
/// - Every call goes to `/api/method/{method}`.
/// - Success responses are unwrapped from the Frappe `{"message": ...}`
///   envelope.
/// - When a session is saved in [TokenStore], the `Authorization: token
///   {api_key}:{api_secret}` header is attached; guests get no header.
/// - Non-2xx responses and connection failures are translated into the
///   typed exceptions in `api_exceptions.dart`.
class ApiClient {
  ApiClient({Dio? dio, TokenStore? tokenStore, String? baseUrl, this.onUnauthenticated})
    : _tokenStore = tokenStore ?? TokenStore(),
      baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            // Default to production so a release built without the
            // --dart-define can never ship pointing at a dev address (an
            // iOS build once shipped defaulting to the Android-emulator
            // loopback 10.0.2.2 and every request failed on real devices).
            // For local dev, pass --dart-define=API_BASE_URL=http://10.0.2.2:8000
            // (Android emulator) or your host IP.
            defaultValue: 'https://zad.micronext.net',
          ),
      _dio = dio ?? Dio() {
    _dio.options.baseUrl = this.baseUrl;
  }

  final Dio _dio;
  final TokenStore _tokenStore;

  /// Base URL requests are sent to, and file paths are resolved against.
  final String baseUrl;

  /// Invoked whenever any request comes back with a 401, right before the
  /// [UnauthenticatedException] is thrown to the caller. `SessionStore`
  /// wires this in `app.dart` to `forceLogout()`, so an expired/revoked
  /// token drops the whole app back to guest — not just the screen that
  /// happened to make the failing call. Mutable so it can be set once the
  /// dependent store exists (it is constructed after this client).
  void Function()? onUnauthenticated;

  Future<Options> _authOptions() async {
    final creds = await _tokenStore.read();
    return Options(
      headers: creds == null
          ? const {}
          : {'Authorization': 'token ${creds.apiKey}:${creds.apiSecret}'},
    );
  }

  Future<dynamic> get(String method, {Map<String, dynamic>? params}) async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/method/$method',
        queryParameters: params,
        options: await _authOptions(),
      );
      return _unwrap(response);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  Future<dynamic> post(String method, {Map<String, dynamic>? data}) async {
    try {
      final response = await _dio.post<dynamic>(
        '/api/method/$method',
        data: data,
        options: await _authOptions(),
      );
      return _unwrap(response);
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  dynamic _unwrap(Response<dynamic> response) {
    final data = response.data;
    if (data is Map && data.containsKey('message')) {
      return data['message'];
    }
    return data;
  }

  /// Resolves a backend-relative file path (e.g. `/files/x.png`) to an
  /// absolute URL against [baseUrl]. Returns `null` for `null`/empty input
  /// and leaves already-absolute URLs untouched.
  String? resolveFileUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '$baseUrl$path';
  }

  ApiException _mapError(DioException e) {
    final response = e.response;
    if (response == null) {
      // No HTTP response at all: connection error, timeout, cancellation…
      return ApiNetworkException(e.message ?? 'Network error');
    }

    final message = _extractMessage(response.data);
    switch (response.statusCode) {
      case 401:
        // `grocery.api.auth.*` uses 401 as a *credential-validation* result
        // (wrong password on login, wrong OLD password on change_password —
        // frappe's check_password raises AuthenticationError), not as "your
        // session is dead". Force-logging the whole app out because an
        // authed user mistyped their current password in ChangePasswordPage
        // would be wrong, so the app-wide 401 hook is skipped for those
        // endpoints; a genuinely expired token still logs out on the next
        // non-auth call. The distinct type also lets the UI say "incorrect
        // password" instead of the misleading "your session has expired".
        if (_isCredentialEndpoint(e.requestOptions.path)) {
          return InvalidCredentialsException(message);
        }
        onUnauthenticated?.call();
        return UnauthenticatedException(message);
      case 400:
        // Backend `WeakPasswordError` (auth password policy). Its own status,
        // so no exc_type disambiguation needed.
        return WeakPasswordException(message);
      case 403:
        return ForbiddenException(message);
      case 409:
        return OutOfStockException(message, _extractItems(response.data));
      case 417:
        // Frappe returns 417 for EVERY plain `frappe.throw` (its ValidationError
        // default), so the status alone can't tell a real delivery-coverage
        // rejection from a generic validation error like "Incorrect OTP" — which
        // is why a wrong signup OTP used to read as "outside coverage".
        // Disambiguate by the exception class Frappe puts in the body.
        switch (_excType(response.data)) {
          case 'OutsideCoverageError':
            return OutsideCoverageException(message);
          case 'OtpInvalidError':
            return OtpInvalidException(message);
          case 'AccountNotFoundError':
            return AccountNotFoundException(message);
          default:
            return ApiException(message);
        }
      case 425:
        return StoreClosedException(message);
      case 423:
        return OtpCooldownException(message, _extractCooldownSec(response.data));
      case 410:
        return OtpExpiredException(message);
      case 422:
        return PhoneAlreadyRegisteredException(message);
      default:
        return ApiException(message);
    }
  }

  /// Whether [path] is an auth endpoint whose 401s mean "wrong credentials
  /// entered" rather than "session expired" — see the 401 case above.
  bool _isCredentialEndpoint(String path) =>
      path.contains('grocery.api.auth.');

  List<dynamic> _extractItems(dynamic data) {
    if (data is Map && data['items'] is List) {
      return data['items'] as List<dynamic>;
    }
    return const [];
  }

  int _extractCooldownSec(dynamic data) {
    final value = data is Map ? data['cooldown_sec'] : null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// Extracts a human-readable error message defensively: Frappe may put it
  /// in `_server_messages` (a JSON-encoded list, each entry itself possibly
  /// JSON-encoded), or plainly in `message`/`exception`.
  /// The thrown exception's class name from a Frappe (V1) error body —
  /// `{"exc_type": "OutsideCoverageError", ...}` — or null when absent. Used to
  /// disambiguate the shared 417 status.
  String? _excType(dynamic data) =>
      data is Map && data['exc_type'] is String ? data['exc_type'] as String : null;

  String _extractMessage(dynamic data, {String fallback = 'Something went wrong'}) {
    if (data is Map) {
      final serverMessages = data['_server_messages'];
      if (serverMessages is String && serverMessages.isNotEmpty) {
        final parsed = _parseServerMessages(serverMessages);
        if (parsed != null) return parsed;
      }
      final message = data['message'];
      if (message is String && message.isNotEmpty) return message;
      final exception = data['exception'];
      if (exception is String && exception.isNotEmpty) return exception;
    }
    return fallback;
  }

  String? _parseServerMessages(String serverMessages) {
    try {
      final decoded = jsonDecode(serverMessages);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! String) return null;
      try {
        final inner = jsonDecode(first);
        if (inner is Map && inner['message'] is String) {
          return inner['message'] as String;
        }
      } catch (_) {
        // Not JSON-encoded — treat the entry itself as the message.
      }
      return first;
    } catch (_) {
      return null;
    }
  }
}
