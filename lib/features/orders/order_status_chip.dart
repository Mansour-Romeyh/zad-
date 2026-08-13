import 'package:flutter/material.dart';

import '../../core/order_status.dart';
import '../../l10n/app_localizations.dart';

/// The localized fulfilment-status pill shared by the orders list, order
/// detail and order success screens — label + color straight from the one
/// PRD A2 map in `core/order_status.dart`.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({required this.status, super.key});

  /// The exact server status string (`custom_fulfilment_status`).
  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final color = orderStatusColor(status);
    return Container(
      key: Key('orderStatusChip-$status'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        orderStatusLabel(l10n, status),
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
