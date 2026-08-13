import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/profile_repository.dart';

import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) {
  return Response(requestOptions: options, statusCode: 200, data: {'message': message});
}

ApiClient _client(Dio dio) => ApiClient(
      dio: dio,
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

const _profileJson = {
  'user': '9647700000001@app.local',
  'full_name': 'Jane Doe',
  'phone': '+9647700000001',
  'email': null, // synthetic {phone}@app.local reported as absent
  'customer': 'CUST-0001',
};

void main() {
  group('ProfileRepository', () {
    test('get() calls profile.get and maps the profile', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _profileJson),
          capturedRequests: requests);
      final repo = ProfileRepository(_client(dio));

      final profile = await repo.get();

      expect(requests.single.path, '/api/method/grocery.api.profile.get');
      expect(profile.user, '9647700000001@app.local');
      expect(profile.fullName, 'Jane Doe');
      expect(profile.phone, '+9647700000001');
      expect(profile.email, isNull);
      expect(profile.customer, 'CUST-0001');
    });

    test('update() sends only the provided fields — phone never sent', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
          (options) => _envelope(options, {..._profileJson, 'full_name': 'Jane D.'}),
          capturedRequests: requests);
      final repo = ProfileRepository(_client(dio));

      final updated = await repo.update(fullName: 'Jane D.');

      expect(requests.single.path, '/api/method/grocery.api.profile.update');
      expect(requests.single.data, {'full_name': 'Jane D.'});
      expect(updated.fullName, 'Jane D.');
    });

    test('update() can send email alone (empty string clears it)', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _profileJson),
          capturedRequests: requests);
      final repo = ProfileRepository(_client(dio));

      await repo.update(email: '');

      expect(requests.single.data, {'email': ''});
    });

    test('registerDevice() posts the token', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, {'ok': true}),
          capturedRequests: requests);
      final repo = ProfileRepository(_client(dio));

      await repo.registerDevice('fcm-token-1');

      expect(requests.single.path,
          '/api/method/grocery.api.profile.register_device');
      expect(requests.single.data, {'token': 'fcm-token-1'});
    });

    test('registerDevice() swallows failures (safe no-op) and skips empty tokens', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => Response(
          requestOptions: options,
          statusCode: 500,
          data: {'message': 'push unconfigured'},
        ),
        capturedRequests: requests,
      );
      final repo = ProfileRepository(_client(dio));

      await repo.registerDevice('fcm-token-1'); // must not throw
      expect(requests, hasLength(1));

      await repo.registerDevice(''); // no request at all
      expect(requests, hasLength(1));
    });

    test('a guest 401 surfaces as UnauthenticatedException', () async {
      final dio = buildFakeDio(
        (options) => Response(
          requestOptions: options,
          statusCode: 401,
          data: {'message': 'Please log in'},
        ),
      );
      final repo = ProfileRepository(_client(dio));

      expect(repo.get(), throwsA(isA<UnauthenticatedException>()));
    });
  });
}
