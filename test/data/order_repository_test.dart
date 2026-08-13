import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/order_repository.dart';

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

void main() {
  group('OrderRepository', () {
    test('placeOrder() posts address + idempotency_key and parses {order, status}', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'order': 'SAL-ORD-2026-00042',
          'status': 'Pending Assignment',
        }),
        capturedRequests: requests,
      );
      final repo = OrderRepository(_client(dio));

      final placement = await repo.placeOrder(
        address: 'ADDR-1',
        idempotencyKey: 'key-123',
      );

      expect(requests.single.path, '/api/method/grocery.api.order.place_order');
      expect(requests.single.method, 'POST');
      expect(requests.single.data, {
        'address': 'ADDR-1',
        'idempotency_key': 'key-123',
      });
      expect(placement.order, 'SAL-ORD-2026-00042');
      expect(placement.status, 'Pending Assignment');
    });

    test('placeOrder() maps 409 to OutOfStockException with the item list', () async {
      final dio = buildFakeDio(
        (options) => Response(
          requestOptions: options,
          statusCode: 409,
          data: {
            'message': 'These items are not available in the requested quantity: ITEM-1',
            'items': ['ITEM-1', 'ITEM-2'],
          },
        ),
      );
      final repo = OrderRepository(_client(dio));

      try {
        await repo.placeOrder(address: 'ADDR-1', idempotencyKey: 'k');
        fail('expected OutOfStockException');
      } on OutOfStockException catch (e) {
        expect(e.items, ['ITEM-1', 'ITEM-2']);
      }
    });

    test('placeOrder() maps 417 to OutsideCoverageException', () async {
      final dio = buildFakeDio(
        (options) => Response(
          requestOptions: options,
          statusCode: 417,
          data: {
            'exc_type': 'OutsideCoverageError',
            'message': 'This address is outside our delivery coverage area.',
          },
        ),
      );
      final repo = OrderRepository(_client(dio));

      expect(
        () => repo.placeOrder(address: 'ADDR-1', idempotencyKey: 'k'),
        throwsA(isA<OutsideCoverageException>()),
      );
    });

    test('myOrders() GETs page (omitting status) and parses the envelope', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'items': [
            {
              'name': 'SAL-ORD-2026-00002',
              'date': '2026-07-13',
              'status': 'Picking',
              'grand_total': 12500,
              'item_count': 3,
            },
            {
              'name': 'SAL-ORD-2026-00001',
              'date': '2026-07-12',
              'status': 'Delivered',
              'grand_total': 4000.5,
              'item_count': 1,
            },
          ],
          'page': 1,
          'has_more': true,
        }),
        capturedRequests: requests,
      );
      final repo = OrderRepository(_client(dio));

      final result = await repo.myOrders(page: 1);

      expect(requests.single.path, '/api/method/grocery.api.order.my_orders');
      expect(requests.single.method, 'GET');
      expect(requests.single.queryParameters, {'page': 1});
      expect(result.items, hasLength(2));
      expect(result.items.first.name, 'SAL-ORD-2026-00002');
      expect(result.items.first.status, 'Picking');
      expect(result.items.first.grandTotal, 12500);
      expect(result.items.first.itemCount, 3);
      expect(result.items.last.date, '2026-07-12');
      expect(result.page, 1);
      expect(result.hasMore, isTrue);
    });

    test('myOrders() sends the status filter when given', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {'items': <dynamic>[], 'page': 2, 'has_more': false}),
        capturedRequests: requests,
      );
      final repo = OrderRepository(_client(dio));

      final result = await repo.myOrders(status: 'Delivered', page: 2);

      expect(requests.single.queryParameters, {'page': 2, 'status': 'Delivered'});
      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
    });

    test('detail() parses lines (estimated/actual, weight flag), totals and zone', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'name': 'SAL-ORD-2026-00042',
          'date': '2026-07-13',
          'status': 'Picked',
          'zone': 'Central Baghdad',
          'items': [
            {
              'name': 'row-1',
              'item_code': 'ITEM-1',
              'item_name': 'Fresh Tomatoes',
              'qty': 0.65,
              'uom': 'Kg',
              'estimated_qty': 0.5,
              'actual_qty': 0.65,
              'weight_confirmed': 1,
              'rate': 1500,
              'amount': 975,
            },
            {
              'name': 'row-2',
              'item_code': 'ITEM-2',
              'item_name': 'Milk',
              'qty': 2,
              'uom': 'Nos',
              'estimated_qty': 2,
              'actual_qty': 0,
              'weight_confirmed': 0,
              'rate': 2000,
              'amount': 4000,
            },
          ],
          'totals': {'net_total': 4975, 'grand_total': 4975, 'currency': 'IQD'},
        }),
        capturedRequests: requests,
      );
      final repo = OrderRepository(_client(dio));

      final detail = await repo.detail('SAL-ORD-2026-00042');

      expect(requests.single.path, '/api/method/grocery.api.order.detail');
      expect(requests.single.queryParameters, {'name': 'SAL-ORD-2026-00042'});
      expect(detail.name, 'SAL-ORD-2026-00042');
      expect(detail.status, 'Picked');
      expect(detail.zone, 'Central Baghdad');
      expect(detail.items, hasLength(2));
      final adjusted = detail.items.first;
      expect(adjusted.estimatedQty, 0.5);
      expect(adjusted.actualQty, 0.65);
      expect(adjusted.weightConfirmed, isTrue);
      expect(adjusted.adjusted, isTrue);
      final untouched = detail.items.last;
      // actual_qty 0 = "not confirmed yet", never an adjustment to zero.
      expect(untouched.adjusted, isFalse);
      expect(detail.totals.grandTotal, 4975);
      expect(detail.totals.currency, 'IQD');
    });

    test('changes() unwraps the feed and tolerates a missing list', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'changes': [
            {
              'type': 'weight_adjustment',
              'item_code': 'ITEM-1',
              'item_name': 'Fresh Tomatoes',
              'detail': 'تم تعديل وزن Fresh Tomatoes: 0.5 → 0.65, السعر الجديد 975.0',
              'timestamp': '2026-07-13 10:30:00',
            },
            {
              'type': 'removal',
              'item_code': 'ITEM-3',
              'item_name': 'Bread',
              'detail': 'تم حذف Bread من طلبك لعدم توفره.',
              'timestamp': null,
            },
          ],
        }),
        capturedRequests: requests,
      );
      final repo = OrderRepository(_client(dio));

      final changes = await repo.changes('SAL-ORD-2026-00042');

      expect(requests.single.path, '/api/method/grocery.api.order.changes');
      expect(requests.single.queryParameters, {'name': 'SAL-ORD-2026-00042'});
      expect(changes, hasLength(2));
      expect(changes.first.type, 'weight_adjustment');
      expect(changes.first.detail, contains('تم تعديل وزن'));
      expect(changes.first.timestamp, '2026-07-13 10:30:00');
      expect(changes.last.timestamp, isNull);

      final emptyRepo = OrderRepository(
        _client(buildFakeDio((options) => _envelope(options, null))),
      );
      expect(await emptyRepo.changes('SO-X'), isEmpty);
    });

    test('guest 401 is surfaced as UnauthenticatedException', () async {
      final dio = buildFakeDio(
        (options) => Response(
          requestOptions: options,
          statusCode: 401,
          data: {'message': 'Not permitted'},
        ),
      );
      final repo = OrderRepository(_client(dio));

      expect(() => repo.myOrders(), throwsA(isA<UnauthenticatedException>()));
    });
  });
}
