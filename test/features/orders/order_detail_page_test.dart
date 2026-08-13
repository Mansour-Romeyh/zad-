import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/orders/order_detail_page.dart';

import '../../helpers.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

const _detailJson = {
  'name': 'SAL-ORD-2026-00042',
  'date': '2026-07-13',
  'status': 'Picking',
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
};

const _changesJson = {
  'changes': [
    {
      'type': 'substitution',
      'item_code': 'ITEM-9',
      'item_name': 'Substitute Milk',
      'detail': 'تم استبدال Milk بـ Substitute Milk',
      'timestamp': '2026-07-13 11:00:00',
    },
    {
      'type': 'weight_adjustment',
      'item_code': 'ITEM-1',
      'item_name': 'Fresh Tomatoes',
      'detail': 'تم تعديل وزن Fresh Tomatoes: 0.5 → 0.65, السعر الجديد 975.0',
      'timestamp': '2026-07-13 10:30:00',
    },
  ],
};

Widget _page(
  WidgetTester tester, {
  Map<String, dynamic> detail = _detailJson,
  Map<String, dynamic> changes = _changesJson,
  Response<dynamic>? Function(RequestOptions options)? overrides,
}) {
  return wrapPage(
    const OrderDetailPage(orderName: 'SAL-ORD-2026-00042'),
    providers: homeTestProviders(
      orderRepository: buildFakeOrderRepository(
        overrides: overrides ??
            (options) {
              if (options.path.endsWith('order.detail')) {
                return _envelope(options, detail);
              }
              if (options.path.endsWith('order.changes')) {
                return _envelope(options, changes);
              }
              return null;
            },
      ),
    ),
  );
}

void main() {
  testWidgets(
      'renders lines with estimated/actual qty, the adjusted badge, totals '
      'and the status chip', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(tester));
    await tester.pumpAndSettle();

    expect(find.text('SAL-ORD-2026-00042'), findsOneWidget);
    expect(find.byKey(const Key('orderStatusChip-Picking')), findsOneWidget);

    // The weight-adjusted line: badge + est/actual pair.
    expect(find.byKey(const Key('adjustedBadge-row-1')), findsOneWidget);
    expect(find.text('Estimated: 0.5 Kg'), findsOneWidget);
    expect(find.text('Actual: 0.65 Kg'), findsOneWidget);

    // The untouched line has NO badge and shows qty × rate.
    expect(find.byKey(const Key('adjustedBadge-row-2')), findsNothing);
    expect(find.text('2 Nos × IQD 2,000'), findsOneWidget);

    // Totals.
    expect(find.text('IQD 4,975'), findsNWidgets(2)); // subtotal + total
  });

  testWidgets('renders the change feed newest first with Arabic details',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(tester));
    await tester.pumpAndSettle();

    expect(find.text('Order Changes'), findsOneWidget);
    final substitution = find.text('تم استبدال Milk بـ Substitute Milk');
    final adjustment = find.text(
      'تم تعديل وزن Fresh Tomatoes: 0.5 → 0.65, السعر الجديد 975.0',
    );
    expect(substitution, findsOneWidget);
    expect(adjustment, findsOneWidget);
    // Server order (newest first) preserved on screen.
    expect(
      tester.getTopLeft(substitution).dy,
      lessThan(tester.getTopLeft(adjustment).dy),
    );
  });

  testWidgets('an empty feed hides the changes section', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(tester, changes: const {'changes': <dynamic>[]}),
    );
    await tester.pumpAndSettle();

    expect(find.text('Order Changes'), findsNothing);
  });

  testWidgets('the happy-path timeline lists all steps without a terminal banner',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_page(tester));
    await tester.pumpAndSettle();

    // Status "Picking": no terminal banner, full 7-step timeline present.
    expect(find.byKey(const Key('terminalStatusBanner')), findsNothing);
    expect(find.text('Out for Delivery'), findsOneWidget); // future step listed
  });

  testWidgets('a cancelled order shows the terminal banner', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cancelled = Map<String, dynamic>.of(_detailJson)
      ..['status'] = 'Cancelled';
    await tester.pumpWidget(_page(tester, detail: cancelled));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('terminalStatusBanner')), findsOneWidget);
    expect(find.byKey(const Key('orderStatusChip-Cancelled')), findsOneWidget);
  });

  testWidgets(
      'a failed change feed degrades to detail-without-feed instead of an '
      'error page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _page(
        tester,
        overrides: (options) {
          if (options.path.endsWith('order.detail')) {
            return _envelope(options, _detailJson);
          }
          if (options.path.endsWith('order.changes')) {
            return Response(
              requestOptions: options,
              statusCode: 500,
              data: {'message': 'feed exploded'},
            );
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    // Full detail rendered: header, lines, totals, timeline.
    expect(find.text('SAL-ORD-2026-00042'), findsOneWidget);
    expect(find.byKey(const Key('adjustedBadge-row-1')), findsOneWidget);
    expect(find.text('IQD 4,975'), findsNWidgets(2));
    // Only the (auxiliary) feed is omitted — no retry/error state.
    expect(find.text('Order Changes'), findsNothing);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a failed load shows retry, and retry recovers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var detailCalls = 0;
    await tester.pumpWidget(
      _page(
        tester,
        overrides: (options) {
          if (options.path.endsWith('order.detail')) {
            detailCalls++;
            if (detailCalls == 1) {
              return Response(
                requestOptions: options,
                statusCode: 500,
                data: {'message': 'boom'},
              );
            }
            return _envelope(options, _detailJson);
          }
          if (options.path.endsWith('order.changes')) {
            return _envelope(options, _changesJson);
          }
          return null;
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('SAL-ORD-2026-00042'), findsOneWidget);
    expect(find.byKey(const Key('adjustedBadge-row-1')), findsOneWidget);
  });

  testWidgets('renders a Delivery line when the order carries a delivery fee',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final detailWithFee = {
      ..._detailJson,
      'totals': {
        'net_total': 4975,
        'delivery_fee': 1000,
        'grand_total': 5975,
        'currency': 'IQD',
      },
    };

    await tester.pumpWidget(_page(tester, detail: detailWithFee));
    await tester.pumpAndSettle();

    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('IQD 1,000'), findsOneWidget); // fee line
    expect(find.text('IQD 4,975'), findsOneWidget); // subtotal
    expect(find.text('IQD 5,975'), findsOneWidget); // grand total (fee included)
  });
}
