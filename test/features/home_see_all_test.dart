import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/home/home_page.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

ApiClient _client() => ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) {
          return _envelope(options, [
            {'name': 'cat-1', 'label': 'Fruits', 'item_count': 3},
          ]);
        }
        if (options.path.endsWith('get_best_items')) {
          return _envelope(options, {
            'items': [
              {
                'item_code': 'ITEM-1',
                'item_name': 'Toor Dal',
                'image': null,
                'price_per_uom': 10000,
                'uom': '1 kg',
                'in_stock': true,
              },
            ],
            'page': 1,
            'has_more': true,
          });
        }
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

Widget _app() {
  final client = _client();
  return wrapPage(
    const HomePage(),
    providers: homeTestProviders(
      catalogRepository: CatalogRepository(client),
      contentRepository: ContentRepository(client),
    ),
    routes: {
      '/categories': (_) => const Scaffold(body: Text('CATEGORIES_MARKER')),
      '/best-deals': (_) => const Scaffold(body: Text('BEST_DEALS_MARKER')),
    },
  );
}

void main() {
  testWidgets('Shop By Category See All opens the categories page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('See All').first);
    await tester.pumpAndSettle();

    expect(find.text('CATEGORIES_MARKER'), findsOneWidget);
  });

  testWidgets('Best Deal See All opens the best deals page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('See All').last);
    await tester.pumpAndSettle();

    expect(find.text('BEST_DEALS_MARKER'), findsOneWidget);
  });
}
