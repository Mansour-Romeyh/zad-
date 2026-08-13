import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/auth_repository.dart';

import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) {
  return Response(requestOptions: options, statusCode: 200, data: {'message': message});
}

Response<dynamic> _error(RequestOptions options, int statusCode, Map<String, dynamic> data) {
  return Response(requestOptions: options, statusCode: statusCode, data: data);
}

void main() {
  late FakeSecureStorage storage;
  late TokenStore tokenStore;

  setUp(() {
    storage = FakeSecureStorage();
    tokenStore = TokenStore(storage: storage);
  });

  AuthRepository repoWith(Dio dio) => AuthRepository(
        ApiClient(dio: dio, tokenStore: tokenStore, baseUrl: 'http://test.local'),
      );

  group('restore', () {
    test('starts as guest when nothing is saved', () async {
      final store = SessionStore(authRepository: repoWith(Dio()), tokenStore: tokenStore);

      await store.restore();

      expect(store.status, SessionStatus.guest);
      expect(store.isAuthed, isFalse);
    });

    test('restores an authed session from saved credentials', () async {
      await tokenStore.save(
        apiKey: 'key123',
        apiSecret: 'secret456',
        user: 'jane@app.local',
        fullName: 'Jane Doe',
        phone: '+9647701234567',
      );
      final store = SessionStore(authRepository: repoWith(Dio()), tokenStore: tokenStore);

      await store.restore();

      expect(store.status, SessionStatus.authed);
      expect(store.isAuthed, isTrue);
      expect(store.fullName, 'Jane Doe');
      expect(store.phone, '+9647701234567');
    });

    test('notifies listeners while restoring', () async {
      final store = SessionStore(authRepository: repoWith(Dio()), tokenStore: tokenStore);
      final statuses = <SessionStatus>[];
      store.addListener(() => statuses.add(store.status));

      await store.restore();

      expect(statuses, contains(SessionStatus.guest));
    });
  });

  group('login', () {
    test('persists credentials and flips to authed on success', () async {
      // True PRD F1 login shape: identity fields nested in `profile`.
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
      );
      final store = SessionStore(authRepository: repoWith(dio), tokenStore: tokenStore);

      await store.login(phone: '+9647701234567', password: 'p@ssw0rd');

      expect(store.status, SessionStatus.authed);
      expect(store.user, 'jane@app.local');
      expect(store.fullName, 'Jane Doe');
      final saved = await tokenStore.read();
      expect(saved!.apiKey, 'key789');
      expect(saved.user, 'jane@app.local');
    });

    test('rethrows and stays guest on failure', () async {
      final dio = buildFakeDio(
        (options) => _error(options, 401, {'message': 'Invalid credentials'}),
      );
      final store = SessionStore(authRepository: repoWith(dio), tokenStore: tokenStore);

      await expectLater(
        store.login(phone: '+9647701234567', password: 'wrong'),
        throwsException,
      );
      expect(store.status, SessionStatus.guest);
      expect(await tokenStore.read(), isNull);
    });
  });

  group('register', () {
    test('persists credentials and flips to authed on success', () async {
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'api_key': 'key123',
          'api_secret': 'secret456',
          'user': 'jane@app.local',
        }),
      );
      final store = SessionStore(authRepository: repoWith(dio), tokenStore: tokenStore);

      await store.register(
        fullName: 'Jane Doe',
        phone: '+9647701234567',
        password: 'p@ssw0rd',
        otp: '1234',
      );

      expect(store.status, SessionStatus.authed);
      expect(store.fullName, 'Jane Doe');
      expect(store.phone, '+9647701234567');
    });
  });

  group('logout', () {
    test('clears storage and drops to guest', () async {
      await tokenStore.save(apiKey: 'k', apiSecret: 's', user: 'u@app.local');
      final dio = buildFakeDio((options) => _envelope(options, null));
      final store = SessionStore(authRepository: repoWith(dio), tokenStore: tokenStore);
      await store.restore();
      expect(store.status, SessionStatus.authed);

      await store.logout();

      expect(store.status, SessionStatus.guest);
      expect(await tokenStore.read(), isNull);
    });

    test('still clears local session when the server call fails', () async {
      await tokenStore.save(apiKey: 'k', apiSecret: 's', user: 'u@app.local');
      final dio = buildFakeDio((options) => _error(options, 500, {'message': 'boom'}));
      final store = SessionStore(authRepository: repoWith(dio), tokenStore: tokenStore);
      await store.restore();

      await store.logout();

      expect(store.status, SessionStatus.guest);
      expect(await tokenStore.read(), isNull);
    });
  });

  group('deleteAccount', () {
    test('clears the session on success', () async {
      await tokenStore.save(apiKey: 'k', apiSecret: 's', user: 'u@app.local');
      final dio = buildFakeDio(
        (options) => _envelope(options, {'status': 'scheduled', 'purge_after': '2026-08-19'}),
      );
      final store = SessionStore(authRepository: repoWith(dio), tokenStore: tokenStore);
      await store.restore();
      expect(store.status, SessionStatus.authed);

      await store.deleteAccount();

      expect(store.isAuthed, isFalse);
      expect(store.user, isNull);
      expect(await tokenStore.read(), isNull);
    });

    test('keeps the session when the server call fails', () async {
      await tokenStore.save(apiKey: 'k', apiSecret: 's', user: 'u@app.local');
      final dio = buildFakeDio((options) => _error(options, 500, {'message': 'boom'}));
      final store = SessionStore(authRepository: repoWith(dio), tokenStore: tokenStore);
      await store.restore();
      expect(store.status, SessionStatus.authed);

      await expectLater(store.deleteAccount(), throwsA(isA<Exception>()));

      expect(store.isAuthed, isTrue);
      expect(await tokenStore.read(), isNotNull);
    });
  });

  group('forceLogout', () {
    test('drops an authed session to guest without calling the server', () async {
      await tokenStore.save(apiKey: 'k', apiSecret: 's', user: 'u@app.local');
      final store = SessionStore(authRepository: repoWith(Dio()), tokenStore: tokenStore);
      await store.restore();
      expect(store.status, SessionStatus.authed);

      await store.forceLogout();

      expect(store.status, SessionStatus.guest);
      expect(await tokenStore.read(), isNull);
    });
  });
}
