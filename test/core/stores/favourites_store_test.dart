import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/data/wishlist_repository.dart';
import 'package:zad/models/product.dart';

import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

Map<String, dynamic> _card(String code) => {
      'item_code': code,
      'item_name': 'Item $code',
      'price_per_uom': 1000,
      'uom': 'pc',
      'in_stock': true,
      'is_favourite': true,
    };

/// A [WishlistRepository] over a fake dio: `list` answers with [listItems]
/// (refreshable via the returned mutable list), add/remove answer
/// `{ok: true}`. [onRequest] lets a test observe or fail individual calls
/// by returning an override response.
WishlistRepository _fakeRepository({
  List<Map<String, dynamic>> listItems = const [],
  List<RequestOptions>? requests,
  Response<dynamic>? Function(RequestOptions options)? override,
}) {
  final dio = buildFakeDio(
    (options) {
      final overridden = override?.call(options);
      if (overridden != null) return overridden;
      if (options.path.endsWith('wishlist.list')) {
        return _envelope(options, listItems);
      }
      return _envelope(options, {'ok': true});
    },
    capturedRequests: requests,
  );
  return WishlistRepository(
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
  // Fake dio so logout()'s best-effort server round trip never hits the
  // network.
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
  group('FavouritesStore — guest', () {
    test('starts empty and every mutation is a no-op (no server calls)', () async {
      final requests = <RequestOptions>[];
      final store = FavouritesStore(repository: _fakeRepository(requests: requests));

      expect(store.contains('ITEM-1'), isFalse);

      await store.add('ITEM-1');
      await store.toggle('ITEM-2');
      await store.remove('ITEM-1');
      await store.refresh();
      await store.restore();

      expect(store.contains('ITEM-1'), isFalse);
      expect(store.contains('ITEM-2'), isFalse);
      expect(store.items, isEmpty);
      expect(requests, isEmpty);
    });
  });

  group('FavouritesStore — optimistic add/remove (authed)', () {
    test('add flips the heart immediately and posts wishlist.add', () async {
      final requests = <RequestOptions>[];
      final store = FavouritesStore(
        repository: _fakeRepository(requests: requests),
        session: await _authedSession(),
      );
      var notified = 0;
      store.addListener(() => notified++);

      final future = store.add('ITEM-1');

      expect(store.contains('ITEM-1'), isTrue); // before the server answered
      expect(notified, 1);

      await future;

      expect(store.contains('ITEM-1'), isTrue);
      final call = _calls(requests, 'wishlist.add').single;
      expect(call.data, {'item_code': 'ITEM-1'});
    });

    test('add rolls the flip back when the server call fails (and never throws)', () async {
      final store = FavouritesStore(
        repository: _fakeRepository(
          override: (o) => o.path.endsWith('wishlist.add') ? _serverError(o) : null,
        ),
        session: await _authedSession(),
      );

      final future = store.add('ITEM-1');
      expect(store.contains('ITEM-1'), isTrue); // optimistic

      await future; // completes normally — no rethrow to the tap site

      expect(store.contains('ITEM-1'), isFalse); // rolled back
      expect(store.error, isNull); // toggle failures never poison the page state
    });

    test('add is idempotent: a second add posts nothing', () async {
      final requests = <RequestOptions>[];
      final store = FavouritesStore(
        repository: _fakeRepository(requests: requests),
        session: await _authedSession(),
      );

      await store.add('ITEM-1');
      await store.add('ITEM-1');

      expect(_calls(requests, 'wishlist.add'), hasLength(1));
    });

    test('remove flips immediately, drops the card from items, posts wishlist.remove', () async {
      final requests = <RequestOptions>[];
      final store = FavouritesStore(
        repository: _fakeRepository(
          listItems: [_card('ITEM-1'), _card('ITEM-2')],
          requests: requests,
        ),
        session: await _authedSession(),
      );
      await store.restore();
      expect(store.items, hasLength(2));

      final future = store.remove('ITEM-1');

      expect(store.contains('ITEM-1'), isFalse); // before the server answered
      expect(store.items.map((p) => p.itemCode), ['ITEM-2']);

      await future;

      final call = _calls(requests, 'wishlist.remove').single;
      expect(call.data, {'item_code': 'ITEM-1'});
    });

    test('remove rolls back the code AND the card at its original position on failure', () async {
      final store = FavouritesStore(
        repository: _fakeRepository(
          listItems: [_card('ITEM-1'), _card('ITEM-2'), _card('ITEM-3')],
          override: (o) => o.path.endsWith('wishlist.remove') ? _serverError(o) : null,
        ),
        session: await _authedSession(),
      );
      await store.restore();

      final future = store.remove('ITEM-2');
      expect(store.items.map((p) => p.itemCode), ['ITEM-1', 'ITEM-3']);

      await future;

      expect(store.contains('ITEM-2'), isTrue);
      expect(store.items.map((p) => p.itemCode), ['ITEM-1', 'ITEM-2', 'ITEM-3']);
    });

    test('toggle flips membership through the right endpoints', () async {
      final requests = <RequestOptions>[];
      final store = FavouritesStore(
        repository: _fakeRepository(requests: requests),
        session: await _authedSession(),
      );

      await store.toggle('ITEM-1');
      expect(store.contains('ITEM-1'), isTrue);

      await store.toggle('ITEM-1');
      expect(store.contains('ITEM-1'), isFalse);

      expect(_calls(requests, 'wishlist.add'), hasLength(1));
      expect(_calls(requests, 'wishlist.remove'), hasLength(1));
    });
  });

  group('FavouritesStore — seeding from ItemCard payloads', () {
    Product product(String code, {bool? isFavourite}) => Product(
          id: code,
          nameEn: code,
          nameAr: code,
          unitEn: 'pc',
          unitAr: 'pc',
          price: 1000,
          imagePath: '',
          itemCode: code,
          isFavourite: isFavourite,
        );

    test('seed adds only is_favourite=true codes and notifies once', () async {
      final requests = <RequestOptions>[];
      final store = FavouritesStore(
        repository: _fakeRepository(requests: requests),
        session: await _authedSession(),
      );
      var notified = 0;
      store.addListener(() => notified++);

      store.seed([
        product('ITEM-1', isFavourite: true),
        product('ITEM-2', isFavourite: false),
        product('ITEM-3'),
        product('ITEM-4', isFavourite: true),
      ]);

      expect(store.contains('ITEM-1'), isTrue);
      expect(store.contains('ITEM-2'), isFalse);
      expect(store.contains('ITEM-3'), isFalse);
      expect(store.contains('ITEM-4'), isTrue);
      expect(notified, 1);
      expect(requests, isEmpty); // pure local seeding, no network
    });

    test('seed never un-favourites an already-favourited item', () async {
      final store = FavouritesStore(
        repository: _fakeRepository(),
        session: await _authedSession(),
      );
      await store.add('ITEM-1');

      store.seed([product('ITEM-1', isFavourite: false)]);

      expect(store.contains('ITEM-1'), isTrue);
    });

    test('a re-seed does not notify when nothing changed', () async {
      final store = FavouritesStore(
        repository: _fakeRepository(),
        session: await _authedSession(),
      );
      store.seed([product('ITEM-1', isFavourite: true)]);
      var notified = 0;
      store.addListener(() => notified++);

      store.seed([product('ITEM-1', isFavourite: true)]);

      expect(notified, 0);
    });
  });

  group('FavouritesStore — hydrate lifecycle (list)', () {
    test('restore() while authed hydrates codes and items from wishlist.list', () async {
      final requests = <RequestOptions>[];
      final store = FavouritesStore(
        repository: _fakeRepository(
          listItems: [_card('ITEM-2'), _card('ITEM-1')],
          requests: requests,
        ),
        session: await _authedSession(),
      );

      await store.restore();

      expect(_calls(requests, 'wishlist.list'), hasLength(1));
      expect(store.hydrated, isTrue);
      expect(store.busy, isFalse);
      expect(store.items.map((p) => p.itemCode), ['ITEM-2', 'ITEM-1']); // server order
      expect(store.contains('ITEM-1'), isTrue);
      expect(store.contains('ITEM-2'), isTrue);
    });

    test('login transition hydrates automatically', () async {
      final requests = <RequestOptions>[];
      final session = _guestSessionWithFakeLogin();
      final store = FavouritesStore(
        repository: _fakeRepository(listItems: [_card('ITEM-1')], requests: requests),
        session: session,
      );
      expect(store.contains('ITEM-1'), isFalse);

      await session.login(phone: '+9647701234567', password: 'p@ss');
      await store.sessionSyncDone;

      expect(_calls(requests, 'wishlist.list'), hasLength(1));
      expect(store.hydrated, isTrue);
      expect(store.contains('ITEM-1'), isTrue);
    });

    test('logout clears everything', () async {
      final session = await _authedSession();
      final store = FavouritesStore(
        repository: _fakeRepository(listItems: [_card('ITEM-1')]),
        session: session,
      );
      await store.restore();
      expect(store.contains('ITEM-1'), isTrue);

      await session.logout();

      expect(store.contains('ITEM-1'), isFalse);
      expect(store.items, isEmpty);
      expect(store.hydrated, isFalse);
      expect(store.error, isNull);
    });

    test('a failed list records error (busy cleared) and a later refresh recovers', () async {
      var failList = true;
      final store = FavouritesStore(
        repository: _fakeRepository(
          listItems: [_card('ITEM-1')],
          override: (o) =>
              failList && o.path.endsWith('wishlist.list') ? _serverError(o) : null,
        ),
        session: await _authedSession(),
      );

      await store.restore(); // never throws

      expect(store.error, isNotNull);
      expect(store.busy, isFalse);
      expect(store.hydrated, isFalse);

      failList = false;
      await store.refresh();

      expect(store.error, isNull);
      expect(store.hydrated, isTrue);
      expect(store.contains('ITEM-1'), isTrue);
    });

    test('refresh replaces the snapshot (an item unfavourited elsewhere drops out)', () async {
      final listItems = <Map<String, dynamic>>[_card('ITEM-1'), _card('ITEM-2')];
      final store = FavouritesStore(
        repository: _fakeRepository(listItems: listItems),
        session: await _authedSession(),
      );
      await store.restore();
      expect(store.items, hasLength(2));

      listItems.removeAt(0); // ITEM-1 unfavourited on another device

      await store.refresh();

      expect(store.contains('ITEM-1'), isFalse);
      expect(store.items.map((p) => p.itemCode), ['ITEM-2']);
    });

    test('concurrent refresh calls share ONE in-flight wishlist.list', () async {
      final requests = <RequestOptions>[];
      final store = FavouritesStore(
        repository: _fakeRepository(listItems: [_card('ITEM-1')], requests: requests),
        session: await _authedSession(),
      );

      final first = store.refresh();
      final second = store.refresh(); // fired while the first is in flight
      await Future.wait([first, second]);

      expect(_calls(requests, 'wishlist.list'), hasLength(1));
      expect(store.hydrated, isTrue);
    });

    test('a heart added while the login hydrate is in flight survives the snapshot', () async {
      // The canonical race (PRD A3 flow): guest taps a heart → login sheet
      // → login succeeds → the listener's hydrate starts → the pending
      // toggle() fires while wishlist.list is STILL in flight. The list
      // snapshot (taken before the add) must not clobber the new heart.
      final listGate = Completer<void>();
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            if (options.path.endsWith('wishlist.list')) {
              await listGate.future;
              handler.resolve(_envelope(options, [_card('ITEM-OLD')]));
              return;
            }
            handler.resolve(_envelope(options, {'ok': true}));
          },
        ),
      );
      final repo = WishlistRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      final session = _guestSessionWithFakeLogin();
      final store = FavouritesStore(repository: repo, session: session);

      await session.login(phone: '+9647701234567', password: 'p@ss');
      // Wait until the login-triggered hydrate is genuinely in flight.
      while (_calls(requests, 'wishlist.list').isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }

      final toggleFuture = store.toggle('ITEM-NEW'); // heart tap mid-hydrate
      expect(store.contains('ITEM-NEW'), isTrue); // optimistic

      listGate.complete(); // stale snapshot (without ITEM-NEW) lands now
      await store.sessionSyncDone;
      await toggleFuture;

      expect(store.contains('ITEM-OLD'), isTrue); // snapshot applied
      expect(store.contains('ITEM-NEW'), isTrue); // optimistic add survived
      expect(_calls(requests, 'wishlist.add').single.data, {'item_code': 'ITEM-NEW'});
    });
  });

  group('FavouritesStore — session-boundary races', () {
    test('logout invalidates the in-flight list: relogin issues a fresh fetch and the stale snapshot is discarded', () async {
      // User A's wishlist.list hangs → A logs out → B logs in. B's refresh
      // must NOT adopt A's hung fetch: a second wishlist.list goes out, and
      // A's late snapshot must never populate B's store.
      final firstListGate = Completer<void>();
      var listCalls = 0;
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            if (options.path.endsWith('wishlist.list')) {
              listCalls += 1;
              if (listCalls == 1) {
                await firstListGate.future;
                handler.resolve(_envelope(options, [_card('ITEM-OF-USER-A')]));
                return;
              }
              handler.resolve(_envelope(options, [_card('ITEM-OF-USER-B')]));
              return;
            }
            handler.resolve(_envelope(options, {'ok': true}));
          },
        ),
      );
      final repo = WishlistRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      final session = _guestSessionWithFakeLogin();
      final store = FavouritesStore(repository: repo, session: session);

      await session.login(phone: '+9647700000001', password: 'p@ss');
      while (_calls(requests, 'wishlist.list').isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }

      await session.logout(); // A's fetch still hung
      await session.login(phone: '+9647700000002', password: 'p@ss');
      await store.sessionSyncDone; // B is FULLY hydrated first…
      expect(store.contains('ITEM-OF-USER-B'), isTrue);

      firstListGate.complete(); // …then A's straggler lands strictly last
      await Future<void>.delayed(Duration.zero); // let it settle

      expect(_calls(requests, 'wishlist.list'), hasLength(2),
          reason: 'relogin must issue its own wishlist.list, not adopt the hung one');
      expect(store.contains('ITEM-OF-USER-B'), isTrue,
          reason: "A's late snapshot must not overwrite B's applied hydrate");
      expect(store.contains('ITEM-OF-USER-A'), isFalse,
          reason: "user A's stale snapshot must never populate user B's store");
    });

    test('double-toggle serializes same-item mutations in tap order on the wire', () async {
      final addGate = Completer<void>();
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            if (options.path.endsWith('wishlist.add')) {
              await addGate.future; // hold the add on the wire
            }
            handler.resolve(_envelope(options, {'ok': true}));
          },
        ),
      );
      final repo = WishlistRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      final store = FavouritesStore(repository: repo, session: await _authedSession());

      final addFuture = store.toggle('ITEM-1'); // tap 1 → add (hung)
      expect(store.contains('ITEM-1'), isTrue);
      final removeFuture = store.toggle('ITEM-1'); // tap 2 while add in flight
      expect(store.contains('ITEM-1'), isFalse); // optimistic

      await Future<void>.delayed(Duration.zero);
      expect(_calls(requests, 'wishlist.remove'), isEmpty,
          reason: 'remove must queue behind the in-flight add, not race it');

      addGate.complete();
      await Future.wait([addFuture, removeFuture]);

      expect(_calls(requests, 'wishlist.add'), hasLength(1));
      expect(_calls(requests, 'wishlist.remove'), hasLength(1));
      expect(store.contains('ITEM-1'), isFalse); // UI and server agree
    });

    test('seed is a no-op for guests even with is_favourite payloads', () {
      final store = FavouritesStore(repository: _fakeRepository());
      store.seed([Product.fromJson(_card('ITEM-1'))]);
      expect(store.contains('ITEM-1'), isFalse);
    });
  });
}
