import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/data/wishlist_repository.dart';
import 'package:zad/features/favourites/favourites_tab.dart';
import 'package:zad/features/home/widgets/product_card.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

Map<String, dynamic> _card(String code, String name) => {
      'item_code': code,
      'item_name': name,
      'price_per_uom': 1500,
      'uom': 'pc',
      'in_stock': true,
      'is_favourite': true,
    };

Widget _page({
  required FavouritesStore favourites,
  required SessionStore session,
  CartStore? cart,
  Map<String, WidgetBuilder> routes = const {},
}) {
  return wrapPage(
    const Scaffold(body: FavouritesTab()),
    routes: routes,
    providers: homeTestProviders(
      favouritesStore: favourites,
      sessionStore: session,
      cartStore: cart,
    ),
  );
}

void main() {
  testWidgets('guest sees a login prompt (no wishlist call) and can reach /auth/login',
      (tester) async {
    final requests = <RequestOptions>[];
    final session = buildGuestSessionStore();
    final favourites = FavouritesStore(
      repository: buildFakeWishlistRepository(capturedRequests: requests),
      session: session,
    );

    await tester.pumpWidget(
      _page(
        favourites: favourites,
        session: session,
        routes: {'/auth/login': (_) => const Scaffold(body: Text('LOGIN_MARKER'))},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('Log in to view your favorites'), findsOneWidget);
    expect(requests, isEmpty);

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('LOGIN_MARKER'), findsOneWidget);
  });

  testWidgets('authed renders the hydrated favourites as product cards', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await buildAuthedSessionStore();
    final favourites = FavouritesStore(
      repository: buildFakeWishlistRepository(
        items: [_card('ITEM-1', 'Fresh Milk'), _card('ITEM-2', 'Brown Bread')],
      ),
      session: session,
    );
    await tester.runAsync(favourites.restore);

    await tester.pumpWidget(_page(favourites: favourites, session: session));
    await tester.pumpAndSettle();

    expect(find.byType(ProductCard), findsNWidgets(2));
    expect(find.text('Fresh Milk'), findsOneWidget);
    expect(find.text('Brown Bread'), findsOneWidget);
    // Cards on this page are favourites by definition — hearts are filled.
    expect(find.byIcon(Iconsax.heart5), findsNWidgets(2));
  });

  testWidgets('authed with no favourites shows the empty state', (tester) async {
    final session = await buildAuthedSessionStore();
    final favourites = FavouritesStore(
      repository: buildFakeWishlistRepository(),
      session: session,
    );
    await tester.runAsync(favourites.restore);

    await tester.pumpWidget(_page(favourites: favourites, session: session));
    await tester.pumpAndSettle();

    expect(find.text('No favorites yet'), findsOneWidget);
    expect(find.byType(ProductCard), findsNothing);
  });

  testWidgets('a failed hydrate shows the retry prompt, and retry recovers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var failList = true;
    final dio = buildFakeDio((options) {
      if (options.path.endsWith('wishlist.list')) {
        if (failList) {
          return Response(requestOptions: options, statusCode: 500, data: {'message': 'boom'});
        }
        return _envelope(options, [_card('ITEM-1', 'Fresh Milk')]);
      }
      return _envelope(options, {'ok': true});
    });
    final repo = WishlistRepository(
      ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
    );
    final session = await buildAuthedSessionStore();
    final favourites = FavouritesStore(repository: repo, session: session);
    await tester.runAsync(favourites.restore);

    await tester.pumpWidget(_page(favourites: favourites, session: session));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);

    failList = false;
    await tester.tap(find.text('Retry'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('Fresh Milk'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
  });

  testWidgets('tapping a card heart un-favourites: card leaves the grid, wishlist.remove posts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final requests = <RequestOptions>[];
    final session = await buildAuthedSessionStore();
    final favourites = FavouritesStore(
      repository: buildFakeWishlistRepository(
        items: [_card('ITEM-1', 'Fresh Milk'), _card('ITEM-2', 'Brown Bread')],
        capturedRequests: requests,
      ),
      session: session,
    );
    await tester.runAsync(favourites.restore);

    await tester.pumpWidget(_page(favourites: favourites, session: session));
    await tester.pumpAndSettle();

    final milkHeart = find.descendant(
      of: find.byType(ProductCard).first,
      matching: find.byIcon(Iconsax.heart5),
    );
    await tester.tap(milkHeart, warnIfMissed: false);
    await tester.pump();

    expect(find.text('Fresh Milk'), findsNothing); // optimistic removal
    expect(find.text('Brown Bread'), findsOneWidget);
    expect(favourites.contains('ITEM-1'), isFalse);

    // Drain the in-flight wishlist.remove, then assert what was posted.
    await tester.pumpAndSettle();
    final removes = requests.where((r) => r.path.endsWith('wishlist.remove'));
    expect(removes.single.data, {'item_code': 'ITEM-1'});
    expect(find.text('Fresh Milk'), findsNothing); // server confirmed, no rollback
  });

  testWidgets('the card Add button adds the favourite to the cart', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await buildAuthedSessionStore();
    final favourites = FavouritesStore(
      repository: buildFakeWishlistRepository(items: [_card('ITEM-1', 'Fresh Milk')]),
      session: session,
    );
    final cart = CartStore(repository: buildFakeCartRepository(), session: session);
    await tester.runAsync(favourites.restore);

    await tester.pumpWidget(_page(favourites: favourites, session: session, cart: cart));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();

    expect(cart.count, 1);
    expect(cart.items.single.itemCode, 'ITEM-1');
  });
}
