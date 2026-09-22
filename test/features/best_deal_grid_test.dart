import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/best_deal_grid.dart';
import 'package:zad/features/home/widgets/product_card.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

Map<String, dynamic> _item(String code) => {
      'item_code': code,
      'item_name': 'Item $code',
      'image': null,
      'price_per_uom': 1000,
      'uom': 'pc',
      'in_stock': true,
    };

/// A catalog client whose best-items endpoint is paged: page 1 has_more, page 2
/// is the last page. Records every page number requested in [pagesSeen].
ApiClient _pagedBestItemsClient({required List<int> pagesSeen}) => ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_best_items')) {
          final page = (options.data as Map)['page'] as int;
          pagesSeen.add(page);
          if (page == 1) {
            return _envelope(options, {
              'items': [_item('A'), _item('B')],
              'page': 1,
              'has_more': true,
            });
          }
          return _envelope(options, {
            'items': [_item('C')],
            'page': 2,
            'has_more': false,
          });
        }
        // Give categories a group so its "See All" is present — that lets the
        // no-See-All assertion below target the best-deal section specifically.
        if (options.path.endsWith('get_categories')) {
          return _envelope(options, [
            {'name': 'cat-1', 'label': 'Fruits', 'item_count': 3},
          ]);
        }
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

void main() {
  testWidgets('the best-deal section walks every page and shows all items', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final pagesSeen = <int>[];
    final client = _pagedBestItemsClient(pagesSeen: pagesSeen);

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

    // Both pages were fetched (1, then 2), and every item across them renders.
    expect(pagesSeen, [1, 2]);
    expect(find.byType(BestDealGrid), findsOneWidget);
    for (final code in ['A', 'B', 'C']) {
      expect(find.text('Item $code'), findsOneWidget);
    }
    // Three items in a two-column grid occupy two rows (two distinct top edges).
    final tops = {
      for (final code in ['A', 'B', 'C'])
        tester.getTopLeft(find.text('Item $code')).dy.roundToDouble(),
    };
    expect(tops.length, 2);
  });

  testWidgets('the best-deal section no longer offers a See All', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = _pagedBestItemsClient(pagesSeen: []);

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

    // Only "Shop By Category" keeps a See All; the best-deal header dropped it.
    expect(find.text('See All'), findsOneWidget);
    // Sanity: the grid is present and holds a card, so the section did render.
    expect(find.byType(ProductCard), findsWidgets);
  });
}
