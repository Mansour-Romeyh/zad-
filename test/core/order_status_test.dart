import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/order_status.dart';
import 'package:zad/features/orders/order_status_chip.dart';
import 'package:zad/l10n/app_localizations.dart';

import '../helpers.dart';

/// The PRD A2 Arabic labels, spelled out so a silent arb regression cannot
/// pass the mapping test.
const _arabicLabels = {
  OrderStatus.pendingAssignment: 'بانتظار التجهيز',
  OrderStatus.assigned: 'تم الإسناد',
  OrderStatus.picking: 'قيد التجهيز',
  OrderStatus.picked: 'تم التجهيز',
  OrderStatus.readyForDelivery: 'جاهز للتوصيل',
  OrderStatus.outForDelivery: 'قيد التوصيل',
  OrderStatus.delivered: 'تم التوصيل',
  // Masculine agreement — the described noun is الطلب (the order).
  OrderStatus.expired: 'منتهي الصلاحية',
  OrderStatus.cancelled: 'ملغي',
};

void main() {
  test('OrderStatus.all covers every A2 status exactly once', () {
    expect(OrderStatus.all, hasLength(9));
    expect(OrderStatus.all.toSet(), hasLength(9));
    expect(OrderStatus.timeline, hasLength(7));
    expect(OrderStatus.terminal, [OrderStatus.expired, OrderStatus.cancelled]);
  });

  test('timelineIndex orders the happy path and excludes terminal failures', () {
    expect(OrderStatus.timelineIndex(OrderStatus.pendingAssignment), 0);
    expect(OrderStatus.timelineIndex(OrderStatus.outForDelivery), 5);
    expect(OrderStatus.timelineIndex(OrderStatus.delivered), 6);
    expect(OrderStatus.timelineIndex(OrderStatus.expired), isNull);
    expect(OrderStatus.timelineIndex(OrderStatus.cancelled), isNull);
    expect(OrderStatus.timelineIndex('Bogus'), isNull);
  });

  test('every A2 status has an Arabic label and a color', () {
    final l10n = lookupAppLocalizations(const Locale('ar'));
    for (final status in OrderStatus.all) {
      expect(orderStatusLabel(l10n, status), _arabicLabels[status],
          reason: 'Arabic label for $status');
    }
    // Colors are per-status accents, not one shared tone.
    final colors = OrderStatus.all.map(orderStatusColor).toSet();
    expect(colors, hasLength(OrderStatus.all.length));
  });

  test('unknown statuses fall through unchanged (label) with a fallback color', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(orderStatusLabel(l10n, 'Weird Future Status'), 'Weird Future Status');
    expect(orderStatusColor('Weird Future Status'), isA<Color>());
  });

  testWidgets('OrderStatusChip renders the localized label for every A2 status',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      wrapPage(
        Scaffold(
          body: Column(
            children: [
              for (final status in OrderStatus.all) OrderStatusChip(status: status),
            ],
          ),
        ),
        locale: const Locale('ar'),
      ),
    );

    for (final status in OrderStatus.all) {
      expect(find.byKey(Key('orderStatusChip-$status')), findsOneWidget);
      expect(find.text(_arabicLabels[status]!), findsOneWidget,
          reason: 'chip label for $status');
    }
  });
}
