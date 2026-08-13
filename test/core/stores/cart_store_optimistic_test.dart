import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/data/cart_repository.dart';
import 'package:zad/models/product.dart';

import '../../helpers.dart';

/// The basket's +/- steppers and remove must feel instant even when authed
/// (every mutation is a server round-trip). [CartStore] updates the displayed
/// line optimistically, then debounces the actual `update_item`/`remove_item`
/// so a burst of taps collapses into a single call, reconciling with (or
/// rolling back to) the server's answer.
class _FakeCartRepo implements CartRepository {
  final List<({String row, double qty})> updates = [];
  final List<String> removes = [];
  bool failNextUpdate = false;
  bool failNextRemove = false;

  /// When set, `update_item`/`remove_item` block until [openGate] — lets a
  /// test assert the optimistic state while the "server" call is in flight.
  Completer<void>? _gate;
  void gate() => _gate = Completer<void>();
  void openGate() {
    _gate?.complete();
    _gate = null;
  }

  CartSnapshot _oneLine(String row, String itemCode, double qty) => CartSnapshot(
    lines: [
      CartLine(
        row: row,
        itemCode: itemCode,
        qty: qty,
        uom: 'pc',
        rate: 1000,
        amount: 1000 * qty,
        itemName: itemCode,
      ),
    ],
    totals: CartTotals(netTotal: 1000 * qty, grandTotal: 1000 * qty),
  );

  @override
  Future<CartSnapshot> addItem(String itemCode, {required num qty, String? uom}) async =>
      _oneLine('row-$itemCode', itemCode, qty.toDouble());

  @override
  Future<CartSnapshot> updateItem(String row, num qty) async {
    updates.add((row: row, qty: qty.toDouble()));
    if (_gate != null) await _gate!.future;
    if (failNextUpdate) {
      failNextUpdate = false;
      throw Exception('update failed');
    }
    return _oneLine(row, row.replaceFirst('row-', ''), qty.toDouble());
  }

  @override
  Future<CartSnapshot> removeItem(String row) async {
    removes.add(row);
    if (_gate != null) await _gate!.future;
    if (failNextRemove) {
      failNextRemove = false;
      throw Exception('remove failed');
    }
    return const CartSnapshot(lines: [], totals: CartTotals(netTotal: 0, grandTotal: 0));
  }

  @override
  Future<CartSnapshot> get() async =>
      const CartSnapshot(lines: [], totals: CartTotals(netTotal: 0, grandTotal: 0));

  @override
  Future<CartSnapshot> clear() async =>
      const CartSnapshot(lines: [], totals: CartTotals(netTotal: 0, grandTotal: 0));

  @override
  Future<CartSnapshot> merge(List<CartMergeLine> lines) async =>
      const CartSnapshot(lines: [], totals: CartTotals(netTotal: 0, grandTotal: 0));
}

const _product = Product(
  id: 'ITEM-1',
  nameEn: 'Milk',
  nameAr: 'حليب',
  unitEn: 'pc',
  unitAr: 'pc',
  price: 1000,
  imagePath: '',
  itemCode: 'ITEM-1',
  pricePerUom: 1000,
  uom: 'pc',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// An authed store seeded with one line (row-ITEM-1, qty 1), a short debounce
  /// so tests need only a brief real delay to let a sync fire.
  Future<(CartStore, _FakeCartRepo)> authedCartWithOneLine() async {
    final repo = _FakeCartRepo();
    final session = await buildAuthedSessionStore();
    final cart = CartStore(
      repository: repo,
      session: session,
      syncDebounce: const Duration(milliseconds: 20),
    );
    await cart.add(_product);
    return (cart, repo);
  }

  Future<void> pastDebounce() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  test('increment shows the new qty immediately, before the server responds', () async {
    final (cart, repo) = await authedCartWithOneLine();
    addTearDown(cart.dispose);

    unawaited(cart.increment(cart.items.single));

    expect(cart.items.single.qty, 2); // optimistic — no await, no server yet
    expect(repo.updates, isEmpty); // debounce hasn't fired
  });

  test('a burst of taps collapses into ONE update_item carrying the final qty', () async {
    final (cart, repo) = await authedCartWithOneLine();
    addTearDown(cart.dispose);

    final line = cart.items.single; // qty 1 — deliberately reuse the stale ref
    cart.increment(line);
    cart.increment(line);
    cart.increment(line);

    expect(cart.items.single.qty, 4); // resolved from live state each time
    expect(repo.updates, isEmpty); // still debounced

    await pastDebounce();

    expect(repo.updates, hasLength(1));
    expect(repo.updates.single.qty, 4); // only the final value is sent
  });

  test('after the debounced sync succeeds the store adopts the server snapshot', () async {
    final (cart, repo) = await authedCartWithOneLine();
    addTearDown(cart.dispose);

    cart.increment(cart.items.single); // optimistic qty 2
    await pastDebounce();

    expect(repo.updates.single.qty, 2);
    expect(cart.items.single.qty, 2);
    expect(cart.items.single.lineTotal, 2000); // server amount 1000*2
  });

  test('optimistic qty updates the line total and grand total instantly', () async {
    final (cart, repo) = await authedCartWithOneLine();
    addTearDown(cart.dispose);

    expect(cart.totals.grandTotal, 1000);

    cart.increment(cart.items.single); // optimistic qty 2

    expect(cart.items.single.lineTotal, 2000); // price 1000 * qty 2
    expect(cart.totals.netTotal, 2000);
    expect(cart.totals.grandTotal, 2000);
  });

  test('a failed qty sync reverts the optimistic qty and warns', () async {
    final (cart, repo) = await authedCartWithOneLine();
    addTearDown(cart.dispose);
    repo.failNextUpdate = true;
    final warnings = <String>[];
    final sub = cart.warnings.listen(warnings.addAll);
    addTearDown(sub.cancel);

    cart.increment(cart.items.single);
    expect(cart.items.single.qty, 2); // optimistic

    await pastDebounce();

    expect(cart.items.single.qty, 1); // reverted to server truth
    expect(warnings, contains(kCartSyncFailedWarning));
  });

  test('remove hides the line immediately, before the server responds', () async {
    final (cart, repo) = await authedCartWithOneLine();
    addTearDown(cart.dispose);
    repo.gate();

    unawaited(cart.remove(cart.items.single.id));

    expect(cart.items, isEmpty); // optimistic removal
    repo.openGate();
    await pastDebounce();
  });

  test('a failed remove restores the line and warns', () async {
    final (cart, repo) = await authedCartWithOneLine();
    addTearDown(cart.dispose);
    repo.failNextRemove = true;
    final warnings = <String>[];
    final sub = cart.warnings.listen(warnings.addAll);
    addTearDown(sub.cancel);

    cart.remove(cart.items.single.id);
    expect(cart.items, isEmpty); // optimistic

    await pastDebounce();

    expect(cart.items, hasLength(1)); // restored
    expect(warnings, contains(kCartSyncFailedWarning));
  });
}
