import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/search_repository.dart';

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
  group('SearchRepository', () {
    test('query posts q/page and maps the paged envelope', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'items': [
            {'item_code': 'ITEM-1', 'item_name': 'Milk', 'price_per_uom': 1.5},
          ],
          'page': 2,
          'has_more': true,
        }),
        capturedRequests: requests,
      );
      final repo = SearchRepository(_client(dio));

      final result = await repo.query('milk', page: 2);

      expect(requests.single.method, 'POST');
      expect(requests.single.path, '/api/method/grocery.api.search.query');
      expect(requests.single.data, {'q': 'milk', 'page': 2});
      expect(result.items.single.itemCode, 'ITEM-1');
      expect(result.page, 2);
      expect(result.hasMore, isTrue);
    });

    test('query defaults to page 1', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'items': <dynamic>[],
          'page': 1,
          'has_more': false,
        }),
        capturedRequests: requests,
      );
      final repo = SearchRepository(_client(dio));

      await repo.query('rice');

      expect(requests.single.data, {'q': 'rice', 'page': 1});
    });

    test('recent posts to search.recent and maps a bare list of strings', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, ['milk', 'bread', 'eggs']),
        capturedRequests: requests,
      );
      final repo = SearchRepository(_client(dio));

      final result = await repo.recent();

      expect(requests.single.path, '/api/method/grocery.api.search.recent');
      expect(result, ['milk', 'bread', 'eggs']);
    });

    test('recent surfaces UnauthenticatedException for guests (401)', () async {
      final dio = buildFakeDio(
        (options) => Response(
          requestOptions: options,
          statusCode: 401,
          data: {'message': 'Not permitted'},
        ),
      );
      final repo = SearchRepository(_client(dio));

      expect(repo.recent(), throwsA(isA<UnauthenticatedException>()));
    });

    test('clearRecent posts to search.clear_recent', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {'ok': true}),
        capturedRequests: requests,
      );
      final repo = SearchRepository(_client(dio));

      await repo.clearRecent();

      expect(
        requests.single.path,
        '/api/method/grocery.api.search.clear_recent',
      );
    });

    test('trending posts to search.trending and maps a bare ItemCard list', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, [
          {'item_code': 'ITEM-9', 'item_name': 'Honey'},
        ]),
        capturedRequests: requests,
      );
      final repo = SearchRepository(_client(dio));

      final result = await repo.trending();

      expect(requests.single.path, '/api/method/grocery.api.search.trending');
      expect(result.single.itemCode, 'ITEM-9');
      expect(result.single.nameEn, 'Honey');
    });

    test('trending tolerates a non-list payload defensively', () async {
      final dio = buildFakeDio((options) => _envelope(options, null));
      final repo = SearchRepository(_client(dio));

      final result = await repo.trending();

      expect(result, isEmpty);
    });
  });
}
