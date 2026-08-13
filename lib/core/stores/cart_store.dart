import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/cart_repository.dart';
import '../../models/product.dart';
import '../constants.dart';
import '../json_utils.dart';
import '../session/session_store.dart';

/// A unified cart line — the shape both guest (local) and authed
/// (server-backed) modes present to the UI, so `BasketPage` never has to
/// branch on which mode is active.
class CartLineView {
  const CartLineView({
    required this.id,
    required this.itemCode,
    required this.nameEn,
    required this.nameAr,
    this.imageUrl,
    required this.unit,
    required this.price,
    required this.qty,
    this.amount,
    this.soldByWeight = false,
    this.weightStepG,
    this.minG,
    this.maxG,
    this.inStock = true,
  });

  /// Server Quotation Item row name when authed, the `item_code` when a
  /// guest (there is no server row yet) — either way, the id [CartStore]'s
  /// mutation methods expect back.
  final String id;
  final String itemCode;
  final String nameEn;
  final String nameAr;
  final String? imageUrl;
  final String unit;

  /// Unit price (`rate`/`price_per_uom`).
  final double price;

  /// Kg for weight-sold items (PRD E1), an integer count otherwise.
  final double qty;

  /// Server-computed line `amount` (authed lines) — authoritative when
  /// present. Guest lines leave it `null` and compute locally.
  final double? amount;
  final bool soldByWeight;
  final double? weightStepG;
  final double? minG;
  final double? maxG;
  final bool inStock;

  String nameFor(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;

  double get lineTotal => amount ?? price * qty;

  /// A copy with a new [qty]; pass `clearAmount: true` to drop the
  /// server-computed [amount] so [lineTotal] recomputes from `price * qty`
  /// (used for optimistic qty edits before the server confirms).
  CartLineView copyWith({double? qty, bool clearAmount = false}) => CartLineView(
    id: id,
    itemCode: itemCode,
    nameEn: nameEn,
    nameAr: nameAr,
    imageUrl: imageUrl,
    unit: unit,
    price: price,
    qty: qty ?? this.qty,
    amount: clearAmount ? null : amount,
    soldByWeight: soldByWeight,
    weightStepG: weightStepG,
    minG: minG,
    maxG: maxG,
    inStock: inStock,
  );
}

/// Typed sentinel pushed onto [CartStore.warnings] when the merge-on-login
/// (or a later retry) fails — the guest lines stay persisted and the next
/// server interaction retries automatically. The store has no
/// BuildContext/locale, so it emits this marker instead of display text;
/// `CartWarningsListener` (which sits below `Localizations`) maps it to
/// `AppLocalizations.cartSyncFailed`. Raw server warning strings on the
/// same stream pass through to the UI unchanged.
const kCartSyncFailedWarning = 'zad.cart.sync_failed';

/// In-memory cart state, exposed via `provider` above `MaterialApp` (PRD F5
/// `cart.get/add_item/update_item/remove_item/clear/merge`, E1 weight
/// qty-in-Kg, J2 guest-cart merge on login).
///
/// Guest mode keeps its lines purely on-device (persisted to
/// shared_preferences so they survive an app restart); authed mode is a
/// thin, always-fresh mirror of the server Quotation cart. [restore] loads
/// whichever applies at app boot; a [SessionStore] passed in reacts to
/// later login/logout transitions automatically.
class CartStore extends ChangeNotifier {
  CartStore({
    required CartRepository repository,
    SessionStore? session,
    Duration syncDebounce = const Duration(milliseconds: 350),
  }) : _repository = repository,
       _session = session,
       _syncDebounce = syncDebounce {
    _authed = session?.isAuthed ?? false;
    session?.addListener(_handleSessionChanged);
  }

  final CartRepository _repository;
  final SessionStore? _session;

  /// How long to coalesce rapid +/- taps on one line before firing a single
  /// server sync (PRD F5 `update_item`). Injectable so tests need not wait.
  final Duration _syncDebounce;

  bool _authed = false;
  bool _busy = false;
  Object? _error;

  List<CartLineView> _serverItems = const [];
  CartTotals _serverTotals = const CartTotals(netTotal: 0, grandTotal: 0);
  List<_GuestLine> _guestLines = <_GuestLine>[];

  // -- optimistic overlay (authed) --------------------------------------
  // The displayed cart is `_serverItems` (last server truth) with these
  // per-line overrides applied on top, so a +/- tap or remove repaints
  // instantly while the real `update_item`/`remove_item` syncs in the
  // background (debounced). On success the overlay entry is cleared as the
  // server snapshot is adopted; on failure it is cleared to roll back.
  final Map<String, double> _optimisticQty = {};
  final Set<String> _optimisticRemovals = {};
  final Map<String, Timer> _syncTimers = {};

  final _warningsController = StreamController<List<String>>.broadcast();

  /// One event per mutation whose server response carried soft stock
  /// warnings (PRD F5 `add_item` "soft stock check, warn only") — the UI
  /// turns each into a SnackBar. Never blocks the action that triggered it.
  Stream<List<String>> get warnings => _warningsController.stream;

  /// Resolves once any in-flight login/logout side effect (merge + refresh,
  /// or the logout reset) triggered by the last [SessionStore] transition
  /// has settled. The store is correct even if nobody ever reads this — it
  /// exists purely so callers (tests, or UI that wants a spinner) can await
  /// the transition deterministically instead of racing the listener.
  Future<void> get sessionSyncDone => _sessionSyncFuture ?? Future<void>.value();
  Future<void>? _sessionSyncFuture;

  bool get busy => _busy;
  Object? get error => _error;

  List<CartLineView> get items => _authed ? _composedServerItems() : _guestItemViews();

  /// The cart line for [itemCode] (guest or authed), or null when the item
  /// is not in the cart. Lets a `ProductCard` reflect and drive its own line
  /// without knowing which cart mode is active. Reads through [items], so the
  /// authed optimistic overlay and guest views are both honoured.
  CartLineView? lineFor(String itemCode) {
    for (final line in items) {
      if (line.itemCode == itemCode) return line;
    }
    return null;
  }

  /// `_serverItems` with the optimistic overlay applied: removed lines
  /// hidden, edited lines shown at their pending qty (line total recomputed).
  List<CartLineView> _composedServerItems() {
    if (_optimisticQty.isEmpty && _optimisticRemovals.isEmpty) return _serverItems;
    final out = <CartLineView>[];
    for (final line in _serverItems) {
      if (_optimisticRemovals.contains(line.id)) continue;
      final q = _optimisticQty[line.id];
      out.add(q == null ? line : line.copyWith(qty: q, clearAmount: true));
    }
    return out;
  }

  /// Number of lines in the cart (not total quantity) — what the bottom-nav
  /// badge shows.
  int get count => items.length;

  CartTotals get totals {
    if (!_authed) return _guestTotals();
    if (_optimisticQty.isEmpty && _optimisticRemovals.isEmpty) return _serverTotals;
    // Optimistic totals: recompute the net from the (overlaid) line totals and
    // preserve the server's fee/discount offset (grand − net) so the footer
    // moves with the taps; the next sync replaces this with server truth.
    final net = _composedServerItems().fold<double>(0, (sum, l) => sum + l.lineTotal);
    final offset = _serverTotals.grandTotal - _serverTotals.netTotal;
    return CartTotals(
      netTotal: net,
      grandTotal: net + offset,
      deliveryFee: _serverTotals.deliveryFee,
      currency: _serverTotals.currency,
    );
  }

  /// Loads whichever cart applies at app boot: guest → local storage,
  /// authed → `cart.get`. Mirrors [SessionStore.restore] — call once at
  /// startup (after [SessionStore.restore] has resolved) before relying on
  /// [items]/[count]. Never throws: an offline boot leaves [error] set and
  /// splash still navigates on; the basket retries later.
  Future<void> restore() async {
    _authed = _session?.isAuthed ?? false;
    // Load persisted guest lines in both modes: while authed they are the
    // pending-merge record of a previous session's failed merge-on-login
    // (PRD J2), which refresh() below folds into the server cart.
    await _loadGuestCart();
    if (_authed) {
      try {
        await refresh();
      } catch (_) {
        // _run already recorded the error and notified; nothing else to do.
      }
    } else {
      notifyListeners();
    }
  }

  /// Re-pulls the server cart, first retrying any still-pending guest-line
  /// merge (a previously failed merge-on-login) so the cart self-heals on
  /// the next refresh — pull, app-restart [restore], or the next [add].
  /// No-op while guest (nothing to pull).
  Future<void> refresh() async {
    if (!_authed) return;
    await _run(() async {
      await _mergePendingGuestLines();
      _applySnapshot(await _repository.get());
    });
  }

  /// Adds [product] to the cart. `qtyKg` is for weight-sold items (PRD E1);
  /// unit items pass an integer `qty` (defaults to 1). Authed: posts
  /// `add_item` and adopts the server's response as the new truth (soft
  /// stock warnings surface on [warnings]; a hard zero-stock error is
  /// rethrown for the caller to show). Guest: sums into the existing local
  /// line for this item, or appends a new one, then persists.
  Future<void> add(Product product, {double? qtyKg, int qty = 1}) async {
    final itemCode = product.itemCode ?? product.id;
    final effectiveQty = qtyKg ?? qty.toDouble();
    if (_authed) {
      await _run(() async {
        await _mergePendingGuestLines();
        _applySnapshot(
          await _repository.addItem(itemCode, qty: effectiveQty, uom: product.uom),
        );
      });
      return;
    }
    final idx = _guestLines.indexWhere((l) => l.itemCode == itemCode);
    if (idx >= 0) {
      _guestLines[idx] = _guestLines[idx].copyWith(qty: _guestLines[idx].qty + effectiveQty);
    } else {
      _guestLines.add(_GuestLine.fromProduct(product, qty: effectiveQty));
    }
    await _persistGuestCart();
    notifyListeners();
  }

  /// Sets a line's quantity outright — [id] is a [CartLineView.id] (server
  /// row when authed, item code when guest). Authed: applies the new qty to
  /// the optimistic overlay immediately (instant repaint) and debounces the
  /// real `update_item` so a burst of taps collapses into one call.
  Future<void> updateQty(String id, double qty) async {
    if (_authed) {
      _optimisticRemovals.remove(id);
      _optimisticQty[id] = qty;
      notifyListeners();
      _scheduleSync(id);
      return;
    }
    final idx = _guestLines.indexWhere((l) => l.itemCode == id);
    if (idx < 0) return;
    _guestLines[idx] = _guestLines[idx].copyWith(qty: qty);
    await _persistGuestCart();
    notifyListeners();
  }

  /// Whether [line] can step up one more increment (PRD E1: weight items
  /// clamp at `max_g`; unit items are unbounded above).
  bool canIncrement(CartLineView line) {
    if (!line.soldByWeight) return true;
    final maxKg = line.maxG != null ? line.maxG! / 1000.0 : null;
    return maxKg == null || line.qty < maxKg;
  }

  /// Whether [line] can step down one more increment (weight items clamp
  /// at `min_g`, falling back to `weight_step_g`; unit items floor at 1).
  bool canDecrement(CartLineView line) {
    if (!line.soldByWeight) return line.qty > 1;
    final minKg = _minKg(line);
    return line.qty > minKg;
  }

  /// Steps [line] up by one `weight_step_g` (weight items) or by 1 (unit
  /// items), clamped — PRD E1. Steps from the line's *current* (optimistic)
  /// qty so a fast burst of taps compounds correctly even if the passed
  /// [line] snapshot is a frame stale.
  Future<void> increment(CartLineView line) =>
      updateQty(line.id, _steppedQty(_liveLine(line), up: true));

  /// Steps [line] down by one `weight_step_g` (weight items) or by 1 (unit
  /// items), clamped — PRD E1.
  Future<void> decrement(CartLineView line) =>
      updateQty(line.id, _steppedQty(_liveLine(line), up: false));

  /// The current view of [line] (with any pending optimistic qty applied),
  /// falling back to the passed snapshot if the line is no longer present.
  CartLineView _liveLine(CartLineView line) {
    for (final l in items) {
      if (l.id == line.id) return l;
    }
    return line;
  }

  /// Removes a line. Authed: hides it from the overlay immediately and
  /// debounces the real `remove_item`; restores it on failure.
  Future<void> remove(String id) async {
    if (_authed) {
      _optimisticQty.remove(id);
      _optimisticRemovals.add(id);
      notifyListeners();
      _scheduleSync(id);
      return;
    }
    _guestLines.removeWhere((l) => l.itemCode == id);
    await _persistGuestCart();
    notifyListeners();
  }

  Future<void> clear() async {
    if (_authed) {
      _clearOptimistic();
      await _run(() async => _applySnapshot(await _repository.clear()));
      return;
    }
    _guestLines = [];
    await _persistGuestCart();
    notifyListeners();
  }

  @override
  void dispose() {
    _clearOptimistic();
    _session?.removeListener(_handleSessionChanged);
    _warningsController.close();
    super.dispose();
  }

  // -- session transitions (PRD J2) -----------------------------------

  void _handleSessionChanged() {
    final authed = _session!.isAuthed;
    if (authed == _authed) return;
    _authed = authed;
    if (authed) {
      _sessionSyncFuture = _mergeGuestCartThenRefresh();
    } else {
      _clearOptimistic();
      _serverItems = const [];
      _serverTotals = const CartTotals(netTotal: 0, grandTotal: 0);
      _sessionSyncFuture = null;
      notifyListeners();
    }
  }

  /// The guest→authed side effect (PRD J2): merge local lines to the
  /// server, clear local storage, pull the server cart — all via
  /// [refresh]. A failure (offline mid-login, server error) never
  /// propagates out of this listener-triggered background task: the guest
  /// lines stay persisted as the pending-merge record ([refresh]/[add]
  /// retry them automatically) and the user gets a warning SnackBar via
  /// [warnings] instead.
  Future<void> _mergeGuestCartThenRefresh() async {
    try {
      await refresh();
    } catch (_) {
      _warningsController.add(const [kCartSyncFailedWarning]);
    }
  }

  /// In-flight pending-merge future — memoized so concurrent callers
  /// (login-triggered refresh + an add fired right after the login sheet
  /// pops, the canonical J2 flow) all await ONE `cart.merge` instead of
  /// re-posting the same lines. The server sums duplicate lines, so a
  /// double-send would silently double every quantity.
  Future<void>? _pendingMergeFuture;

  /// Folds any still-pending guest lines into the server cart
  /// (`cart.merge` sums duplicates server-side), clearing local storage
  /// only after the merge succeeded. Throws on failure — the caller's
  /// `_run` records the error and the lines stay persisted for the next
  /// retry. Safe to call concurrently: all callers share one in-flight
  /// merge.
  Future<void> _mergePendingGuestLines() async {
    if (_pendingMergeFuture == null && _guestLines.isEmpty) return;
    final future = _pendingMergeFuture ??= _doMergePendingGuestLines();
    try {
      await future;
    } finally {
      // Guarded reset: only clear the slot for the future we awaited, so a
      // straggling caller can never clobber a newer retry's in-flight merge.
      if (identical(_pendingMergeFuture, future)) {
        _pendingMergeFuture = null;
      }
    }
  }

  Future<void> _doMergePendingGuestLines() async {
    final lines = _guestLines
        .map((l) => CartMergeLine(itemCode: l.itemCode, qty: l.qty))
        .toList();
    await _repository.merge(lines);
    _guestLines = [];
    await _persistGuestCart();
  }

  // -- server plumbing --------------------------------------------------

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      _error = e;
      notifyListeners();
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _applySnapshot(CartSnapshot snapshot) {
    _serverItems = snapshot.lines.map(_lineViewFromServer).toList();
    _serverTotals = snapshot.totals;
    if (snapshot.warnings.isNotEmpty) {
      _warningsController.add(snapshot.warnings);
    }
  }

  // -- optimistic sync (authed) -----------------------------------------

  /// (Re)arms the per-line debounce timer: a fresh tap on [id] within the
  /// window replaces the pending sync, so a burst collapses into one call.
  void _scheduleSync(String id) {
    _syncTimers[id]?.cancel();
    _syncTimers[id] = Timer(_syncDebounce, () => _flushSync(id));
  }

  /// Fires the pending mutation for [id] — a removal wins over a qty edit
  /// (the line is going away regardless).
  Future<void> _flushSync(String id) async {
    _syncTimers.remove(id);
    if (_optimisticRemovals.contains(id)) {
      await _syncRemove(id);
    } else if (_optimisticQty.containsKey(id)) {
      await _syncUpdate(id, _optimisticQty[id]!);
    }
  }

  Future<void> _syncUpdate(String id, double sentQty) async {
    try {
      final snapshot = await _repository.updateItem(id, sentQty);
      _applySnapshot(snapshot);
      // Clear the overlay only if no newer tap superseded what we just sent
      // (otherwise a fresh timer is pending and will reconcile the newer qty).
      if (!_syncTimers.containsKey(id) && _optimisticQty[id] == sentQty) {
        _optimisticQty.remove(id);
      }
      notifyListeners();
    } catch (_) {
      _optimisticQty.remove(id); // roll back to server truth
      _warningsController.add(const [kCartSyncFailedWarning]);
      notifyListeners();
    }
  }

  Future<void> _syncRemove(String id) async {
    try {
      final snapshot = await _repository.removeItem(id);
      _applySnapshot(snapshot);
      if (!_syncTimers.containsKey(id)) {
        _optimisticRemovals.remove(id);
      }
      notifyListeners();
    } catch (_) {
      _optimisticRemovals.remove(id); // restore the line
      _warningsController.add(const [kCartSyncFailedWarning]);
      notifyListeners();
    }
  }

  /// Drops every pending optimistic edit and its timer — used when the
  /// authoritative cart is replaced wholesale (logout, clear-all, dispose).
  void _clearOptimistic() {
    for (final timer in _syncTimers.values) {
      timer.cancel();
    }
    _syncTimers.clear();
    _optimisticQty.clear();
    _optimisticRemovals.clear();
  }

  CartLineView _lineViewFromServer(CartLine line) => CartLineView(
    id: line.row,
    itemCode: line.itemCode,
    nameEn: line.itemName ?? line.itemCode,
    nameAr: line.itemName ?? line.itemCode,
    imageUrl: line.imageUrl,
    unit: line.uom ?? '',
    price: line.rate,
    qty: line.qty,
    amount: line.amount,
    soldByWeight: line.soldByWeight,
    weightStepG: line.weightStepG,
    minG: line.minG,
    maxG: line.maxG,
    inStock: line.inStock,
  );

  // -- weight-step math (PRD E1) -----------------------------------------

  double _minKg(CartLineView line) {
    final minG = line.minG;
    final effectiveMinG = (minG != null && minG > 0) ? minG : (line.weightStepG ?? 500);
    return effectiveMinG / 1000.0;
  }

  double _steppedQty(CartLineView line, {required bool up}) {
    if (!line.soldByWeight) {
      final next = line.qty + (up ? 1 : -1);
      return next < 1 ? 1 : next;
    }
    final stepKg = (line.weightStepG ?? 500) / 1000.0;
    final minKg = _minKg(line);
    final maxKg = line.maxG != null ? line.maxG! / 1000.0 : null;
    var next = line.qty + (up ? stepKg : -stepKg);
    if (next < minKg) next = minKg;
    if (maxKg != null && next > maxKg) next = maxKg;
    return next;
  }

  // -- guest local cart (shared_preferences) ------------------------------

  List<CartLineView> _guestItemViews() => _guestLines
      .map(
        (l) => CartLineView(
          id: l.itemCode,
          itemCode: l.itemCode,
          nameEn: l.nameEn,
          nameAr: l.nameAr,
          imageUrl: l.imageUrl,
          unit: l.uom ?? '',
          price: l.price,
          qty: l.qty,
          soldByWeight: l.soldByWeight,
          weightStepG: l.weightStepG,
          minG: l.minG,
          maxG: l.maxG,
        ),
      )
      .toList();

  CartTotals _guestTotals() {
    final net = _guestLines.fold<double>(0, (sum, l) => sum + l.price * l.qty);
    return CartTotals(netTotal: net, grandTotal: net);
  }

  Future<void> _loadGuestCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kGuestCartKey);
      if (raw == null || raw.isEmpty) {
        _guestLines = [];
        return;
      }
      final decoded = jsonDecode(raw);
      _guestLines = decoded is List
          ? decoded.whereType<Map<String, dynamic>>().map(_GuestLine.fromJson).toList()
          : [];
    } catch (_) {
      // Storage unavailable or corrupt — start with an empty guest cart
      // rather than crashing; this is no worse than a fresh install.
      _guestLines = [];
    }
  }

  Future<void> _persistGuestCart() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_guestLines.isEmpty) {
        await prefs.remove(kGuestCartKey);
      } else {
        await prefs.setString(
          kGuestCartKey,
          jsonEncode(_guestLines.map((l) => l.toJson()).toList()),
        );
      }
    } catch (_) {
      // Best-effort: in-memory state is still correct for this session even
      // if the disk write fails.
    }
  }
}

/// One persisted guest-cart line: an on-device snapshot of the [Product]
/// fields needed to render and step a `CartLineView` without another
/// network round trip (PRD J2 "guest local cart").
class _GuestLine {
  const _GuestLine({
    required this.itemCode,
    required this.qty,
    this.uom,
    required this.price,
    required this.nameEn,
    required this.nameAr,
    this.imageUrl,
    this.soldByWeight = false,
    this.weightStepG,
    this.minG,
    this.maxG,
  });

  final String itemCode;
  final double qty;
  final String? uom;
  final double price;
  final String nameEn;
  final String nameAr;
  final String? imageUrl;
  final bool soldByWeight;
  final double? weightStepG;
  final double? minG;
  final double? maxG;

  factory _GuestLine.fromProduct(Product product, {required double qty}) => _GuestLine(
    itemCode: product.itemCode ?? product.id,
    qty: qty,
    uom: product.uom,
    price: product.pricePerUom ?? product.price,
    nameEn: product.nameEn,
    nameAr: product.nameAr,
    imageUrl: product.imageUrl ?? (product.imagePath.isEmpty ? null : product.imagePath),
    soldByWeight: product.soldByWeight,
    weightStepG: product.weightStepG,
    minG: product.minG,
    maxG: product.maxG,
  );

  _GuestLine copyWith({double? qty}) => _GuestLine(
    itemCode: itemCode,
    qty: qty ?? this.qty,
    uom: uom,
    price: price,
    nameEn: nameEn,
    nameAr: nameAr,
    imageUrl: imageUrl,
    soldByWeight: soldByWeight,
    weightStepG: weightStepG,
    minG: minG,
    maxG: maxG,
  );

  Map<String, dynamic> toJson() => {
    'item_code': itemCode,
    'qty': qty,
    'uom': uom,
    'price': price,
    'name_en': nameEn,
    'name_ar': nameAr,
    'image_url': imageUrl,
    'sold_by_weight': soldByWeight,
    'weight_step_g': weightStepG,
    'min_g': minG,
    'max_g': maxG,
  };

  factory _GuestLine.fromJson(Map<String, dynamic> json) => _GuestLine(
    itemCode: json['item_code'] as String? ?? '',
    qty: toDouble(json['qty']) ?? 0,
    uom: json['uom'] as String?,
    price: toDouble(json['price']) ?? 0,
    nameEn: json['name_en'] as String? ?? '',
    nameAr: json['name_ar'] as String? ?? '',
    imageUrl: json['image_url'] as String?,
    soldByWeight: toBool(json['sold_by_weight']),
    weightStepG: toDouble(json['weight_step_g']),
    minG: toDouble(json['min_g']),
    maxG: toDouble(json['max_g']),
  );
}
