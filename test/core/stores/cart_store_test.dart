import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/data/cart_repository.dart';
import 'package:zad/models/product.dart';

import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

const _unitProduct = Product(
  id: 'ITEM-1',
  nameEn: 'Milk',
  nameAr: 'حليب',
  unitEn: '1 Ltr',
  unitAr: '1 لتر',
  price: 1500,
  imagePath: '',
  itemCode: 'ITEM-1',
  pricePerUom: 1500,
  uom: 'pc',
);

const _weightProduct = Product(
  id: 'ITEM-2',
  nameEn: 'Tomatoes',
  nameAr: 'طماطم',
  unitEn: 'Kg',
  unitAr: 'كغم',
  price: 2000,
  imagePath: '',
  itemCode: 'ITEM-2',
  pricePerUom: 2000,
  uom: 'Kg',
  soldByWeight: true,
  weightStepG: 500,
  minG: 500,
  maxG: 5000,
);

/// A [CartRepository] whose fake dio echoes back a single line for whatever
/// was posted (add_item/update_item), so store-level tests can assert
/// "the right thing reached the server" without hand-building full cart
/// snapshots for every call. [onRequest] lets a test observe/override
/// individual calls (e.g. to assert `merge`'s payload).
CartRepository _fakeRepository({
  void Function(RequestOptions options)? onRequest,
  List<Map<String, dynamic>>? nextItems,
  List<String> nextWarnings = const [],
}) {
  final dio = buildFakeDio((options) {
    onRequest?.call(options);
    if (options.path.endsWith('cart.add_item') || options.path.endsWith('cart.update_item')) {
      final data = options.data as Map<String, dynamic>;
      final row = data['row'] as String? ?? 'row-${data['item_code']}';
      final itemCode = data['item_code'] as String? ?? row.replaceFirst('row-', '');
      return _envelope(options, {
        'items': nextItems ??
            [
              {
                'name': row,
                'item_code': itemCode,
                'qty': data['qty'],
                'uom': data['uom'],
                'rate': 1000,
                'amount': 1000,
                'item_name': itemCode,
              },
            ],
        'totals': {'net_total': 1000, 'grand_total': 1000},
        if (nextWarnings.isNotEmpty) 'warnings': nextWarnings,
      });
    }
    return _envelope(options, {
      'items': nextItems ?? <dynamic>[],
      'totals': {'net_total': 0, 'grand_total': 0},
      if (nextWarnings.isNotEmpty) 'warnings': nextWarnings,
    });
  });
  return CartRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

/// A guest [SessionStore] whose `login()` succeeds against a fake dio (PRD
/// F1 login shape) instead of hitting the network — for the merge-on-login
/// tests, which need a real guest→authed transition to fire the listener.
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
  // A fake (never-real-network) dio for auth calls the store's own tests
  // might trigger, e.g. `logout()`'s best-effort server round trip.
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CartStore — guest local cart', () {
    test('starts empty', () {
      final store = CartStore(repository: _fakeRepository());
      expect(store.count, 0);
      expect(store.items, isEmpty);
    });

    test('add appends a unit-item line and notifies listeners', () async {
      final store = CartStore(repository: _fakeRepository());
      var notified = 0;
      store.addListener(() => notified++);

      await store.add(_unitProduct);

      expect(store.count, 1);
      expect(store.items.single.itemCode, 'ITEM-1');
      expect(store.items.single.qty, 1);
      expect(notified, greaterThan(0));
    });

    test('add accepts qtyKg for weight-sold items', () async {
      final store = CartStore(repository: _fakeRepository());

      await store.add(_weightProduct, qtyKg: 0.5);

      expect(store.items.single.itemCode, 'ITEM-2');
      expect(store.items.single.qty, 0.5);
      expect(store.items.single.soldByWeight, isTrue);
    });

    test('adding the same item twice sums qty into one line', () async {
      final store = CartStore(repository: _fakeRepository());

      await store.add(_unitProduct, qty: 1);
      await store.add(_unitProduct, qty: 2);

      expect(store.count, 1);
      expect(store.items.single.qty, 3);
    });

    test('add persists to shared_preferences', () async {
      final store = CartStore(repository: _fakeRepository());

      await store.add(_unitProduct, qty: 2);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kGuestCartKey);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as List;
      expect(decoded, hasLength(1));
      expect(decoded.single['item_code'], 'ITEM-1');
      expect(decoded.single['qty'], 2);
    });

    test('guest cart persists and restores across store recreation', () async {
      final store1 = CartStore(repository: _fakeRepository());
      await store1.add(_unitProduct, qty: 2);
      await store1.add(_weightProduct, qtyKg: 1.5);

      final store2 = CartStore(repository: _fakeRepository());
      await store2.restore();

      expect(store2.count, 2);
      final byCode = {for (final l in store2.items) l.itemCode: l};
      expect(byCode['ITEM-1']!.qty, 2);
      expect(byCode['ITEM-2']!.qty, 1.5);
      expect(byCode['ITEM-2']!.soldByWeight, isTrue);
      expect(byCode['ITEM-2']!.weightStepG, 500);
    });

    test('restore with nothing saved leaves an empty cart', () async {
      final store = CartStore(repository: _fakeRepository());

      await store.restore();

      expect(store.count, 0);
    });

    test('remove drops the line and persists', () async {
      final store = CartStore(repository: _fakeRepository());
      await store.add(_unitProduct);
      final id = store.items.single.id;

      await store.remove(id);

      expect(store.items, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuestCartKey), isNull);
    });

    test('clear empties the cart and persisted storage', () async {
      final store = CartStore(repository: _fakeRepository());
      await store.add(_unitProduct);
      await store.add(_weightProduct, qtyKg: 1);

      await store.clear();

      expect(store.count, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuestCartKey), isNull);
    });

    test('totals sum price * qty across guest lines', () async {
      final store = CartStore(repository: _fakeRepository());
      await store.add(_unitProduct, qty: 2); // 1500 * 2 = 3000
      await store.add(_weightProduct, qtyKg: 0.5); // 2000 * 0.5 = 1000

      expect(store.totals.netTotal, 4000);
      expect(store.totals.grandTotal, 4000);
    });

    test('badge count reflects number of lines, not total qty', () async {
      final store = CartStore(repository: _fakeRepository());
      await store.add(_unitProduct, qty: 5);
      expect(store.count, 1);
      await store.add(_weightProduct, qtyKg: 2);
      expect(store.count, 2);
    });
  });

  group('CartStore — weight steppers (PRD E1)', () {
    test('increment/decrement step by weight_step_g, clamped to [min_g, max_g]', () async {
      final store = CartStore(repository: _fakeRepository());
      await store.add(_weightProduct, qtyKg: 0.5);
      final line = store.items.single;

      expect(store.canDecrement(line), isFalse); // already at min_g
      expect(store.canIncrement(line), isTrue);

      await store.increment(line);
      expect(store.items.single.qty, 1.0);

      await store.increment(store.items.single);
      expect(store.items.single.qty, 1.5);

      await store.decrement(store.items.single);
      expect(store.items.single.qty, 1.0);
    });

    test('increment clamps at max_g', () async {
      final store = CartStore(repository: _fakeRepository());
      await store.add(_weightProduct, qtyKg: 4.5);

      await store.increment(store.items.single); // -> 5.0 (max_g)
      expect(store.items.single.qty, 5.0);
      expect(store.canIncrement(store.items.single), isFalse);

      await store.increment(store.items.single); // stays clamped
      expect(store.items.single.qty, 5.0);
    });

    test('unit items step by 1, clamped at a minimum of 1', () async {
      final store = CartStore(repository: _fakeRepository());
      await store.add(_unitProduct, qty: 1);

      expect(store.canDecrement(store.items.single), isFalse);
      await store.decrement(store.items.single);
      expect(store.items.single.qty, 1);

      await store.increment(store.items.single);
      expect(store.items.single.qty, 2);
    });
  });

  group('CartStore — authed server cart', () {
    test('add calls repository.addItem then reflects the server snapshot', () async {
      final session = await _authedSession();
      final store = CartStore(repository: _fakeRepository(), session: session);
      await store.restore();

      await store.add(_unitProduct, qty: 3);

      expect(store.count, 1);
      expect(store.items.single.itemCode, 'ITEM-1');
      expect(store.items.single.qty, 3);
    });

    test('totals come from the server response, not a local computation', () async {
      final session = await _authedSession();
      final repo = _fakeRepository();
      final store = CartStore(repository: repo, session: session);
      await store.restore();

      await store.add(_unitProduct, qty: 3);

      expect(store.totals.netTotal, 1000); // fixture rate, not price snapshot math
      expect(store.totals.grandTotal, 1000);
    });

    test('updateQty reflects the new qty at once, then debounces update_item with the row id', () async {
      final session = await _authedSession();
      RequestOptions? captured;
      final store = CartStore(
        repository: _fakeRepository(onRequest: (o) {
          if (o.path.endsWith('cart.update_item')) captured = o;
        }),
        session: session,
        syncDebounce: const Duration(milliseconds: 20),
      );
      await store.restore();
      await store.add(_unitProduct, qty: 1);
      final row = store.items.single.id;

      await store.updateQty(row, 5);

      expect(store.items.single.qty, 5); // optimistic, before any server call
      expect(captured, isNull); // still within the debounce window

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(captured, isNotNull);
      expect(captured!.data, {'row': row, 'qty': 5});
      expect(store.items.single.qty, 5);
    });

    test('remove hides the line at once, then debounces remove_item with the row id', () async {
      final session = await _authedSession();
      RequestOptions? captured;
      final store = CartStore(
        repository: _fakeRepository(onRequest: (o) {
          if (o.path.endsWith('cart.remove_item')) captured = o;
        }),
        session: session,
        syncDebounce: const Duration(milliseconds: 20),
      );
      await store.restore();
      await store.add(_unitProduct, qty: 1);
      final row = store.items.single.id;

      await store.remove(row);

      expect(store.items, isEmpty); // optimistic, before any server call

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(captured, isNotNull);
      expect(captured!.data, {'row': row});
    });

    test('clear calls repository.clear', () async {
      final session = await _authedSession();
      var cleared = false;
      final store = CartStore(
        repository: _fakeRepository(onRequest: (o) {
          if (o.path.endsWith('cart.clear')) cleared = true;
        }),
        session: session,
      );
      await store.restore();

      await store.clear();

      expect(cleared, isTrue);
    });

    test('a zero-stock add throws and leaves busy/error observable', () async {
      final session = await _authedSession();
      final dio = buildFakeDio((options) {
        if (options.path.endsWith('cart.get')) {
          return _envelope(options, {'items': <dynamic>[], 'totals': {'net_total': 0, 'grand_total': 0}});
        }
        return Response(
          requestOptions: options,
          statusCode: 409,
          data: {'message': 'Out of stock', 'items': ['ITEM-1']},
        );
      });
      final repo = CartRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      final store = CartStore(repository: repo, session: session);
      await store.restore();

      await expectLater(store.add(_unitProduct), throwsA(isA<OutOfStockException>()));
      expect(store.error, isA<OutOfStockException>());
      expect(store.busy, isFalse);
    });

    test('server warnings are surfaced on the warnings stream', () async {
      final session = await _authedSession();
      final store = CartStore(repository: _fakeRepository(nextWarnings: const ['Only 2 left of ITEM-1']), session: session);
      await store.restore();

      final events = <List<String>>[];
      store.warnings.listen(events.add);

      await store.add(_unitProduct);
      await Future<void>.delayed(Duration.zero);

      expect(events, [
        ['Only 2 left of ITEM-1'],
      ]);
    });
  });

  group('CartStore — login/logout transitions (PRD J2)', () {
    test('login merges guest lines to the server, then empties local storage', () async {
      final session = _guestSessionWithFakeLogin();
      final mergeCalls = <dynamic>[];
      final repo = _fakeRepository(onRequest: (o) {
        if (o.path.endsWith('cart.merge')) mergeCalls.add(o.data);
      });
      final store = CartStore(repository: repo, session: session);
      await store.restore();
      await store.add(_unitProduct, qty: 2);
      await store.add(_weightProduct, qtyKg: 1.5);

      await session.login(phone: '+9647701234567', password: 'p@ss');
      await store.sessionSyncDone;

      expect(mergeCalls, hasLength(1));
      final lines = (mergeCalls.single as Map)['lines'] as List;
      expect(lines, containsAll([
        {'item_code': 'ITEM-1', 'qty': 2.0},
        {'item_code': 'ITEM-2', 'qty': 1.5},
      ]));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuestCartKey), isNull);
    });

    test('login with an empty guest cart does not call merge', () async {
      final session = _guestSessionWithFakeLogin();
      var mergeCalled = false;
      final repo = _fakeRepository(onRequest: (o) {
        if (o.path.endsWith('cart.merge')) mergeCalled = true;
      });
      final store = CartStore(repository: repo, session: session);
      await store.restore();

      await session.login(phone: '+9647701234567', password: 'p@ss');
      await store.sessionSyncDone;

      expect(mergeCalled, isFalse);
    });

    test('login refreshes from the server after merging', () async {
      final session = _guestSessionWithFakeLogin();
      final store = CartStore(
        repository: _fakeRepository(nextItems: const [
          {'name': 'row-9', 'item_code': 'ITEM-9', 'qty': 1, 'rate': 500, 'amount': 500},
        ]),
        session: session,
      );
      await store.restore();

      await session.login(phone: '+9647701234567', password: 'p@ss');
      await store.sessionSyncDone;

      expect(store.items.single.itemCode, 'ITEM-9');
    });

    test('logout reverts to an empty guest cart without touching guest storage', () async {
      final session = await _authedSession();
      final store = CartStore(
        repository: _fakeRepository(nextItems: const [
          {'name': 'row-9', 'item_code': 'ITEM-9', 'qty': 1, 'rate': 500, 'amount': 500},
        ]),
        session: session,
      );
      await store.restore();
      expect(store.items, isNotEmpty);

      await session.logout();

      expect(store.items, isEmpty);
      expect(store.count, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuestCartKey), isNull);
    });
  });

  group('CartStore — merge-failure resilience (PRD J2)', () {
    /// A repository whose `cart.merge` fails while [failMerge] is flipped
    /// on; everything else succeeds. `cart.get` returns [serverItems] so
    /// the post-heal state is observable.
    (CartRepository, List<RequestOptions>) mergeFailingRepository(
      bool Function() failMerge, {
      List<Map<String, dynamic>> serverItems = const [],
    }) {
      final mergeRequests = <RequestOptions>[];
      final dio = buildFakeDio((options) {
        if (options.path.endsWith('cart.merge')) {
          mergeRequests.add(options);
          if (failMerge()) {
            return Response(
              requestOptions: options,
              statusCode: 500,
              data: {'message': 'boom'},
            );
          }
        }
        return _envelope(options, {
          'items': options.path.endsWith('cart.get') ? serverItems : <dynamic>[],
          'totals': {'net_total': 0, 'grand_total': 0},
        });
      });
      final repo = CartRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      return (repo, mergeRequests);
    }

    test('a failed merge on login keeps guest lines persisted and emits a warning', () async {
      final session = _guestSessionWithFakeLogin();
      final (repo, mergeRequests) = mergeFailingRepository(() => true);
      final store = CartStore(repository: repo, session: session);
      await store.restore();
      await store.add(_unitProduct, qty: 2);

      final events = <List<String>>[];
      store.warnings.listen(events.add);

      await session.login(phone: '+9647701234567', password: 'p@ss');
      await store.sessionSyncDone; // must not throw despite the failed merge
      await Future<void>.delayed(Duration.zero); // deliver the stream event

      expect(mergeRequests, hasLength(1));
      expect(events, [
        [kCartSyncFailedWarning],
      ]);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kGuestCartKey);
      expect(raw, isNotNull); // guest lines survived the failed merge
      expect(jsonDecode(raw!).single['item_code'], 'ITEM-1');
    });

    test('a later refresh() retries the pending merge, clears local, shows the server cart', () async {
      final session = _guestSessionWithFakeLogin();
      var failMerge = true;
      final (repo, mergeRequests) = mergeFailingRepository(
        () => failMerge,
        serverItems: const [
          {'name': 'row-1', 'item_code': 'ITEM-1', 'qty': 2, 'rate': 1500, 'amount': 3000},
        ],
      );
      final store = CartStore(repository: repo, session: session);
      await store.restore();
      await store.add(_unitProduct, qty: 2);

      await session.login(phone: '+9647701234567', password: 'p@ss');
      await store.sessionSyncDone; // merge failed; lines pending

      failMerge = false;
      await store.refresh(); // self-heals: merge retried, then cart.get

      expect(mergeRequests, hasLength(2));
      final retried = (mergeRequests.last.data as Map)['lines'] as List;
      expect(retried, [
        {'item_code': 'ITEM-1', 'qty': 2.0},
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuestCartKey), isNull); // local cleared after success
      expect(store.items.single.itemCode, 'ITEM-1'); // server cart shown
      expect(store.items.single.id, 'row-1');
    });

    test('restore() while authed retries a pending merge from a previous session', () async {
      // A previous session's failed merge left guest lines persisted.
      SharedPreferences.setMockInitialValues({
        kGuestCartKey: jsonEncode([
          {'item_code': 'ITEM-1', 'qty': 2, 'price': 1500, 'name_en': 'Milk', 'name_ar': 'حليب'},
        ]),
      });
      final session = await _authedSession();
      final (repo, mergeRequests) = mergeFailingRepository(() => false);
      final store = CartStore(repository: repo, session: session);

      await store.restore();

      expect(mergeRequests, hasLength(1));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuestCartKey), isNull);
    });

    test('a mutation arriving while a merge is in flight awaits the SAME merge (no double-send)', () async {
      // A pending merge from a previous session (the same race exists for
      // the login-triggered merge: add() fired right after the login sheet
      // pops, before merge resolves — the canonical J2 flow).
      SharedPreferences.setMockInitialValues({
        kGuestCartKey: jsonEncode([
          {'item_code': 'ITEM-1', 'qty': 2, 'price': 1500, 'name_en': 'Milk', 'name_ar': 'حليب'},
        ]),
      });
      final session = await _authedSession();

      // A repository whose cart.merge blocks on [mergeGate], so the test
      // controls exactly when the in-flight merge completes.
      final mergeGate = Completer<void>();
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            requests.add(options);
            if (options.path.endsWith('cart.merge')) {
              await mergeGate.future;
            }
            handler.resolve(
              _envelope(options, {
                'items': <dynamic>[],
                'totals': {'net_total': 0, 'grand_total': 0},
              }),
            );
          },
        ),
      );
      final repo = CartRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      final store = CartStore(repository: repo, session: session);

      Iterable<RequestOptions> merges() => requests.where((r) => r.path.endsWith('cart.merge'));

      // restore() starts the pending merge; it blocks on the gate.
      final restoreFuture = store.restore();
      while (merges().isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(merges(), hasLength(1)); // in flight

      // Second mutation arrives while the merge is still in flight.
      final addFuture = store.add(_unitProduct, qty: 1);
      await Future<void>.delayed(Duration.zero);

      mergeGate.complete();
      await Future.wait([restoreFuture, addFuture]);

      // Exactly ONE cart.merge — the add awaited the in-flight one instead
      // of re-posting the same lines (which the server would have summed,
      // doubling the quantity).
      final mergeCalls = merges().toList();
      expect(mergeCalls, hasLength(1));
      expect((mergeCalls.single.data as Map)['lines'], [
        {'item_code': 'ITEM-1', 'qty': 2.0},
      ]);
      // The add itself still went through, once.
      expect(requests.where((r) => r.path.endsWith('cart.add_item')), hasLength(1));
      // Pending state fully consumed: local storage empty, and a later
      // refresh() does not re-merge.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kGuestCartKey), isNull);
      await store.refresh();
      expect(merges(), hasLength(1));
    });
  });

  group('CartStore — line totals (server amount)', () {
    test('authed lines use the server amount when present (discounts etc.)', () async {
      final session = await _authedSession();
      final store = CartStore(
        repository: _fakeRepository(nextItems: const [
          // amount deliberately != rate * qty — the server is authoritative.
          {'name': 'row-1', 'item_code': 'ITEM-1', 'qty': 2, 'rate': 1500, 'amount': 2750},
        ]),
        session: session,
      );
      await store.restore();

      expect(store.items.single.lineTotal, 2750);
    });

    test('guest lines fall back to price * qty', () async {
      final store = CartStore(repository: _fakeRepository());
      await store.add(_unitProduct, qty: 2);

      expect(store.items.single.lineTotal, 3000); // 1500 * 2
    });
  });

  test('lineFor returns the guest line for an item, else null', () async {
    final store = CartStore(repository: _fakeRepository());
    addTearDown(store.dispose);

    expect(store.lineFor('UNIT-1'), isNull); // empty cart

    await store.add(
      Product.fromJson(const {
        'item_code': 'UNIT-1',
        'item_name': 'Canned Beans',
        'price_per_uom': 3000,
        'uom': 'pc',
        'in_stock': true,
      }),
    );

    expect(store.lineFor('UNIT-1')?.qty, 1);
    expect(store.lineFor('NOPE'), isNull);
  });
}
