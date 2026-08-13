import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/features/product/best_deals_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

Map<String, dynamic> _item(int n) => {
      'item_code': 'ITEM-$n',
      'item_name': 'Product $n',
      'image': null,
      'price_per_uom': 1000 * n,
      'uom': '1 kg',
      'in_stock': true,
    };

CatalogRepository _repoWith(Response<dynamic> Function(RequestOptions) handler) {
  return CatalogRepository(
    ApiClient(
      dio: buildFakeDio(handler),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    ),
  );
}

Widget _app(CatalogRepository repo) => wrapPage(
      const BestDealsPage(),
      providers: [
        Provider<CatalogRepository>.value(value: repo),
        ChangeNotifierProvider<FavouritesStore>(
          create: (_) =>
              FavouritesStore(repository: buildFakeWishlistRepository()),
        ),
        // The page now hosts a CartFab, which reads CartStore. An empty
        // (unrestored) guest cart keeps the FAB hidden and off the way.
        ChangeNotifierProvider<CartStore>(
          create: (_) => CartStore(
            repository: buildFakeCartRepository(),
            session: buildGuestSessionStore(),
          ),
        ),
      ],
    );

void main() {
  testWidgets('renders the paged best-deals grid across pages', (tester) async {
    // Phone-sized surface: page 1's single row renders shorter than the
    // viewport, so the underfill check must auto-fetch page 2.
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = _repoWith((options) {
      final page = (options.data as Map<String, dynamic>)['page'] as int;
      return _envelope(options, {
        'items': [_item(page)],
        'page': page,
        'has_more': page < 2,
      });
    });
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Best Deal'), findsOneWidget);
    // Page 1 is shorter than the viewport, so page 2 auto-loads.
    expect(find.text('Product 1'), findsOneWidget);
    expect(find.text('Product 2'), findsOneWidget);
  });

  testWidgets('a failed load shows a retry button that reloads', (tester) async {
    var calls = 0;
    final repo = _repoWith((options) {
      calls++;
      if (calls == 1) {
        return Response(
          requestOptions: options,
          statusCode: 500,
          data: {'message': 'boom'},
        );
      }
      return _envelope(options, {
        'items': [_item(1)],
        'page': 1,
        'has_more': false,
      });
    });
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();

    expect(find.text('Product 1'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Product 1'), findsOneWidget);
  });
}
