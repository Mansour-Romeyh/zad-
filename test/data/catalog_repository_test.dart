import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/catalog_repository.dart';

import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) {
  return Response(
    requestOptions: options,
    statusCode: 200,
    data: {'message': message},
  );
}

ApiClient _client(Dio dio) => ApiClient(
  dio: dio,
  tokenStore: TokenStore(storage: FakeSecureStorage()),
  baseUrl: 'http://test.local',
);

void main() {
  group('CatalogRepository', () {
    test(
      'getCategories calls catalog.get_categories via GET and maps items',
      () async {
        final requests = <RequestOptions>[];
        final dio = buildFakeDio(
          (options) => _envelope(options, [
            {
              'name': 'Dairy',
              'label': 'Dairy & Breakfast',
              'image': '/files/dairy.png',
              'item_count': 5,
            },
          ]),
          capturedRequests: requests,
        );
        final repo = CatalogRepository(_client(dio));

        final categories = await repo.getCategories();

        expect(requests.single.method, 'GET');
        expect(
          requests.single.path,
          '/api/method/grocery.api.catalog.get_categories',
        );
        expect(categories, hasLength(1));
        expect(categories.single.name, 'Dairy');
        expect(categories.single.imageUrl, 'http://test.local/files/dairy.png');
      },
    );

    test(
      'itemsByCategory posts item_group/page/page_size and maps the paged envelope',
      () async {
        final requests = <RequestOptions>[];
        final dio = buildFakeDio(
          (options) => _envelope(options, {
            'items': [
              {
                'item_code': 'ITEM-1',
                'item_name': 'Milk',
                'price_per_uom': 1.5,
                'uom': 'Ltr',
              },
            ],
            'page': 2,
            'has_more': true,
          }),
          capturedRequests: requests,
        );
        final repo = CatalogRepository(_client(dio));

        final result = await repo.itemsByCategory('Dairy', page: 2);

        expect(requests.single.method, 'POST');
        expect(
          requests.single.path,
          '/api/method/grocery.api.catalog.items_by_category',
        );
        expect(requests.single.data, {
          'item_group': 'Dairy',
          'page': 2,
          'page_size': 20,
        });
        expect(result.items.single.itemCode, 'ITEM-1');
        expect(result.items.single.pricePerUom, 1.5);
        expect(result.page, 2);
        expect(result.hasMore, isTrue);
      },
    );

    test('itemsByCategory surfaces has_more=false from the envelope', () async {
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'items': <Map<String, dynamic>>[],
          'page': 1,
          'has_more': false,
        }),
      );
      final repo = CatalogRepository(_client(dio));

      final result = await repo.itemsByCategory('Dairy');

      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
    });

    test(
      'itemsByCategory resolves item image urls inside the envelope',
      () async {
        final dio = buildFakeDio(
          (options) => _envelope(options, {
            'items': [
              {
                'item_code': 'ITEM-1',
                'item_name': 'Milk',
                'image': '/files/milk.png',
              },
            ],
            'page': 1,
            'has_more': false,
          }),
        );
        final repo = CatalogRepository(_client(dio));

        final result = await repo.itemsByCategory('Dairy');

        expect(
          result.items.single.imageUrl,
          'http://test.local/files/milk.png',
        );
      },
    );

    test('getBestItems posts page and maps the paged envelope', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'items': [
            {'item_code': 'BEST-1', 'item_name': 'Honey'},
          ],
          'page': 3,
          'has_more': false,
        }),
        capturedRequests: requests,
      );
      final repo = CatalogRepository(_client(dio));

      final result = await repo.getBestItems(page: 3);

      expect(
        requests.single.path,
        '/api/method/grocery.api.catalog.get_best_items',
      );
      expect(requests.single.data, {'page': 3});
      expect(result.items.single.itemCode, 'BEST-1');
      expect(result.hasMore, isFalse);
    });

    test(
      'paged endpoints tolerate a bare list defensively (fallback contract)',
      () async {
        final dio = buildFakeDio(
          (options) => _envelope(options, [
            {'item_code': 'ITEM-1', 'item_name': 'Milk'},
          ]),
        );
        final repo = CatalogRepository(_client(dio));

        final result = await repo.itemsByCategory('Dairy');

        expect(result.items.single.itemCode, 'ITEM-1');
        // 1 item < page_size 20 -> heuristic treats it as the last page.
        expect(result.hasMore, isFalse);
      },
    );

    test('getItem posts item_code and maps a single ItemCard', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) =>
            _envelope(options, {'item_code': 'ITEM-9', 'item_name': 'Rice'}),
        capturedRequests: requests,
      );
      final repo = CatalogRepository(_client(dio));

      final item = await repo.getItem('ITEM-9');

      expect(requests.single.path, '/api/method/grocery.api.catalog.get_item');
      expect(requests.single.data, {'item_code': 'ITEM-9'});
      expect(item.itemCode, 'ITEM-9');
      expect(item.nameEn, 'Rice');
    });
  });
}
