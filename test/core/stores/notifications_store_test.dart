import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/notifications_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/data/notifications_repository.dart';

import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

/// A [NotificationsRepository] over a fake dio: `unread_count` answers
/// [unread], `mark_read` `{ok: true}`. [override] lets a test observe or
/// fail individual calls.
NotificationsRepository _fakeRepository({
  int unread = 0,
  List<RequestOptions>? requests,
  Response<dynamic>? Function(RequestOptions options)? override,
}) {
  final dio = buildFakeDio(
    (options) {
      final overridden = override?.call(options);
      if (overridden != null) return overridden;
      if (options.path.endsWith('notifications.unread_count')) {
        return _envelope(options, {'count': unread});
      }
      return _envelope(options, {'ok': true});
    },
    capturedRequests: requests,
  );
  return NotificationsRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

Response<dynamic> _serverError(RequestOptions options) =>
    Response(requestOptions: options, statusCode: 500, data: {'message': 'boom'});

/// A guest [SessionStore] whose `login()` succeeds against a fake dio, for
/// tests that need a real guest→authed transition to fire the listener.
SessionStore _guestSessionWithFakeLogin() {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  final dio = buildFakeDio(
    (options) => _envelope(options, {
      'api_key': 'key789',
      'api_secret': 'secretabc',
      'profile': {'user': 'jane@app.local', 'full_name': 'Jane Doe'},
    }),
  );
  return SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: dio, tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
}

Future<SessionStore> _authedSession() async {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  await tokenStore.save(apiKey: 'k', apiSecret: 's', user: 'jane@app.local');
  final dio = buildFakeDio((options) => _envelope(options, null));
  final session = SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: dio, tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
  await session.restore();
  return session;
}

Iterable<RequestOptions> _calls(List<RequestOptions> requests, String suffix) =>
    requests.where((r) => r.path.endsWith(suffix));

void main() {
  group('NotificationsStore — guest', () {
    test('stays at zero and never calls the server', () async {
      final requests = <RequestOptions>[];
      final store = NotificationsStore(
          repository: _fakeRepository(unread: 7, requests: requests));

      await store.restore();
      await store.refresh();
      expect(await store.markRead('NL-1'), isFalse);

      expect(store.unreadCount, 0);
      expect(requests, isEmpty);
    });
  });

  group('NotificationsStore — authed', () {
    test('restore() hydrates the unread count', () async {
      final requests = <RequestOptions>[];
      final store = NotificationsStore(
        repository: _fakeRepository(unread: 3, requests: requests),
        session: await _authedSession(),
      );

      await store.restore();

      expect(store.unreadCount, 3);
      expect(_calls(requests, 'notifications.unread_count'), hasLength(1));
    });

    test('concurrent refresh() callers share one in-flight fetch', () async {
      final gate = Completer<void>();
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            await gate.future;
            handler.resolve(_envelope(options, {'count': 5}));
          },
        ),
      );
      final repo = NotificationsRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      final store =
          NotificationsStore(repository: repo, session: await _authedSession());

      final first = store.refresh();
      final second = store.refresh();
      gate.complete();
      await first;
      await second;

      expect(requests, hasLength(1));
      expect(store.unreadCount, 5);
    });

    test('a failed refresh keeps the previous count and records the error', () async {
      var fail = false;
      final store = NotificationsStore(
        repository: _fakeRepository(
          unread: 2,
          override: (options) => fail ? _serverError(options) : null,
        ),
        session: await _authedSession(),
      );
      await store.restore();
      expect(store.unreadCount, 2);

      fail = true;
      await store.refresh();

      expect(store.unreadCount, 2); // badge keeps last known value
      expect(store.error, isNotNull);

      fail = false;
      await store.refresh();
      expect(store.error, isNull);
    });

    test('markRead() posts and decrements the badge, clamped at zero', () async {
      final requests = <RequestOptions>[];
      final store = NotificationsStore(
        repository: _fakeRepository(unread: 1, requests: requests),
        session: await _authedSession(),
      );
      await store.restore();

      expect(await store.markRead('NL-1'), isTrue);
      expect(store.unreadCount, 0);
      expect(_calls(requests, 'notifications.mark_read').single.data,
          {'name': 'NL-1'});

      // Already at zero — a second markRead must not go negative.
      expect(await store.markRead('NL-2'), isTrue);
      expect(store.unreadCount, 0);
    });

    test('a failed markRead() returns false and leaves the badge alone', () async {
      final store = NotificationsStore(
        repository: _fakeRepository(
          unread: 2,
          override: (options) =>
              options.path.endsWith('notifications.mark_read') ? _serverError(options) : null,
        ),
        session: await _authedSession(),
      );
      await store.restore();

      expect(await store.markRead('NL-1'), isFalse);
      expect(store.unreadCount, 2);
    });
  });

  group('NotificationsStore — session transitions', () {
    test('login hydrates, logout clears', () async {
      final session = _guestSessionWithFakeLogin();
      final store = NotificationsStore(
        repository: _fakeRepository(unread: 4),
        session: session,
      );

      await session.login(phone: '+9647700000001', password: 'p@ss');
      await store.sessionSyncDone;
      expect(store.unreadCount, 4);

      await session.logout();
      expect(store.unreadCount, 0);
      expect(store.error, isNull);
    });
  });

  group('NotificationsStore — session-boundary races', () {
    test('logout invalidates the in-flight count: relogin issues a fresh fetch and the stale snapshot is discarded', () async {
      // User A's unread_count hangs → A logs out → B logs in. B's refresh
      // must NOT adopt A's hung fetch: a second unread_count goes out, and
      // A's late (large) count must never show on B's badge.
      final firstCountGate = Completer<void>();
      var countCalls = 0;
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            if (options.path.endsWith('notifications.unread_count')) {
              countCalls += 1;
              if (countCalls == 1) {
                await firstCountGate.future;
                handler.resolve(_envelope(options, {'count': 99}));
                return;
              }
              handler.resolve(_envelope(options, {'count': 1}));
              return;
            }
            handler.resolve(_envelope(options, {'ok': true}));
          },
        ),
      );
      final repo = NotificationsRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      final session = _guestSessionWithFakeLogin();
      final store = NotificationsStore(repository: repo, session: session);

      await session.login(phone: '+9647700000001', password: 'p@ss');
      while (_calls(requests, 'notifications.unread_count').isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }

      await session.logout(); // A's fetch still hung
      await session.login(phone: '+9647700000002', password: 'p@ss');
      final secondHydrate = store.sessionSyncDone;

      firstCountGate.complete(); // A's stale snapshot lands mid-B-hydrate
      await secondHydrate;
      await Future<void>.delayed(Duration.zero); // let the straggler settle

      expect(_calls(requests, 'notifications.unread_count'), hasLength(2),
          reason: 'relogin must issue its own unread_count, not adopt the hung one');
      expect(store.unreadCount, 1,
          reason: "user A's stale count must never show on user B's badge");
    });

    test('a stale post-logout failure does not poison the cleared state', () async {
      final firstCountGate = Completer<void>();
      var countCalls = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            if (options.path.endsWith('notifications.unread_count')) {
              countCalls += 1;
              if (countCalls == 1) {
                await firstCountGate.future;
                handler.reject(DioException(
                  requestOptions: options,
                  response: _serverError(options),
                  type: DioExceptionType.badResponse,
                ));
                return;
              }
            }
            handler.resolve(_envelope(options, {'ok': true}));
          },
        ),
      );
      final repo = NotificationsRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      final session = _guestSessionWithFakeLogin();
      final store = NotificationsStore(repository: repo, session: session);

      await session.login(phone: '+9647700000001', password: 'p@ss');
      await Future<void>.delayed(Duration.zero); // fetch now hung
      await session.logout();

      firstCountGate.complete(); // stale failure lands after the reset
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(store.error, isNull,
          reason: 'a post-logout failure must not re-poison the cleared error');
      expect(store.unreadCount, 0);
    });
  });
}
