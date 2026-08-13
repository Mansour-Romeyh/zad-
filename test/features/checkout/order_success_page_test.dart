import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/checkout/order_success_page.dart';

import '../../helpers.dart';

void main() {
  testWidgets('shows the order number and the بانتظار التجهيز status chip',
      (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const OrderSuccessPage(
          orderName: 'SAL-ORD-2026-00042',
          status: 'Pending Assignment',
        ),
        locale: const Locale('ar'),
      ),
    );

    expect(find.text('تم استلام طلبك!'), findsOneWidget);
    expect(find.text('رقم الطلب: SAL-ORD-2026-00042'), findsOneWidget);
    expect(find.byKey(const Key('orderStatusChip-Pending Assignment')), findsOneWidget);
    expect(find.text('بانتظار التجهيز'), findsOneWidget);
  });

  testWidgets('CTAs route to the orders list and home', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const OrderSuccessPage(orderName: 'SO-1', status: 'Pending Assignment'),
        routes: {
          '/orders': (_) => const Scaffold(body: Text('ORDERS_MARKER')),
          '/home': (_) => const Scaffold(body: Text('HOME_MARKER')),
        },
      ),
    );

    await tester.tap(find.byKey(const Key('successViewOrdersButton')));
    await tester.pumpAndSettle();
    expect(find.text('ORDERS_MARKER'), findsOneWidget);
  });

  testWidgets('home CTA clears the stack back to /home', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const OrderSuccessPage(orderName: 'SO-1', status: 'Pending Assignment'),
        routes: {
          '/orders': (_) => const Scaffold(body: Text('ORDERS_MARKER')),
          '/home': (_) => const Scaffold(body: Text('HOME_MARKER')),
        },
      ),
    );

    await tester.tap(find.byKey(const Key('successGoHomeButton')));
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
  });
}
