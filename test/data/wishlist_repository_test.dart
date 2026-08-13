import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/wishlist_repository.dart';

import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) {
  return Response(requestOptions: options, statusCode: 200, data: {'message': message});
}

ApiClient _client(Dio dio) => ApiClient(
      dio: dio,
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

// ItemCard list as wishlist.list returns it (newest favourite first).
const _favouritesJson = [
  {
    'item_code': 'ITEM-2',
    'item_name': 'Tomatoes',
    'image': '/files/tomato.png',
    'price_per_uom': 2000.0,
    'uom': 'Kg',
    'sold_by_weight': true,
    'weight_step_g': 500,
    'min_g': 500,
    'max_g': 5000,
    'in_stock': true,
    'is_favourite': true,
  },
  {
    'item_code': 'ITEM-1',
    'item_name': 'Milk',
    'image': null,
    'price_per_uom': 1500.0,
    'uom': 'pc',
    'sold_by_weight': false,
    'in_stock': false,
    'is_favourite': true,
  },
];

void main() {
  group('WishlistRepository', () {
    test('list() calls wishlist.list and maps ItemCards in server order', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _favouritesJson),
          capturedRequests: requests);
      final repo = WishlistRepository(_client(dio));

      final items = await repo.list();

      expect(requests.single.path, '/api/method/grocery.api.wishlist.list');
      expect(items, hasLength(2));
      expect(items.first.itemCode, 'ITEM-2');
      expect(items.first.soldByWeight, isTrue);
      expect(items.first.imageUrl, 'http://test.local/files/tomato.png');
      expect(items.first.isFavourite, isTrue);
      expect(items.last.itemCode, 'ITEM-1');
      expect(items.last.inStock, isFalse);
      expect(items.last.pricePerUom, 1500.0);
    });

    test('list() tolerates a non-list payload', () async {
      final dio = buildFakeDio((options) => _envelope(options, null));
      final repo = WishlistRepository(_client(dio));

      expect(await repo.list(), isEmpty);
    });

    test('add() posts item_code to wishlist.add', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, {'ok': true}),
          capturedRequests: requests);
      final repo = WishlistRepository(_client(dio));

      await repo.add('ITEM-1');

      expect(requests.single.path, '/api/method/grocery.api.wishlist.add');
      expect(requests.single.data, {'item_code': 'ITEM-1'});
    });

    test('remove() posts item_code to wishlist.remove', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, {'ok': true}),
          capturedRequests: requests);
      final repo = WishlistRepository(_client(dio));

      await repo.remove('ITEM-1');

      expect(requests.single.path, '/api/method/grocery.api.wishlist.remove');
      expect(requests.single.data, {'item_code': 'ITEM-1'});
    });

    test('a guest 401 surfaces as UnauthenticatedException', () async {
      final dio = buildFakeDio(
        (options) => Response(
          requestOptions: options,
          statusCode: 401,
          data: {'message': 'Please log in'},
        ),
      );
      final repo = WishlistRepository(_client(dio));

      expect(repo.list(), throwsA(isA<UnauthenticatedException>()));
    });
  });
}
