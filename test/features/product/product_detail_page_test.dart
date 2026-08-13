import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/features/product/product_detail_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

const _weightItemJson = {
  'item_code': 'WEIGHT-1',
  'item_name': 'Fresh Tomatoes',
  'description': 'Locally grown, hand-picked daily.',
  'price_per_uom': 2500,
  'uom': 'Kg',
  'sold_by_weight': true,
  'weight_step_g': 500,
  'min_g': 500,
  'max_g': 5000,
  'in_stock': true,
};

const _unitItemJson = {
  'item_code': 'UNIT-1',
  'item_name': 'Canned Beans',
  'price_per_uom': 3000,
  'uom': 'pc',
  'sold_by_weight': false,
  'in_stock': true,
};

const _outOfStockItemJson = {
  'item_code': 'OOS-1',
  'item_name': 'Sold Out Item',
  'price_per_uom': 5000,
  'uom': 'pc',
  'sold_by_weight': false,
  'in_stock': false,
};

ApiClient _clientFor(Map<String, dynamic> itemJson) => ApiClient(
      dio: buildFakeDio((options) => _envelope(options, itemJson)),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

Future<void> _openDetail(
  WidgetTester tester, {
  required CatalogRepository repo,
  String itemCode = 'ITEM-1',
  CartStore? cartStore,
  FavouritesStore? favouritesStore,
  SessionStore? sessionStore,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    wrapPage(
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ProductDetailPage(),
              settings: RouteSettings(arguments: itemCode),
            ),
          ),
          child: const Text('open'),
        ),
      ),
      providers: homeTestProviders(
        catalogRepository: repo,
        cartStore: cartStore,
        favouritesStore: favouritesStore,
        sessionStore: sessionStore,
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('ProductDetailPage — content', () {
    testWidgets('renders name, price per uom, description and in-stock badge', (tester) async {
      await _openDetail(tester, repo: CatalogRepository(_clientFor(_weightItemJson)), itemCode: 'WEIGHT-1');

      expect(find.text('Fresh Tomatoes'), findsOneWidget);
      expect(find.textContaining('IQD 2,500'), findsWidgets);
      expect(find.text('/ Kg'), findsOneWidget);
      expect(find.text('Locally grown, hand-picked daily.'), findsOneWidget);
      expect(find.text('In Stock'), findsOneWidget);
    });

    testWidgets('shows out-of-stock badge and disables Add-to-basket', (tester) async {
      final cart = CartStore(repository: buildFakeCartRepository());
      await _openDetail(
        tester,
        repo: CatalogRepository(_clientFor(_outOfStockItemJson)),
        itemCode: 'OOS-1',
        cartStore: cart,
        sessionStore: await buildAuthedSessionStore(),
      );

      expect(find.text('Out of Stock'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(
        find.descendant(of: find.byKey(const Key('addToBasketButton')), matching: find.byType(ElevatedButton)),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const Key('addToBasketButton')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(cart.count, 0);
    });

    testWidgets('shows a retry prompt when fetching the item fails', (tester) async {
      var callCount = 0;
      final client = ApiClient(
        dio: buildFakeDio((options) {
          callCount++;
          if (callCount == 1) {
            return Response(requestOptions: options, statusCode: 500, data: {'message': 'boom'});
          }
          return _envelope(options, _weightItemJson);
        }),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      );

      await _openDetail(tester, repo: CatalogRepository(client), itemCode: 'WEIGHT-1');

      expect(find.text('Something went wrong'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Fresh Tomatoes'), findsOneWidget);
    });
  });

  group('ProductDetailPage — weight selector (PRD E1 / J4)', () {
    testWidgets('starts at weight_step_g, steps to 1.0kg/1.5kg with live total price', (tester) async {
      await _openDetail(tester, repo: CatalogRepository(_clientFor(_weightItemJson)), itemCode: 'WEIGHT-1');

      expect(find.text('500 g'), findsOneWidget);
      expect(find.byKey(const Key('weightTotalPrice')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('weightTotalPrice'))).data,
        'IQD 1,250', // 0.5kg * 2500/kg
      );

      await tester.tap(find.byKey(const Key('weightIncrementButton')));
      await tester.pump();
      expect(find.text('1 kg'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('weightTotalPrice'))).data, 'IQD 2,500');

      await tester.tap(find.byKey(const Key('weightIncrementButton')));
      await tester.pump();
      expect(find.text('1.5 kg'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('weightTotalPrice'))).data, 'IQD 3,750');
    });

    testWidgets('clamps at max_g and min_g', (tester) async {
      await _openDetail(tester, repo: CatalogRepository(_clientFor(_weightItemJson)), itemCode: 'WEIGHT-1');

      // max_g is 5000 -> 9 taps of +500 from 500 reaches 5000 exactly.
      for (var i = 0; i < 9; i++) {
        await tester.tap(find.byKey(const Key('weightIncrementButton')));
        await tester.pump();
      }
      expect(find.text('5 kg'), findsOneWidget);
      await tester.tap(find.byKey(const Key('weightIncrementButton')));
      await tester.pump();
      expect(find.text('5 kg'), findsOneWidget); // stays clamped

      for (var i = 0; i < 9; i++) {
        await tester.tap(find.byKey(const Key('weightDecrementButton')));
        await tester.pump();
      }
      expect(find.text('500 g'), findsOneWidget);
      await tester.tap(find.byKey(const Key('weightDecrementButton')));
      await tester.pump();
      expect(find.text('500 g'), findsOneWidget); // stays clamped at min_g
    });

    testWidgets('authed add sends the final qtyKg to CartStore and shows a confirmation', (tester) async {
      final cart = CartStore(repository: buildFakeCartRepository());
      await _openDetail(
        tester,
        repo: CatalogRepository(_clientFor(_weightItemJson)),
        itemCode: 'WEIGHT-1',
        cartStore: cart,
        sessionStore: await buildAuthedSessionStore(),
      );

      await tester.tap(find.byKey(const Key('weightIncrementButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('weightIncrementButton')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('addToBasketButton')));
      await tester.pump();
      // `cart.add()` is now an async server call (even against a fake
      // dio) — under `flutter test`'s binding, resolving it needs a real
      // event-loop turn, not just a pumped frame. `runAsync` gives it one
      // without racing the SnackBar's ~4s auto-dismiss timer the way
      // `pumpAndSettle()` would.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();

      expect(cart.count, 1);
      expect(cart.items.single.qty, 1.5);
      expect(cart.items.single.itemCode, 'WEIGHT-1');
      expect(find.text('Added to cart'), findsOneWidget);
    });
  });

  group('ProductDetailPage — unit qty stepper', () {
    testWidgets('starts at 1 and steps by 1 with live total price', (tester) async {
      await _openDetail(tester, repo: CatalogRepository(_clientFor(_unitItemJson)), itemCode: 'UNIT-1');

      expect(find.text('1'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('qtyTotalPrice'))).data, 'IQD 3,000');

      await tester.tap(find.byKey(const Key('qtyIncrementButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('qtyIncrementButton')));
      await tester.pump();

      expect(find.text('3'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('qtyTotalPrice'))).data, 'IQD 9,000');
    });

    testWidgets('cannot step below 1', (tester) async {
      await _openDetail(tester, repo: CatalogRepository(_clientFor(_unitItemJson)), itemCode: 'UNIT-1');

      await tester.tap(find.byKey(const Key('qtyDecrementButton')));
      await tester.pump();

      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('authed add sends the final integer qty to CartStore', (tester) async {
      final cart = CartStore(repository: buildFakeCartRepository());
      await _openDetail(
        tester,
        repo: CatalogRepository(_clientFor(_unitItemJson)),
        itemCode: 'UNIT-1',
        cartStore: cart,
        sessionStore: await buildAuthedSessionStore(),
      );

      await tester.tap(find.byKey(const Key('qtyIncrementButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('qtyIncrementButton')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('addToBasketButton')));
      await tester.pumpAndSettle();

      expect(cart.count, 1);
      expect(cart.items.single.qty, 3);
    });
  });

  group('ProductDetailPage — guest gating', () {
    testWidgets('guest tap on Add-to-basket shows the login prompt and does not add to cart', (tester) async {
      final cart = CartStore(repository: buildFakeCartRepository());
      await _openDetail(
        tester,
        repo: CatalogRepository(_clientFor(_unitItemJson)),
        itemCode: 'UNIT-1',
        cartStore: cart,
      );

      await tester.tap(find.byKey(const Key('addToBasketButton')));
      await tester.pumpAndSettle();

      expect(find.text('Log in to continue'), findsOneWidget);
      expect(cart.count, 0);
    });

    testWidgets('guest tap on the favourite heart shows the login prompt and does not favourite', (tester) async {
      final favourites = FavouritesStore(repository: buildFakeWishlistRepository());
      await _openDetail(
        tester,
        repo: CatalogRepository(_clientFor(_unitItemJson)),
        itemCode: 'UNIT-1',
        favouritesStore: favourites,
      );

      await tester.tap(find.byKey(const Key('favouriteButton')));
      await tester.pumpAndSettle();

      expect(find.text('Log in to continue'), findsOneWidget);
      expect(favourites.contains('UNIT-1'), isFalse);
    });
  });

  group('ProductDetailPage — favourites', () {
    testWidgets('authed tap on the favourite heart toggles FavouritesStore', (tester) async {
      final session = await buildAuthedSessionStore();
      final favourites = FavouritesStore(
        repository: buildFakeWishlistRepository(),
        session: session,
      );
      await _openDetail(
        tester,
        repo: CatalogRepository(_clientFor(_unitItemJson)),
        itemCode: 'UNIT-1',
        favouritesStore: favourites,
        sessionStore: session,
      );

      expect(find.byIcon(Iconsax.heart5), findsNothing);
      await tester.tap(find.byKey(const Key('favouriteButton')));
      await tester.pump();

      expect(find.byIcon(Iconsax.heart5), findsOneWidget); // optimistic flip
      expect(favourites.contains('UNIT-1'), isTrue);

      // Drain the in-flight wishlist.add so no dio timer outlives the test.
      await tester.pumpAndSettle();
      expect(favourites.contains('UNIT-1'), isTrue); // server confirmed, no rollback
    });

    testWidgets('is_favourite in the detail payload seeds the store: heart starts filled', (tester) async {
      final session = await buildAuthedSessionStore();
      final favourites = FavouritesStore(
        repository: buildFakeWishlistRepository(),
        session: session,
      );
      await _openDetail(
        tester,
        repo: CatalogRepository(_clientFor({..._unitItemJson, 'is_favourite': true})),
        itemCode: 'UNIT-1',
        favouritesStore: favourites,
        sessionStore: session,
      );

      expect(favourites.contains('UNIT-1'), isTrue);
      expect(find.byIcon(Iconsax.heart5), findsOneWidget);
    });
  });
}
