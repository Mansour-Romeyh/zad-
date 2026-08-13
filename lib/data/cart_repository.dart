import '../core/api/api_client.dart';
import '../core/json_utils.dart';

/// One cart line as returned by every `cart.*` endpoint (PRD F5): `{name
/// (row id), item_code, qty, uom, rate, amount, item_name, image,
/// sold_by_weight, weight_step_g, min_g, max_g, in_stock...}`. `qty` is in
/// Kg for weight-sold items (PRD E1), an integer count otherwise.
class CartLine {
  const CartLine({
    required this.row,
    required this.itemCode,
    required this.qty,
    this.uom,
    required this.rate,
    this.amount,
    this.itemName,
    this.imageUrl,
    this.soldByWeight = false,
    this.weightStepG,
    this.minG,
    this.maxG,
    this.inStock = true,
  });

  /// Server-side Quotation Item row name — the id used by
  /// `update_item`/`remove_item`.
  final String row;
  final String itemCode;
  final double qty;
  final String? uom;
  final double rate;

  /// Server-computed line total — `null` when the payload omitted it
  /// (consumers then fall back to `rate * qty`).
  final double? amount;
  final String? itemName;
  final String? imageUrl;
  final bool soldByWeight;
  final double? weightStepG;
  final double? minG;
  final double? maxG;
  final bool inStock;

  factory CartLine.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveImageUrl,
  }) {
    final resolver = resolveImageUrl ?? (String? p) => p;
    return CartLine(
      row: json['name'] as String? ?? '',
      itemCode: json['item_code'] as String? ?? '',
      qty: toDouble(json['qty']) ?? 0,
      uom: json['uom'] as String?,
      rate: toDouble(json['rate']) ?? 0,
      amount: toDouble(json['amount']),
      itemName: json['item_name'] as String?,
      imageUrl: resolver(json['image'] as String?),
      soldByWeight: toBool(json['sold_by_weight']),
      weightStepG: toDouble(json['weight_step_g']),
      minG: toDouble(json['min_g']),
      maxG: toDouble(json['max_g']),
      inStock: toBool(json['in_stock'], fallback: true),
    );
  }
}

/// `{net_total, grand_total, currency}` (PRD F5).
class CartTotals {
  const CartTotals({
    required this.netTotal,
    required this.grandTotal,
    this.deliveryFee = 0,
    this.currency,
  });

  final double netTotal;
  final double grandTotal;
  final double deliveryFee;
  final String? currency;

  factory CartTotals.fromJson(dynamic json) {
    if (json is! Map) return const CartTotals(netTotal: 0, grandTotal: 0);
    return CartTotals(
      netTotal: toDouble(json['net_total']) ?? 0,
      grandTotal: toDouble(json['grand_total']) ?? 0,
      deliveryFee: toDouble(json['delivery_fee']) ?? 0,
      currency: json['currency'] as String?,
    );
  }
}

/// The full response shape shared by every `cart.*` mutation/read: `{items,
/// totals, warnings?}`. `warnings` is a soft stock-level notice (PRD F5
/// `add_item` "soft stock check (warn only)") — present only when the
/// server has something to say, never a reason to block the action.
class CartSnapshot {
  const CartSnapshot({required this.lines, required this.totals, this.warnings = const []});

  final List<CartLine> lines;
  final CartTotals totals;
  final List<String> warnings;

  factory CartSnapshot.fromJson(
    dynamic data, {
    String? Function(String?)? resolveImageUrl,
  }) {
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    final rawItems = map['items'];
    final lines = rawItems is List
        ? rawItems
            .map((e) => CartLine.fromJson(e as Map<String, dynamic>, resolveImageUrl: resolveImageUrl))
            .toList()
        : <CartLine>[];
    final rawWarnings = map['warnings'];
    final warnings = rawWarnings is List ? rawWarnings.map((e) => e.toString()).toList() : <String>[];
    return CartSnapshot(
      lines: lines,
      totals: CartTotals.fromJson(map['totals']),
      warnings: warnings,
    );
  }
}

/// One guest-cart line to fold into the server cart on login (PRD J2
/// `cart.merge {lines: [{item_code, qty}]}` — the server sums duplicates).
class CartMergeLine {
  const CartMergeLine({required this.itemCode, required this.qty});

  final String itemCode;
  final double qty;

  Map<String, dynamic> toJson() => {'item_code': itemCode, 'qty': qty};
}

/// Thin, typed wrapper over `grocery.api.cart.*` (PRD F5). Every method
/// requires a logged-in session — the backend returns 401 for guests, which
/// [ApiClient] surfaces as [UnauthenticatedException]. `CartStore` only
/// calls this when authed; guest lines live purely on-device.
class CartRepository {
  CartRepository(this._client);

  final ApiClient _client;

  Future<CartSnapshot> get() async {
    final data = await _client.post('grocery.api.cart.get');
    return _snapshot(data);
  }

  /// `qty` is in Kg for weight-sold items (PRD E1), an integer count
  /// otherwise — the caller (`CartStore`) already resolved which.
  Future<CartSnapshot> addItem(String itemCode, {required num qty, String? uom}) async {
    final data = await _client.post(
      'grocery.api.cart.add_item',
      data: {'item_code': itemCode, 'qty': qty, 'uom': ?uom},
    );
    return _snapshot(data);
  }

  Future<CartSnapshot> updateItem(String row, num qty) async {
    final data = await _client.post(
      'grocery.api.cart.update_item',
      data: {'row': row, 'qty': qty},
    );
    return _snapshot(data);
  }

  Future<CartSnapshot> removeItem(String row) async {
    final data = await _client.post('grocery.api.cart.remove_item', data: {'row': row});
    return _snapshot(data);
  }

  Future<CartSnapshot> clear() async {
    final data = await _client.post('grocery.api.cart.clear');
    return _snapshot(data);
  }

  /// Folds guest-local lines into the server cart on login (PRD J2).
  Future<CartSnapshot> merge(List<CartMergeLine> lines) async {
    final data = await _client.post(
      'grocery.api.cart.merge',
      data: {'lines': lines.map((l) => l.toJson()).toList()},
    );
    return _snapshot(data);
  }

  CartSnapshot _snapshot(dynamic data) =>
      CartSnapshot.fromJson(data, resolveImageUrl: _client.resolveFileUrl);
}
