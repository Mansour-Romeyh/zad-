import 'dart:ui';

import '../l10n/app_localizations.dart';

/// PRD A2 fulfilment statuses (`custom_fulfilment_status`) — the exact
/// server strings, the happy-path timeline order, and the one place that
/// maps every status to its localized label and chip color. Every status
/// display (orders list, detail timeline, success page) goes through this
/// file so a new/renamed status has exactly one home.
abstract final class OrderStatus {
  static const pendingAssignment = 'Pending Assignment';
  static const assigned = 'Assigned';
  static const picking = 'Picking';
  static const picked = 'Picked';
  static const readyForDelivery = 'Ready for Delivery';
  static const outForDelivery = 'Out for Delivery';
  static const delivered = 'Delivered';
  static const expired = 'Expired';
  static const cancelled = 'Cancelled';

  /// The happy path in pipeline order (PRD A2: placed → assigned → picking
  /// → picked → ready → out-for-delivery → delivered) — what the detail
  /// page's timeline renders.
  static const timeline = [
    pendingAssignment,
    assigned,
    picking,
    picked,
    readyForDelivery,
    outForDelivery,
    delivered,
  ];

  /// Terminal failure states — never on the timeline; rendered as a
  /// standalone banner/chip instead of a progress step.
  static const terminal = [expired, cancelled];

  /// Every A2 status.
  static const all = [...timeline, ...terminal];

  /// Index of [status] on the happy-path [timeline], or `null` for
  /// [expired]/[cancelled]/unknown — the detail page highlights steps
  /// `0..index` as reached.
  static int? timelineIndex(String status) {
    final index = timeline.indexOf(status);
    return index < 0 ? null : index;
  }
}

/// Localized display label for a server status string. Unknown values fall
/// through unchanged (a forward-compatible render beats a crash).
String orderStatusLabel(AppLocalizations l10n, String status) {
  switch (status) {
    case OrderStatus.pendingAssignment:
      return l10n.orderStatusPendingAssignment;
    case OrderStatus.assigned:
      return l10n.orderStatusAssigned;
    case OrderStatus.picking:
      return l10n.orderStatusPicking;
    case OrderStatus.picked:
      return l10n.orderStatusPicked;
    case OrderStatus.readyForDelivery:
      return l10n.orderStatusReadyForDelivery;
    case OrderStatus.outForDelivery:
      return l10n.orderStatusOutForDelivery;
    case OrderStatus.delivered:
      return l10n.orderStatusDelivered;
    case OrderStatus.expired:
      return l10n.orderStatusExpired;
    case OrderStatus.cancelled:
      return l10n.orderStatusCancelled;
    default:
      return status;
  }
}

/// Accent color for a status chip (text/icon tone — chips derive their
/// background from it with a low alpha). In-progress statuses run warm →
/// cool as the order advances; Delivered is the brand green; Expired is
/// muted; Cancelled is red.
Color orderStatusColor(String status) {
  switch (status) {
    case OrderStatus.pendingAssignment:
      return const Color(0xFFB7791F); // amber — waiting
    case OrderStatus.assigned:
      return const Color(0xFF2B6CB0); // blue
    case OrderStatus.picking:
      return const Color(0xFF6B46C1); // purple
    case OrderStatus.picked:
      return const Color(0xFF2C7A7B); // teal
    case OrderStatus.readyForDelivery:
      return const Color(0xFF0987A0); // cyan
    case OrderStatus.outForDelivery:
      return const Color(0xFFC05621); // orange — on the road
    case OrderStatus.delivered:
      return const Color(0xFF5AC268); // ZadColors.primary green
    case OrderStatus.expired:
      return const Color(0xFF718096); // grey
    case OrderStatus.cancelled:
      return const Color(0xFFC53030); // red
    default:
      return const Color(0xFF718096);
  }
}
