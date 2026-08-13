import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/api/token_store.dart';

import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) {
  return Response(requestOptions: options, statusCode: 200, data: {'message': message});
}

/// A guest (logged-out) token store backed by an in-memory fake, so
/// constructing an [ApiClient] in tests never touches the platform secure
/// storage channel.
TokenStore _guestTokenStore() => TokenStore(storage: FakeSecureStorage());

Response<dynamic> _errorResponse(
  RequestOptions options,
  int statusCode,
  Map<String, dynamic> data,
) {
  return Response(requestOptions: options, statusCode: statusCode, data: data);
}

void main() {
  group('envelope unwrap', () {
    test('get() unwraps the message key', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {'name': 'Vegetables'}),
        capturedRequests: requests,
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      final result = await client.get('grocery.api.catalog.get_categories');

      expect(result, {'name': 'Vegetables'});
      expect(requests.single.path, '/api/method/grocery.api.catalog.get_categories');
    });

    test('post() sends data and unwraps the message key', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, [1, 2, 3]),
        capturedRequests: requests,
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      final result = await client.post(
        'grocery.api.catalog.items_by_category',
        data: {'item_group': 'Dairy', 'page': 1},
      );

      expect(result, [1, 2, 3]);
      expect(requests.single.data, {'item_group': 'Dairy', 'page': 1});
    });

    test('returns raw data unchanged when there is no message envelope', () async {
      final dio = buildFakeDio(
        (options) => Response(requestOptions: options, statusCode: 200, data: [1, 2]),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      expect(await client.get('grocery.api.content.get_onboarding'), [1, 2]);
    });
  });

  group('auth header', () {
    test('attaches Authorization header when a token is saved', () async {
      final storage = FakeSecureStorage();
      final tokenStore = TokenStore(storage: storage);
      await tokenStore.save(apiKey: 'key123', apiSecret: 'secret456', user: 'u@app.local');

      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, 'ok'),
        capturedRequests: requests,
      );
      final client = ApiClient(dio: dio, tokenStore: tokenStore, baseUrl: 'http://test.local');

      await client.get('grocery.api.wishlist.list');

      expect(requests.single.headers['Authorization'], 'token key123:secret456');
    });

    test('omits Authorization header when logged out (guest)', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, 'ok'),
        capturedRequests: requests,
      );
      final client = ApiClient(
        dio: dio,
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      );

      await client.get('grocery.api.catalog.get_categories');

      expect(requests.single.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('error mapping', () {
    test('401 maps to UnauthenticatedException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 401, {'message': 'Not logged in'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.get('grocery.api.cart.get'),
        throwsA(
          isA<UnauthenticatedException>().having((e) => e.message, 'message', 'Not logged in'),
        ),
      );
    });

    test('401 on a grocery.api.auth.* endpoint maps to InvalidCredentialsException', () async {
      // A wrong/short password on login answers 401, but it is a credential
      // rejection, not an expired session — a distinct type so the UI can say
      // "incorrect password" instead of "your session has expired".
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 401, {'message': 'Incorrect phone number or password.'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.auth.login', data: {'phone': 'p', 'password': 'x'}),
        throwsA(
          isA<InvalidCredentialsException>()
              .having((e) => e.message, 'message', 'Incorrect phone number or password.'),
        ),
      );
    });

    test('403 maps to ForbiddenException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 403, {'message': 'wrong_role'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(client.get('grocery.api.picker.my_orders'), throwsA(isA<ForbiddenException>()));
    });

    test('409 maps to OutOfStockException carrying items', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 409, {
          'message': 'out_of_stock',
          'items': ['ITEM-1', 'ITEM-2'],
        }),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.order.place_order'),
        throwsA(
          isA<OutOfStockException>().having((e) => e.items, 'items', ['ITEM-1', 'ITEM-2']),
        ),
      );
    });

    test('417 with OutsideCoverageError exc_type maps to OutsideCoverageException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 417,
            {'exc_type': 'OutsideCoverageError', 'message': 'outside_coverage'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.zone.resolve'),
        throwsA(isA<OutsideCoverageException>()),
      );
    });

    test('417 with OtpInvalidError exc_type maps to OtpInvalidException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 417,
            {'exc_type': 'OtpInvalidError', 'message': 'Incorrect OTP.'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.auth.verify_and_register'),
        throwsA(isA<OtpInvalidException>()),
      );
    });

    test('a generic 417 (e.g. ValidationError) is NOT treated as outside-coverage', () async {
      // Frappe returns 417 for every plain frappe.throw — a wrong OTP, a failed
      // validation, etc. Those must fall through to a plain ApiException, never
      // the delivery-coverage message.
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 417,
            {'exc_type': 'ValidationError', 'message': 'Something invalid'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.auth.verify_and_register'),
        throwsA(allOf(
          isA<ApiException>(),
          isNot(isA<OutsideCoverageException>()),
          isNot(isA<OtpInvalidException>()),
        )),
      );
    });

    test('417 with AccountNotFoundError exc_type maps to AccountNotFoundException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 417,
            {'exc_type': 'AccountNotFoundError', 'message': 'No account found for this phone number.'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.auth.request_reset_otp'),
        throwsA(allOf(
          isA<AccountNotFoundException>(),
          isNot(isA<OutsideCoverageException>()),
        )),
      );
    });

    test('400 maps to WeakPasswordException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 400, {'message': 'Password must be at least 8 characters'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.auth.verify_and_register'),
        throwsA(isA<WeakPasswordException>()),
      );
    });

    test('425 maps to StoreClosedException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 425, {'message': 'store_closed'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.order.place_order'),
        throwsA(isA<StoreClosedException>()),
      );
    });

    test('423 maps to OtpCooldownException carrying cooldown_sec', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 423, {'message': 'otp_cooldown', 'cooldown_sec': 42}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.auth.request_signup_otp'),
        throwsA(
          isA<OtpCooldownException>().having((e) => e.cooldownSec, 'cooldownSec', 42),
        ),
      );
    });

    test('410 maps to OtpExpiredException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 410, {'message': 'otp_expired'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.auth.verify_and_register'),
        throwsA(isA<OtpExpiredException>()),
      );
    });

    test('other status codes map to the generic ApiException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 500, {'message': 'Internal Server Error'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.get('grocery.api.catalog.get_item'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.message, 'message', 'Internal Server Error')
              .having((e) => e, 'is not a subtype', isNot(isA<UnauthenticatedException>())),
        ),
      );
    });

    test('network/connection errors map to ApiNetworkException', () async {
      final dio = buildNetworkErrorDio();
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.get('grocery.api.catalog.get_categories'),
        throwsA(isA<ApiNetworkException>()),
      );
    });

    test('timeouts map to ApiNetworkException', () async {
      final dio = buildNetworkErrorDio(type: DioExceptionType.connectionTimeout);
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.get('grocery.api.catalog.get_categories'),
        throwsA(isA<ApiNetworkException>()),
      );
    });

    test('invokes onUnauthenticated when a 401 is returned', () async {
      var calls = 0;
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 401, {'message': 'Not logged in'}),
      );
      final client = ApiClient(
        dio: dio,
        tokenStore: _guestTokenStore(),
        baseUrl: 'http://test.local',
        onUnauthenticated: () => calls++,
      );

      await expectLater(
        client.get('grocery.api.cart.get'),
        throwsA(isA<UnauthenticatedException>()),
      );
      expect(calls, 1);
    });

    test(
        'does NOT invoke onUnauthenticated for grocery.api.auth.* 401s '
        '(credential rejections)', () async {
      // frappe's check_password answers a wrong password with 401 — on
      // auth.change_password that means "wrong OLD password", not "session
      // dead", and must never force-log the whole app out.
      var calls = 0;
      final dio = buildFakeDio(
        (options) =>
            _errorResponse(options, 401, {'message': 'Incorrect User or Password'}),
      );
      final client = ApiClient(
        dio: dio,
        tokenStore: _guestTokenStore(),
        baseUrl: 'http://test.local',
        onUnauthenticated: () => calls++,
      );

      await expectLater(
        client.post('grocery.api.auth.change_password', data: {'old': 'x', 'new': 'y'}),
        throwsA(isA<UnauthenticatedException>()),
      );
      await expectLater(
        client.post('grocery.api.auth.login', data: {'phone': 'p', 'password': 'x'}),
        throwsA(isA<UnauthenticatedException>()),
      );
      expect(calls, 0);
    });

    test('does not invoke onUnauthenticated for other status codes', () async {
      var calls = 0;
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 403, {'message': 'wrong_role'}),
      );
      final client = ApiClient(
        dio: dio,
        tokenStore: _guestTokenStore(),
        baseUrl: 'http://test.local',
        onUnauthenticated: () => calls++,
      );

      await expectLater(client.get('grocery.api.picker.my_orders'), throwsA(isA<ForbiddenException>()));
      expect(calls, 0);
    });

    test('parses _server_messages when message key is absent', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 401, {
          '_server_messages': '["{\\"message\\": \\"Session expired\\", \\"indicator\\": \\"red\\"}"]',
        }),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.get('grocery.api.cart.get'),
        throwsA(
          isA<UnauthenticatedException>().having((e) => e.message, 'message', 'Session expired'),
        ),
      );
    });

    test('falls back to exception key when message and _server_messages are absent', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 500, {'exc_type': 'ValidationError', 'exception': 'Boom'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.get('grocery.api.catalog.get_item'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Boom')),
      );
    });
  });

  group('resolveFileUrl', () {
    test('joins the base url with a relative path', () {
      final client = ApiClient(dio: Dio(), baseUrl: 'http://10.0.2.2:8000');
      expect(client.resolveFileUrl('/files/banner.png'), 'http://10.0.2.2:8000/files/banner.png');
    });

    test('returns null for null input', () {
      final client = ApiClient(dio: Dio(), baseUrl: 'http://10.0.2.2:8000');
      expect(client.resolveFileUrl(null), isNull);
    });

    test('returns null for empty input', () {
      final client = ApiClient(dio: Dio(), baseUrl: 'http://10.0.2.2:8000');
      expect(client.resolveFileUrl(''), isNull);
    });

    test('leaves absolute urls untouched', () {
      final client = ApiClient(dio: Dio(), baseUrl: 'http://10.0.2.2:8000');
      expect(
        client.resolveFileUrl('https://cdn.example.com/x.png'),
        'https://cdn.example.com/x.png',
      );
    });
  });

  test('defaults baseUrl to the API_BASE_URL environment default', () {
    final client = ApiClient(dio: Dio());
    expect(client.baseUrl, 'https://zad.micronext.net');
  });
}
