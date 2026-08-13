import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/auth_repository.dart';

import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) {
  return Response(requestOptions: options, statusCode: 200, data: {'message': message});
}

ApiClient _client(Dio dio) =>
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local');

void main() {
  group('AuthRepository', () {
    test('requestSignupOtp posts phone and maps sent/cooldownSec', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {'sent': true, 'cooldown_sec': 60}),
        capturedRequests: requests,
      );
      final repo = AuthRepository(_client(dio));

      final result = await repo.requestSignupOtp('+9647701234567');

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/method/grocery.api.auth.request_signup_otp');
      expect(requests.single.data, {'phone': '+9647701234567'});
      expect(result.sent, isTrue);
      expect(result.cooldownSec, 60);
    });

    test('verifyAndRegister posts registration fields and maps session', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'api_key': 'key123',
          'api_secret': 'secret456',
          'user': 'jane@app.local',
          'customer': 'CUST-0001',
        }),
        capturedRequests: requests,
      );
      final repo = AuthRepository(_client(dio));

      final session = await repo.verifyAndRegister(
        fullName: 'Jane Doe',
        phone: '+9647701234567',
        password: 'p@ssw0rd',
        otp: '1234',
      );

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/method/grocery.api.auth.verify_and_register');
      expect(requests.single.data, {
        'full_name': 'Jane Doe',
        'phone': '+9647701234567',
        'password': 'p@ssw0rd',
        'otp': '1234',
      });
      expect(session.apiKey, 'key123');
      expect(session.apiSecret, 'secret456');
      expect(session.user, 'jane@app.local');
      // Backend doesn't echo full_name/phone on register — fall back to input.
      expect(session.fullName, 'Jane Doe');
      expect(session.phone, '+9647701234567');
    });

    test('login posts phone/password and maps session from profile', () async {
      final requests = <RequestOptions>[];
      // True PRD F1 contract shape: login returns {api_key, api_secret,
      // profile} where profile = {user, full_name, phone, customer} — `user`
      // is NOT top-level for login (it IS for verify_and_register).
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'api_key': 'key789',
          'api_secret': 'secretabc',
          'profile': {
            'user': 'jane@app.local',
            'full_name': 'Jane Doe',
            'phone': '+9647701234567',
            'customer': 'CUST-0001',
          },
        }),
        capturedRequests: requests,
      );
      final repo = AuthRepository(_client(dio));

      final session = await repo.login(phone: '+9647701234567', password: 'p@ssw0rd');

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/method/grocery.api.auth.login');
      expect(requests.single.data, {'phone': '+9647701234567', 'password': 'p@ssw0rd'});
      expect(session.apiKey, 'key789');
      expect(session.apiSecret, 'secretabc');
      expect(session.user, 'jane@app.local');
      expect(session.fullName, 'Jane Doe');
      expect(session.phone, '+9647701234567');
    });

    test('login falls back to top-level fields when profile omits them', () async {
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'api_key': 'key789',
          'api_secret': 'secretabc',
          'user': 'top@app.local',
          'profile': {'full_name': 'Jane Doe'},
        }),
      );
      final repo = AuthRepository(_client(dio));

      final session = await repo.login(phone: '+9647701234567', password: 'p@ssw0rd');

      expect(session.user, 'top@app.local');
      expect(session.fullName, 'Jane Doe');
      expect(session.phone, '+9647701234567'); // request-phone fallback
    });

    test('login without a profile map falls back to the request phone', () async {
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'api_key': 'key789',
          'api_secret': 'secretabc',
          'user': 'jane@app.local',
        }),
      );
      final repo = AuthRepository(_client(dio));

      final session = await repo.login(phone: '+9647701234567', password: 'p@ssw0rd');

      expect(session.user, 'jane@app.local');
      expect(session.fullName, isNull);
      expect(session.phone, '+9647701234567');
    });

    test('requestResetOtp posts phone', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {'sent': true}),
        capturedRequests: requests,
      );
      final repo = AuthRepository(_client(dio));

      final result = await repo.requestResetOtp('+9647701234567');

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/method/grocery.api.auth.request_reset_otp');
      expect(requests.single.data, {'phone': '+9647701234567'});
      expect(result.sent, isTrue);
      expect(result.cooldownSec, 0);
    });

    test('resetPassword posts phone/otp/new_password', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {'ok': true}),
        capturedRequests: requests,
      );
      final repo = AuthRepository(_client(dio));

      await repo.resetPassword(phone: '+9647701234567', otp: '1234', newPassword: 'newp@ss');

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/method/grocery.api.auth.reset_password');
      expect(requests.single.data, {
        'phone': '+9647701234567',
        'otp': '1234',
        'new_password': 'newp@ss',
      });
    });

    test('changePassword posts old/new', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {'ok': true}),
        capturedRequests: requests,
      );
      final repo = AuthRepository(_client(dio));

      await repo.changePassword(oldPassword: 'old1', newPassword: 'new1');

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/method/grocery.api.auth.change_password');
      expect(requests.single.data, {'old': 'old1', 'new': 'new1'});
    });

    test('logout posts an empty body', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, null),
        capturedRequests: requests,
      );
      final repo = AuthRepository(_client(dio));

      await repo.logout();

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/method/grocery.api.auth.logout');
      expect(requests.single.data, {});
    });

    test('deleteAccount posts an empty body', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'status': 'scheduled',
          'purge_after': '2026-08-19',
        }),
        capturedRequests: requests,
      );
      final repo = AuthRepository(_client(dio));

      await repo.deleteAccount();

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/method/grocery.api.auth.delete_account');
      expect(requests.single.data, {});
    });
  });
}
