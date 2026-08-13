import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/product_card.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

// The real paged-list contract: `{items, page, has_more}` envelope.
final _bestItemsJson = {
  'items': [
    {
      'item_code': 'ITEM-1',
      'item_name': 'Surf Excel Easy Wash Detergent Power',
      'image': null,
      'price_per_uom': 12000,
      'uom': '500 ml',
      'in_stock': true,
    },
    {
      'item_code': 'ITEM-2',
      'item_name': 'Fortune Arhar Dal (Toor Dal)',
      'image': null,
      'price_per_uom': 10000,
      'uom': '1 kg',
      'in_stock': true,
    },
  ],
  'page': 1,
  'has_more': false,
};

ApiClient _clientWithBestItems() => ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_best_items')) {
          return _envelope(options, _bestItemsJson);
        }
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

void main() {
  testWidgets('best deal section renders product cards with IQD prices', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _clientWithBestItems();

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

    expect(find.text('Best Deal'), findsOneWidget);
    expect(find.text('Surf Excel Easy Wash Detergent Power'), findsOneWidget);
    expect(find.text('500 ml'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ProductCard).first, matching: find.text('IQD 12,000')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.add), findsWidgets);
  });

  testWidgets('guest heart tap shows the login-required prompt, does not favourite', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _clientWithBestItems();
    final favourites = FavouritesStore(repository: buildFakeWishlistRepository());

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
          favouritesStore: favourites,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Iconsax.heart5), findsNothing);
    final cardHeart = find.descendant(
      of: find.byType(ProductCard).first,
      matching: find.byIcon(Iconsax.heart),
    );
    await tester.tap(cardHeart, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Log in to continue'), findsOneWidget);
    expect(favourites.contains('ITEM-1'), isFalse);
  });

  testWidgets('authed heart tap toggles favorite state via FavouritesStore', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _clientWithBestItems();
    final session = await buildAuthedSessionStore();
    final favourites = FavouritesStore(
      repository: buildFakeWishlistRepository(),
      session: session,
    );

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
          favouritesStore: favourites,
          sessionStore: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Iconsax.heart5), findsNothing);
    final cardHeart = find.descendant(
      of: find.byType(ProductCard).first,
      matching: find.byIcon(Iconsax.heart),
    );
    await tester.tap(cardHeart, warnIfMissed: false);
    await tester.pump();

    expect(find.byIcon(Iconsax.heart5), findsOneWidget); // optimistic flip
    expect(favourites.contains('ITEM-1'), isTrue);

    // Drain the in-flight wishlist.add so no dio timer outlives the test.
    await tester.pumpAndSettle();
    expect(favourites.contains('ITEM-1'), isTrue); // server confirmed, no rollback
  });

  testWidgets('is_favourite in the best-items payload seeds the store: heart starts filled', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_best_items')) {
          return _envelope(options, {
            'items': [
              {
                'item_code': 'ITEM-1',
                'item_name': 'Pre-loved Item',
                'price_per_uom': 1000,
                'uom': 'pc',
                'in_stock': true,
                'is_favourite': true,
              },
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
    final session = await buildAuthedSessionStore();
    final favourites = FavouritesStore(
      repository: buildFakeWishlistRepository(),
      session: session,
    );

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
          favouritesStore: favourites,
          sessionStore: session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(favourites.contains('ITEM-1'), isTrue);
    expect(find.byIcon(Iconsax.heart5), findsOneWidget);
  });
}
