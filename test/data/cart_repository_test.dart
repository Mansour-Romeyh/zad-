import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/cart_repository.dart';

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

const _cartJson = {
  'items': [
    {
      'name': 'row-1',
      'item_code': 'ITEM-1',
      'qty': 2,
      'uom': 'pc',
      'rate': 1500.0,
      'amount': 3000.0,
      'item_name': 'Milk',
      'image': '/files/milk.png',
      'sold_by_weight': false,
      'in_stock': true,
    },
  ],
  'totals': {'net_total': 3000.0, 'grand_total': 3000.0, 'currency': 'IQD'},
};

void main() {
  group('CartRepository', () {
    test('get() posts to cart.get and maps items/totals', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _cartJson), capturedRequests: requests);
      final repo = CartRepository(_client(dio));

      final snapshot = await repo.get();

      expect(requests.single.path, '/api/method/grocery.api.cart.get');
      expect(snapshot.lines, hasLength(1));
      expect(snapshot.lines.single.row, 'row-1');
      expect(snapshot.lines.single.itemCode, 'ITEM-1');
      expect(snapshot.lines.single.qty, 2);
      expect(snapshot.lines.single.rate, 1500.0);
      expect(snapshot.lines.single.imageUrl, 'http://test.local/files/milk.png');
      expect(snapshot.totals.netTotal, 3000.0);
      expect(snapshot.totals.grandTotal, 3000.0);
      expect(snapshot.warnings, isEmpty);
    });

    test('addItem posts item_code/qty/uom to cart.add_item', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _cartJson), capturedRequests: requests);
      final repo = CartRepository(_client(dio));

      await repo.addItem('ITEM-1', qty: 2, uom: 'pc');

      expect(requests.single.path, '/api/method/grocery.api.cart.add_item');
      expect(requests.single.data, {'item_code': 'ITEM-1', 'qty': 2, 'uom': 'pc'});
    });

    test('addItem omits uom when not provided', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _cartJson), capturedRequests: requests);
      final repo = CartRepository(_client(dio));

      await repo.addItem('ITEM-1', qty: 0.5);

      expect(requests.single.data, {'item_code': 'ITEM-1', 'qty': 0.5});
    });

    test('updateItem posts row/qty to cart.update_item', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _cartJson), capturedRequests: requests);
      final repo = CartRepository(_client(dio));

      await repo.updateItem('row-1', 3);

      expect(requests.single.path, '/api/method/grocery.api.cart.update_item');
      expect(requests.single.data, {'row': 'row-1', 'qty': 3});
    });

    test('removeItem posts row to cart.remove_item', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _cartJson), capturedRequests: requests);
      final repo = CartRepository(_client(dio));

      await repo.removeItem('row-1');

      expect(requests.single.path, '/api/method/grocery.api.cart.remove_item');
      expect(requests.single.data, {'row': 'row-1'});
    });

    test('clear() posts to cart.clear', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, {'items': <dynamic>[], 'totals': {}}), capturedRequests: requests);
      final repo = CartRepository(_client(dio));

      final snapshot = await repo.clear();

      expect(requests.single.path, '/api/method/grocery.api.cart.clear');
      expect(snapshot.lines, isEmpty);
    });

    test('merge posts lines to cart.merge, summing is left to the server', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio((options) => _envelope(options, _cartJson), capturedRequests: requests);
      final repo = CartRepository(_client(dio));

      await repo.merge(const [
        CartMergeLine(itemCode: 'ITEM-1', qty: 2),
        CartMergeLine(itemCode: 'ITEM-2', qty: 0.5),
      ]);

      expect(requests.single.path, '/api/method/grocery.api.cart.merge');
      expect(requests.single.data, {
        'lines': [
          {'item_code': 'ITEM-1', 'qty': 2},
          {'item_code': 'ITEM-2', 'qty': 0.5},
        ],
      });
    });

    test('maps warnings from a soft stock check', () async {
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'items': <dynamic>[],
          'totals': {'net_total': 0, 'grand_total': 0},
          'warnings': ['Only 3 left of ITEM-1'],
        }),
      );
      final repo = CartRepository(_client(dio));

      final snapshot = await repo.addItem('ITEM-1', qty: 5);

      expect(snapshot.warnings, ['Only 3 left of ITEM-1']);
    });

    test('tolerates a missing totals map', () async {
      final dio = buildFakeDio((options) => _envelope(options, {'items': <dynamic>[]}));
      final repo = CartRepository(_client(dio));

      final snapshot = await repo.get();

      expect(snapshot.totals.netTotal, 0);
      expect(snapshot.totals.grandTotal, 0);
    });
  });
}
