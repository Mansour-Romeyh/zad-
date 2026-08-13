import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/data/cart_repository.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/zad_bottom_nav.dart';
import 'package:zad/models/product.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

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

/// Enough categories/banner/best-items to overflow a small viewport, so
/// the home tab's `ListView` is genuinely scrollable (used by the
/// tab-switch state-preservation test below).
ApiClient _tallContentClient() => ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) {
          return _envelope(options, [
            for (var i = 0; i < 6; i++) {'name': 'cat$i', 'label': 'Category $i', 'item_count': 5},
          ]);
        }
        if (options.path.endsWith('home.get_banners')) {
          return _envelope(options, [
            {'image': null, 'title': 'Banner'},
          ]);
        }
        if (options.path.endsWith('get_best_items')) {
          return _envelope(options, {
            'items': [
              for (var i = 0; i < 6; i++)
                {'item_code': 'ITEM-$i', 'item_name': 'Item $i', 'price_per_uom': 1000, 'in_stock': true},
            ],
            'page': 1,
            'has_more': false,
          });
        }
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home shows location header and decorative search', (tester) async {
    await tester.pumpWidget(wrapPage(const HomePage(), providers: homeTestProviders()));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Baghdad'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget); // hint
    expect(find.byIcon(Iconsax.location), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse); // non-editable entry point
  });

  testWidgets('tapping the home search field opens /search', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        routes: {'/search': (_) => const Scaffold(body: Text('search-page'))},
        providers: homeTestProviders(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Search')); // the field's hint area
    await tester.pumpAndSettle();

    expect(find.text('search-page'), findsOneWidget);
  });

  testWidgets('bottom nav switches active item locally', (tester) async {
    await tester.pumpWidget(wrapPage(const HomePage(), providers: homeTestProviders()));
    await tester.pumpAndSettle();
    // Scope to the nav bar: heart/bag icons also appear elsewhere on home.
    final nav = find.byType(ZadBottomNav);
    Finder navIcon(IconData d) =>
        find.descendant(of: nav, matching: find.byIcon(d));
    Icon iconOf(IconData d) => tester.widget<Icon>(navIcon(d));
    // Home icon is active (primary) initially.
    expect(iconOf(Iconsax.home_2).color, ZadColors.primary);
    // Tap the heart nav item — it becomes active, home becomes inactive.
    await tester.tap(navIcon(Iconsax.heart));
    await tester.pump();
    expect(iconOf(Iconsax.heart).color, ZadColors.primary);
    expect(iconOf(Iconsax.home_2).color, ZadColors.ink);
  });

  testWidgets('tapping the profile nav item shows the guest login prompt', (tester) async {
    final store = buildGuestSessionStore();
    await store.restore();
    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(sessionStore: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Iconsax.user));
    await tester.pump();

    expect(find.text('Log in to view your profile'), findsOneWidget);
    expect(find.text('Baghdad'), findsNothing); // home content is gone
  });

  testWidgets('tapping the basket nav item shows the basket tab and hides home content', (tester) async {
    await tester.pumpWidget(wrapPage(const HomePage(), providers: homeTestProviders()));
    await tester.pumpAndSettle();

    // Scope to the nav bar: `LocationHeader` on the (still-mounted, active)
    // home tab also has a decorative bag icon.
    final nav = find.byType(ZadBottomNav);
    await tester.tap(find.descendant(of: nav, matching: find.byIcon(Iconsax.bag_2)));
    await tester.pump();

    expect(find.text('Your basket is empty'), findsOneWidget);
    expect(find.text('Baghdad'), findsNothing); // home content is gone
  });

  testWidgets('the basket nav badge shows the cart count and hides at zero', (tester) async {
    final cart = CartStore(repository: buildFakeCartRepository());
    await tester.pumpWidget(
      wrapPage(const HomePage(), providers: homeTestProviders(cartStore: cart)),
    );
    await tester.pumpAndSettle();

    expect(find.text('1'), findsNothing);

    await cart.add(_unitProduct);
    await tester.pump();

    final nav = find.byType(ZadBottomNav);
    expect(find.descendant(of: nav, matching: find.text('1')), findsOneWidget);
  });

  testWidgets("switching tabs keeps each tab's own state alive (IndexedStack)", (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _tallContentClient();
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

    final homeList = find.byType(Scrollable).first;
    await tester.drag(homeList, const Offset(0, -250));
    await tester.pumpAndSettle();
    final offsetBeforeSwitch = tester.state<ScrollableState>(homeList).position.pixels;
    expect(offsetBeforeSwitch, greaterThan(0)); // actually scrolled, not just overscroll-bounced

    final nav = find.byType(ZadBottomNav);
    await tester.tap(find.descendant(of: nav, matching: find.byIcon(Iconsax.bag_2)));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: nav, matching: find.byIcon(Iconsax.home_2)));
    await tester.pumpAndSettle();

    // An `IndexedStack` never unmounts the other tabs, so the home list's
    // `Scrollable` keeps the exact same `ScrollPosition` object across the
    // round trip — a naive `if (tab == home) ... else ...` swap would have
    // rebuilt it from scratch and reset the offset to 0.
    final offsetAfterSwitch = tester.state<ScrollableState>(homeList).position.pixels;
    expect(offsetAfterSwitch, offsetBeforeSwitch);
  });

  testWidgets('opening the basket tab refreshes the server cart when authed', (tester) async {
    final requests = <RequestOptions>[];
    final dio = buildFakeDio(
      (options) => _envelope(options, {
        'items': <dynamic>[],
        'totals': {'net_total': 0, 'grand_total': 0},
      }),
      capturedRequests: requests,
    );
    final repo = CartRepository(
      ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
    );
    final session = await buildAuthedSessionStore();
    final cart = CartStore(repository: repo, session: session);

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(cartStore: cart, sessionStore: session),
      ),
    );
    await tester.pumpAndSettle();
    Iterable<RequestOptions> gets() => requests.where((r) => r.path.endsWith('cart.get'));
    expect(gets(), isEmpty); // no fetch until the basket is opened

    final nav = find.byType(ZadBottomNav);
    await tester.tap(find.descendant(of: nav, matching: find.byIcon(Iconsax.bag_2)));
    await tester.pumpAndSettle();

    expect(gets(), hasLength(1)); // tab activation triggered CartStore.refresh()
  });

  testWidgets('opening the favourites tab refreshes the wishlist when authed', (tester) async {
    final requests = <RequestOptions>[];
    final session = await buildAuthedSessionStore();
    final favourites = FavouritesStore(
      repository: buildFakeWishlistRepository(capturedRequests: requests),
      session: session,
    );

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(favouritesStore: favourites, sessionStore: session),
      ),
    );
    await tester.pumpAndSettle();
    Iterable<RequestOptions> lists() => requests.where((r) => r.path.endsWith('wishlist.list'));
    expect(lists(), isEmpty); // no fetch until the tab is opened

    final nav = find.byType(ZadBottomNav);
    await tester.tap(find.descendant(of: nav, matching: find.byIcon(Iconsax.heart)));
    await tester.pumpAndSettle();

    expect(lists(), hasLength(1)); // tab activation triggered FavouritesStore.refresh()
  });
}
