import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/category_grid.dart';
import 'package:zad/features/home/widgets/promo_banner.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

const _oneCategory = [
  {'name': 'veg', 'label': 'Vegetables & Fruits', 'item_count': 10},
];

const _oneBanner = [
  {'image': null, 'title': 'Ramadan Sale'},
];

// Paged list endpoints (get_best_items, items_by_category) return the
// `{items, page, has_more}` envelope — the real backend contract.
const _oneBestItem = {
  'items': [
    {
      'item_code': 'ITEM-1',
      'item_name': 'Fresh Tomatoes',
      'price_per_uom': 2500,
      'uom': 'Kg',
      'in_stock': true,
    },
  ],
  'page': 1,
  'has_more': false,
};

Map<String, dynamic> _pagedEnvelope(List<Map<String, dynamic>> items) =>
    {'items': items, 'page': 1, 'has_more': false};

ApiClient _successClient({List<RequestOptions>? captured}) => ApiClient(
      dio: buildFakeDio(
        (options) {
          if (options.path.endsWith('get_categories')) return _envelope(options, _oneCategory);
          if (options.path.endsWith('home.get_banners')) return _envelope(options, _oneBanner);
          if (options.path.endsWith('get_best_items')) return _envelope(options, _oneBestItem);
          return _envelope(options, <dynamic>[]);
        },
        capturedRequests: captured,
      ),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

void main() {
  testWidgets('home renders all three sections from fake repositories on success', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _successClient();

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vegetables & Fruits'), findsOneWidget);
    expect(find.byType(PromoBanner), findsOneWidget);
    expect(find.text('Fresh Tomatoes'), findsOneWidget);
  });

  testWidgets('zero banners collapse the promo section entirely (no card, no stray gap)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Categories and best items succeed with data; banners succeed empty.
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) return _envelope(options, _oneCategory);
        if (options.path.endsWith('get_best_items')) return _envelope(options, _oneBestItem);
        return _envelope(options, <dynamic>[]); // banners: empty
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No promo card and no dead "Shop Now" CTA.
    expect(find.byType(PromoBanner), findsNothing);
    expect(find.text('Shop Now'), findsNothing);
    // No stray gap: with the promo slot gone, the category grid and the
    // Best Deal header are separated by exactly one section gap.
    final gridBottom = tester.getBottomLeft(find.byType(CategoryGrid)).dy;
    final bestDealTop = tester.getTopLeft(find.text('Best Deal')).dy;
    expect(bestDealTop - gridBottom, ZadSpacing.sectionGap);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a non-empty banner list renders the promo card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _successClient();

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PromoBanner), findsOneWidget);
    // Image-only banner: the title and CTA are no longer rendered.
    expect(find.text('Ramadan Sale'), findsNothing);
    expect(find.text('Shop Now'), findsNothing);
  });

  testWidgets('a failed section shows a retry button; other sections still render', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) {
          return Response(requestOptions: options, statusCode: 500, data: {'message': 'boom'});
        }
        if (options.path.endsWith('home.get_banners')) return _envelope(options, _oneBanner);
        if (options.path.endsWith('get_best_items')) return _envelope(options, _oneBestItem);
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // Other sections are unaffected by the categories failure.
    expect(find.byType(PromoBanner), findsOneWidget);
    expect(find.text('Fresh Tomatoes'), findsOneWidget);
  });

  testWidgets('tapping retry re-fetches just that section and recovers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var categoryCalls = 0;
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) {
          categoryCalls++;
          if (categoryCalls == 1) {
            return Response(requestOptions: options, statusCode: 500, data: {'message': 'boom'});
          }
          return _envelope(options, _oneCategory);
        }
        if (options.path.endsWith('home.get_banners')) return _envelope(options, _oneBanner);
        if (options.path.endsWith('get_best_items')) return _envelope(options, _oneBestItem);
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsNothing);
    expect(find.text('Vegetables & Fruits'), findsOneWidget);
    expect(categoryCalls, 2);
  });

  testWidgets('empty categories/best-items show empty-state text, not a crash', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_best_items')) {
          return _envelope(options, _pagedEnvelope(const []));
        }
        return _envelope(options, <dynamic>[]); // categories/banners: bare lists
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No categories yet'), findsOneWidget);
    expect(find.text('No items yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pull-to-refresh re-fetches all three sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final captured = <RequestOptions>[];
    final client = _successClient(captured: captured);

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    int callsTo(String suffix) => captured.where((r) => r.path.endsWith(suffix)).length;
    expect(callsTo('get_categories'), 1);
    expect(callsTo('home.get_banners'), 1);
    expect(callsTo('get_best_items'), 1);

    // Fling from the location header text: it sits directly in the outer
    // (vertical) ListView, clear of the nested non-scrollable category grid
    // and horizontal best-deal list, so the gesture reliably reaches the
    // RefreshIndicator's Scrollable. RefreshIndicator arms once the drag
    // exceeds 25% of its own (viewport) extent, so on this tall test
    // surface the fling distance must clear ~550px — 900px leaves margin.
    await tester.fling(find.text('Home'), const Offset(0.0, 900.0), 1000.0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1)); // finish the scroll animation
    await tester.pump(const Duration(seconds: 1)); // finish the indicator settle animation
    await tester.pump(const Duration(seconds: 1)); // finish the indicator hide animation
    await tester.pumpAndSettle();

    expect(callsTo('get_categories'), 2);
    expect(callsTo('home.get_banners'), 2);
    expect(callsTo('get_best_items'), 2);
  });

  testWidgets('out-of-stock item shows a badge and its Add button is disabled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_best_items')) {
          return _envelope(options, _pagedEnvelope([
            {
              'item_code': 'OOS-1',
              'item_name': 'Sold Out Item',
              'price_per_uom': 5000,
              'uom': 'pc',
              'in_stock': false,
            },
          ]));
        }
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    final cart = CartStore(repository: buildFakeCartRepository());

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
          cartStore: cart,
          sessionStore: await buildAuthedSessionStore(),
        ),
        // Disabled Add area falls through to the card's body tap (view
        // detail — harmless even out of stock), so the detail route needs a
        // generator here too.
        routes: {'/product': (_) => const Scaffold(body: Text('PRODUCT_DETAIL_MARKER'))},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Out of Stock'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.add).first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(cart.count, 0);
  });

  testWidgets('guest tap on Add shows the login prompt and does not add to cart', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _successClient();
    final cart = CartStore(repository: buildFakeCartRepository());

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
          cartStore: cart,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Log in to continue'), findsOneWidget);
    expect(cart.count, 0);
  });

  testWidgets('authed tap on Add for a unit item calls CartStore.add', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_best_items')) {
          return _envelope(options, _pagedEnvelope([
            {
              'item_code': 'UNIT-1',
              'item_name': 'Canned Beans',
              'price_per_uom': 3000,
              'uom': 'pc',
              'in_stock': true,
              'sold_by_weight': false,
            },
          ]));
        }
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    final cart = CartStore(repository: buildFakeCartRepository());

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
          cartStore: cart,
          sessionStore: await buildAuthedSessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(cart.count, 1);
    expect(cart.items.single.itemCode, 'UNIT-1');
  });

  testWidgets('authed tap on Add for a weight item adds its minimum weight straight to the cart', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_best_items')) {
          return _envelope(options, _pagedEnvelope([
            {
              'item_code': 'WEIGHT-1',
              'item_name': 'Fresh Tomatoes',
              'price_per_uom': 2500,
              'uom': 'Kg',
              'in_stock': true,
              'sold_by_weight': true,
            },
          ]));
        }
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    final cart = CartStore(repository: buildFakeCartRepository());

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
          cartStore: cart,
          sessionStore: await buildAuthedSessionStore(),
        ),
        // If (+) still (wrongly) navigated, this marker would render — asserted
        // absent below.
        routes: {'/product': (_) => const Scaffold(body: Text('PRODUCT_DETAIL_MARKER'))},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).first, warnIfMissed: false);
    await tester.pumpAndSettle();

    // (+) adds the item's minimum sellable weight straight to the basket
    // (weight_step_g defaults to 500 g -> 0.5 kg) without opening the detail
    // page (PRD E1); the basket weight stepper fine-tunes grams afterwards.
    expect(find.text('PRODUCT_DETAIL_MARKER'), findsNothing);
    expect(cart.count, 1);
    expect(cart.items.single.itemCode, 'WEIGHT-1');
    expect(cart.items.single.qty, 0.5);
  });
}
