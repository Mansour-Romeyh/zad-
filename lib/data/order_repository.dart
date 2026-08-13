import '../core/api/api_client.dart';
import '../core/json_utils.dart';
import 'cart_repository.dart' show CartTotals;

/// `order.place_order` result: `{order, status}` — the Sales Order name and
/// its fulfilment status (PRD F5/E3). An idempotent replay returns the same
/// order with its *current* status.
class OrderPlacement {
  const OrderPlacement({required this.order, required this.status});

  final String order;
  final String status;

  factory OrderPlacement.fromJson(dynamic json) {
    final map = json is Map ? json : const {};
    return OrderPlacement(
      order: map['order'] as String? ?? '',
      status: map['status'] as String? ?? '',
    );
  }
}

/// One `order.my_orders` card: `{name, date, status, grand_total,
/// item_count}` (PRD F5).
class OrderSummary {
  const OrderSummary({
    required this.name,
    required this.date,
    required this.status,
    required this.grandTotal,
    required this.itemCount,
  });

  final String name;

  /// `transaction_date` as the backend's `YYYY-MM-DD` string.
  final String date;
  final String status;
  final double grandTotal;
  final int itemCount;

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
    name: json['name'] as String? ?? '',
    date: json['date'] as String? ?? '',
    status: json['status'] as String? ?? '',
    grandTotal: toDouble(json['grand_total']) ?? 0,
    itemCount: toInt(json['item_count']) ?? 0,
  );
}

/// The `order.my_orders` paged envelope: `{items, page, has_more}`.
class OrdersResult {
  const OrdersResult({required this.items, required this.page, required this.hasMore});

  final List<OrderSummary> items;
  final int page;
  final bool hasMore;

  factory OrdersResult.fromJson(dynamic json) {
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final rawItems = map['items'];
    return OrdersResult(
      items: rawItems is List
          ? rawItems
                .map((e) => OrderSummary.fromJson(e as Map<String, dynamic>))
                .toList()
          : const [],
      page: toInt(map['page']) ?? 1,
      hasMore: toBool(map['has_more']),
    );
  }
}

/// One `order.detail` line: `{name, item_code, item_name, qty, uom,
/// estimated_qty, actual_qty, weight_confirmed, rate, amount}` (PRD F5/E6).
/// `actual_qty` is the backend's `flt(custom_actual_qty)` — `0` until a
/// picker confirms a weight, so [adjusted] requires a non-zero actual.
class OrderLine {
  const OrderLine({
    required this.name,
    required this.itemCode,
    required this.itemName,
    required this.qty,
    this.uom,
    required this.estimatedQty,
    required this.actualQty,
    this.weightConfirmed = false,
    required this.rate,
    required this.amount,
  });

  final String name;
  final String itemCode;
  final String itemName;
  final double qty;
  final String? uom;
  final double estimatedQty;
  final double actualQty;
  final bool weightConfirmed;
  final double rate;
  final double amount;

  /// PRD E6 — the picker confirmed a quantity different from the checkout
  /// estimate ("تم التعديل"). Mirrors the backend's own change-feed rule:
  /// a zero actual means "not confirmed yet", never an adjustment to zero
  /// (removals are their own change event).
  bool get adjusted => actualQty != 0 && actualQty != estimatedQty;

  factory OrderLine.fromJson(Map<String, dynamic> json) => OrderLine(
    name: json['name'] as String? ?? '',
    itemCode: json['item_code'] as String? ?? '',
    itemName: json['item_name'] as String? ?? json['item_code'] as String? ?? '',
    qty: toDouble(json['qty']) ?? 0,
    uom: json['uom'] as String?,
    estimatedQty: toDouble(json['estimated_qty']) ?? 0,
    actualQty: toDouble(json['actual_qty']) ?? 0,
    weightConfirmed: toBool(json['weight_confirmed']),
    rate: toDouble(json['rate']) ?? 0,
    amount: toDouble(json['amount']) ?? 0,
  );
}

/// `order.detail` response: `{name, date, status, zone, items, totals}`
/// (totals reuse the cart's `{net_total, grand_total, currency}` shape).
class OrderDetail {
  const OrderDetail({
    required this.name,
    required this.date,
    required this.status,
    this.zone,
    required this.items,
    required this.totals,
  });

  final String name;
  final String date;
  final String status;
  final String? zone;
  final List<OrderLine> items;
  final CartTotals totals;

  factory OrderDetail.fromJson(dynamic json) {
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final rawItems = map['items'];
    return OrderDetail(
      name: map['name'] as String? ?? '',
      date: map['date'] as String? ?? '',
      status: map['status'] as String? ?? '',
      zone: map['zone'] as String?,
      items: rawItems is List
          ? rawItems
                .map((e) => OrderLine.fromJson(e as Map<String, dynamic>))
                .toList()
          : const [],
      totals: CartTotals.fromJson(map['totals']),
    );
  }
}

/// One `order.changes` event (PRD F5/D1.11): `{type, item_code, item_name,
/// detail, timestamp}` — `type` is `weight_adjustment` / `substitution` /
/// `removal`, `detail` is the server-rendered Arabic description (the same
/// notification copy the customer received), newest first.
class OrderChange {
  const OrderChange({
    required this.type,
    required this.itemCode,
    required this.itemName,
    required this.detail,
    this.timestamp,
  });

  static const weightAdjustment = 'weight_adjustment';
  static const substitution = 'substitution';
  static const removal = 'removal';

  final String type;
  final String itemCode;
  final String itemName;
  final String detail;
  final String? timestamp;

  factory OrderChange.fromJson(Map<String, dynamic> json) => OrderChange(
    type: json['type'] as String? ?? '',
    itemCode: json['item_code'] as String? ?? '',
    itemName: json['item_name'] as String? ?? '',
    detail: json['detail'] as String? ?? '',
    timestamp: json['timestamp'] as String?,
  );
}

/// Thin, typed wrapper over `grocery.api.order.*` (PRD F5). Every method
/// requires a logged-in session — guests get 401 → [UnauthenticatedException]
/// via the shared [ApiClient] mapping; entry points are login-gated anyway.
class OrderRepository {
  OrderRepository(this._client);

  final ApiClient _client;

  /// PRD E3 atomic checkout. [idempotencyKey] (uuid v4, generated once per
  /// checkout attempt) makes a retried call return the SAME order instead
  /// of placing a second one — callers must reuse the key across retries.
  /// Throws `OutOfStockException(items)` (409) / `OutsideCoverageException`
  /// (417) via the client's error mapping.
  Future<OrderPlacement> placeOrder({
    required String address,
    required String idempotencyKey,
  }) async {
    final data = await _client.post(
      'grocery.api.order.place_order',
      data: {'address': address, 'idempotency_key': idempotencyKey},
    );
    return OrderPlacement.fromJson(data);
  }

  /// The caller's orders, newest first, paged (`{items, page, has_more}`).
  /// [status] filters on one fulfilment status when given.
  Future<OrdersResult> myOrders({String? status, int page = 1, int? pageSize}) async {
    final data = await _client.get(
      'grocery.api.order.my_orders',
      params: {'page': page, 'status': ?status, 'page_size': ?pageSize},
    );
    return OrdersResult.fromJson(data);
  }

  /// One owned order with full lines (estimated/actual qty, weight flags)
  /// and totals.
  Future<OrderDetail> detail(String name) async {
    final data = await _client.get('grocery.api.order.detail', params: {'name': name});
    return OrderDetail.fromJson(data);
  }

  /// The order's change feed (weight adjustments, substitutions, removals),
  /// newest first — `{changes: [...]}` unwrapped to the list.
  Future<List<OrderChange>> changes(String name) async {
    final data = await _client.get('grocery.api.order.changes', params: {'name': name});
    final raw = data is Map ? data['changes'] : null;
    if (raw is! List) return const [];
    return raw
        .map((e) => OrderChange.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
