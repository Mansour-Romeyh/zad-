# Card Inline Add / Qty / Weight Stepper — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The `+` on a product card adds the item directly (no navigation) and then morphs into an inline `[ − value + ]` stepper that drives the real cart line, mirroring the item detail page.

**Architecture:** Add a tiny `CartStore.lineFor(itemCode)` read accessor. Split `ProductCard` so only the image/name/price open the detail page, and a new sibling control zone (`_CardCartControl`) — outside that gesture — shows either the `+` button or the stepper, chosen by watching this item's live cart line via `context.select`. Reuse the store's existing `add/increment/decrement/remove/canIncrement` (same weight math the detail page uses). Reserve a fixed control-row height on every card so the fixed-height grids/lists don't overflow.

**Tech Stack:** Flutter (Dart `^3.11.3`), `provider`, `iconsax`, `flutter_test`.

## Global Constraints

- Flutter SDK is **not on PATH** — always invoke `~/.flutter-sdk/bin/flutter`.
- **Do not build the Android APK during iteration** (15 GB RAM machine hangs under uncapped Gradle). Verify with `~/.flutter-sdk/bin/flutter test` only. A device build, if any, is the user's step.
- **No backend changes. No change to the login gate** (`ensureLoggedIn` still guards the first add, exactly as today). Reuse `CartStore` methods unchanged.
- Reuse `formatWeightGrams` for weight labels; qty is stored in **Kg**, so grams = `qty * 1000`.
- Stepper `−` at the minimum **removes** the line and collapses back to `+`. `+` disables at `max_g` (via `canIncrement`).
- Every `ProductCard` caller (home best-deals list, paged category/best-deals grid, search, favourites, category browser) must still lay out with **no overflow**.

---

### Task 1: `CartStore.lineFor(itemCode)` accessor

**Files:**
- Modify: `lib/core/stores/cart_store.dart` (add one method near `items`, around line 157)
- Test: `test/core/stores/cart_store_test.dart` (append one test)

**Interfaces:**
- Produces: `CartLineView? CartStore.lineFor(String itemCode)` — the cart line whose `itemCode` matches (guest or authed), or `null` if the item is not in the cart. Used by Task 3's control zone.

- [ ] **Step 1: Write the failing test**

Append to `test/core/stores/cart_store_test.dart` (inside the top-level `main()`'s group or as a new `test(...)`; reuse the file's existing imports — it already imports `cart_store.dart`, `product.dart` and `../../helpers.dart` for `buildFakeCartRepository`):

```dart
test('lineFor returns the guest line for an item, else null', () async {
  final store = CartStore(repository: buildFakeCartRepository());
  addTearDown(store.dispose);

  expect(store.lineFor('UNIT-1'), isNull); // empty cart

  await store.add(
    Product.fromJson(const {
      'item_code': 'UNIT-1',
      'item_name': 'Canned Beans',
      'price_per_uom': 3000,
      'uom': 'pc',
      'in_stock': true,
    }),
  );

  expect(store.lineFor('UNIT-1')?.qty, 1);
  expect(store.lineFor('NOPE'), isNull);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/core/stores/cart_store_test.dart --plain-name 'lineFor returns the guest line'`
Expected: FAIL — `The method 'lineFor' isn't defined for the type 'CartStore'`.

- [ ] **Step 3: Add the accessor**

In `lib/core/stores/cart_store.dart`, immediately after the `items` getter (currently line 157) add:

```dart
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/core/stores/cart_store_test.dart --plain-name 'lineFor returns the guest line'`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/stores/cart_store.dart test/core/stores/cart_store_test.dart
git commit -m "feat(cart): add CartStore.lineFor(itemCode) accessor"
```

---

### Task 2: Accessibility labels for the stepper (l10n)

**Files:**
- Modify: `lib/l10n/app_en.arb` (after the `addedToBasket` entry)
- Modify: `lib/l10n/app_ar.arb` (after the `addedToBasket` entry)
- Generated (do not hand-edit): `lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces: `AppLocalizations.increaseQuantity` and `AppLocalizations.decreaseQuantity` (non-nullable `String` getters — the project sets `nullable-getter: false`). Used by Task 3.

- [ ] **Step 1: Add the English strings**

In `lib/l10n/app_en.arb`, directly after the line `"addedToBasket": "Added to basket",` add:

```json
  "increaseQuantity": "Increase quantity",
  "decreaseQuantity": "Decrease quantity",
```

- [ ] **Step 2: Add the Arabic strings**

In `lib/l10n/app_ar.arb`, directly after the line `"addedToBasket": "أُضيف إلى السلة",` add:

```json
  "increaseQuantity": "زيادة الكمية",
  "decreaseQuantity": "إنقاص الكمية",
```

- [ ] **Step 3: Regenerate the localizations**

Run: `~/.flutter-sdk/bin/flutter gen-l10n`
Expected: completes with no error; `lib/l10n/app_localizations.dart` now declares `String get increaseQuantity;` and `String get decreaseQuantity;`.

- [ ] **Step 4: Verify the getters exist**

Run: `grep -n "increaseQuantity\|decreaseQuantity" lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_ar.dart`
Expected: getter declarations in `app_localizations.dart` and concrete overrides returning the En/Ar strings in the two locale files.

- [ ] **Step 5: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_ar.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_ar.dart
git commit -m "i18n: add increase/decrease quantity a11y labels"
```

---

### Task 3: Inline stepper on the product card + height reservation

Restructure `ProductCard` so the control zone is a separate, tap-isolated sibling that morphs `+` ⇄ stepper, and enlarge every fixed-height grid/list cell (and the width test) so the taller card never overflows. These land together because the card only grows once the layouts reserve the room — splitting them would leave the suite red between commits.

**Files:**
- Modify: `lib/core/constants.dart` (add two top-level consts)
- Modify: `lib/features/home/widgets/product_card.dart` (restructure `build`; new `_CardCartControl`; move add handlers)
- Modify: `lib/features/product/paged_products_view.dart:267` (`childAspectRatio`)
- Modify: `lib/features/category/category_browser_page.dart:39` (`_cellHeight`)
- Modify: `lib/features/category/widgets/category_products_skeleton.dart:11` (default `cellHeight`)
- Modify: `lib/features/home/widgets/best_deal_list.dart:15` (`height`)
- Test: `test/features/product/product_card_add_test.dart` (append widget tests)
- Test: `test/features/product/product_card_width_test.dart:58` (bump narrow-cell height)

**Interfaces:**
- Consumes: `CartStore.lineFor` (Task 1); `AppLocalizations.increaseQuantity` / `decreaseQuantity` (Task 2); existing `CartStore.add/increment/decrement/remove/canIncrement`; existing `formatWeightGrams`; existing private `_AddButton` (kept, reports its own centre for the fly animation).
- Produces: control-zone widget keys used by tests — `Key('cardStepperDecrement')`, `Key('cardStepperValue')`, `Key('cardStepperIncrement')`; top-level `const double kProductCardControlHeight = 44;` and `const double kProductCardControlGap = 8;` in `constants.dart`.

- [ ] **Step 1: Write the failing widget tests**

Append to `test/features/product/product_card_add_test.dart` (inside `main()`, after the existing tests; reuse the file's existing `pumpCard`, `settleAdd`, `unitProduct`, `weightProduct` helpers — `settleAdd` settles any async cart mutation, not just the first add):

```dart
  testWidgets('unit item: (+) morphs into a stepper that steps and removes', (
    tester,
  ) async {
    final cart = await pumpCard(tester, unitProduct());

    // Not in cart: a compact (+), no stepper value.
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byKey(const Key('cardStepperValue')), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);

    // Morphed: stepper at qty 1, the plain (+) is gone.
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byKey(const Key('cardStepperValue')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(cart.count, 1);

    // (+) steps up to 2.
    await tester.tap(find.byKey(const Key('cardStepperIncrement')));
    await settleAdd(tester);
    expect(find.text('2'), findsOneWidget);
    expect(cart.items.single.qty, 2);

    // (−) steps back to 1.
    await tester.tap(find.byKey(const Key('cardStepperDecrement')));
    await settleAdd(tester);
    expect(find.text('1'), findsOneWidget);

    // (−) at the minimum removes the line and collapses to (+).
    await tester.tap(find.byKey(const Key('cardStepperDecrement')));
    await settleAdd(tester);
    expect(cart.count, 0);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byKey(const Key('cardStepperValue')), findsNothing);
  });

  testWidgets('tapping the stepper never opens the detail page', (tester) async {
    await pumpCard(tester, unitProduct());
    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);

    await tester.tap(find.byKey(const Key('cardStepperIncrement')));
    await settleAdd(tester);
    expect(find.text('DETAIL PAGE'), findsNothing);

    // But tapping the name still opens the detail page.
    await tester.tap(find.text('Canned Beans'));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL PAGE'), findsOneWidget);
  });

  testWidgets('weight item: stepper shows g/kg and steps by weight_step_g', (
    tester,
  ) async {
    final cart = await pumpCard(tester, weightProduct());

    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);
    expect(find.text('750 g'), findsOneWidget); // min_g 750 -> 0.75 kg

    await tester.tap(find.byKey(const Key('cardStepperIncrement')));
    await settleAdd(tester);
    expect(find.text('1 kg'), findsOneWidget); // 750 + 250 = 1000 g
    expect(cart.items.single.qty, 1.0);
  });
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `~/.flutter-sdk/bin/flutter test test/features/product/product_card_add_test.dart`
Expected: the three new tests FAIL (no `cardStepperValue` key; after add the card still shows `Icons.add`). The four existing tests still PASS.

- [ ] **Step 3: Add the reserved-height constants**

Append to `lib/core/constants.dart` (top-level, near the other layout constants):

```dart
/// Height reserved on every [ProductCard] for its add/stepper control row, so
/// fixed-height grid cells stay uniform whether the card shows a `+` or the
/// `[ − value + ]` stepper.
const double kProductCardControlHeight = 44;

/// Vertical gap between the price and the control row on a [ProductCard].
const double kProductCardControlGap = 8;
```

- [ ] **Step 4: Restructure `ProductCard.build` and add `_CardCartControl`**

In `lib/features/home/widgets/product_card.dart`:

**(a)** Move `_handleAddTap`, `_celebrateAdd`, and `_flyImage` OFF `ProductCard` and onto the new `_CardCartControl` below (they need only `product` + `context`). Keep `_handleFavouriteTap`, `_itemKey`, `_openDetail` on `ProductCard`.

**(b)** Replace the `build` method's `card` local (currently the big `GestureDetector(... onTap: _openDetail ...)` wrapping the whole `Column`) with this structure — the detail tap now wraps **only** the image/name/unit/price; the control zone is a sibling **outside** it:

```dart
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Detail-opening region: image + name + unit + price ONLY. The control
        // zone below is a sibling, deliberately outside this GestureDetector,
        // so stepper taps can never be stolen by the card-body tap (which would
        // otherwise open the detail page).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetail(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The SAME Stack as the current build — the image `Container`
              // with its `RemoteImage`, the favourite-heart
              // `PositionedDirectional`, and the out-of-stock badge — moved
              // here verbatim (copy it unchanged from the existing card body;
              // only its wrapping GestureDetector changes). It still owns its
              // own nested heart GestureDetector.
              Stack(
                children: [
                  // image Container + heart + out-of-stock badge (verbatim)
                ],
              ),
              const SizedBox(height: 8),
              Text(
                product.nameFor(languageCode),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  color: ZadColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                product.unitFor(languageCode),
                style: const TextStyle(fontSize: 11, color: ZadColors.muted),
              ),
              const SizedBox(height: 6),
              // Price only — the (+) moved into the control zone below.
              Row(
                children: [
                  Flexible(
                    child: Text(
                      formatPrice(
                        product.pricePerUom ?? product.price,
                        languageCode,
                      ),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ZadColors.ink,
                      ),
                    ),
                  ),
                  if (product.oldPrice != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      formatPrice(product.oldPrice!, languageCode),
                      style: const TextStyle(
                        fontSize: 12,
                        color: ZadColors.muted,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: ZadColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: kProductCardControlGap),
        _CardCartControl(product: product, enabled: inStock),
      ],
    );
```

Keep the existing out-of-stock wrap at the end of `build` unchanged:

```dart
    if (inStock) return card;
    return Opacity(
      opacity: 0.6,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(_grayscaleMatrix),
        child: card,
      ),
    );
```

**(c)** Add the new control-zone widget (same file, e.g. just above `_AddButton`). It watches only this item's line via `context.select` (a record → structural equality → repaints only when this card's qty / `+`-enabled changes, not on every cart tick):

```dart
/// The card's bottom control row (fixed height, always present so grid cells
/// stay uniform). Shows the (+) button when the item is not in the cart, and
/// the `[ − value + ]` stepper — bound to the live cart line — once it is.
class _CardCartControl extends StatelessWidget {
  const _CardCartControl({required this.product, required this.enabled});

  final Product product;
  final bool enabled;

  String get _itemKey => product.itemCode ?? product.id;

  @override
  Widget build(BuildContext context) {
    // Rebuild only when THIS item's line changes (present? qty? +-enabled?).
    final snap = context.select<CartStore, ({double qty, bool canInc})?>((cart) {
      final line = cart.lineFor(_itemKey);
      return line == null
          ? null
          : (qty: line.qty, canInc: cart.canIncrement(line));
    });

    return SizedBox(
      height: kProductCardControlHeight,
      child: snap == null ? _addButton(context) : _stepper(context, snap),
    );
  }

  Widget _addButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: _AddButton(
        enabled: enabled,
        label: l10n.add,
        onTap: (center) => _handleAddTap(context, center),
      ),
    );
  }

  Widget _stepper(BuildContext context, ({double qty, bool canInc}) snap) {
    final l10n = AppLocalizations.of(context);
    final label = product.soldByWeight
        ? formatWeightGrams(
            snap.qty * 1000,
            gramUnit: l10n.unitGram,
            kgUnit: l10n.unitKg,
          )
        : '${snap.qty.toInt()}';
    return Container(
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            key: const Key('cardStepperDecrement'),
            tooltip: l10n.decreaseQuantity,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: () => _handleDecrement(context),
            icon: const Icon(
              Iconsax.minus_cirlce,
              size: 22,
              color: ZadColors.primary,
            ),
          ),
          Flexible(
            child: Text(
              label,
              key: const Key('cardStepperValue'),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ZadColors.ink,
              ),
            ),
          ),
          IconButton(
            key: const Key('cardStepperIncrement'),
            tooltip: l10n.increaseQuantity,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: snap.canInc ? () => _handleIncrement(context) : null,
            icon: Icon(
              Iconsax.add_circle,
              size: 22,
              color: snap.canInc ? ZadColors.primary : ZadColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  void _handleIncrement(BuildContext context) {
    final cart = context.read<CartStore>();
    final line = cart.lineFor(_itemKey);
    if (line != null) cart.increment(line);
  }

  void _handleDecrement(BuildContext context) {
    final cart = context.read<CartStore>();
    final line = cart.lineFor(_itemKey);
    if (line == null) return;
    if (cart.canDecrement(line)) {
      cart.decrement(line);
    } else {
      cart.remove(line.id); // at the minimum → remove & collapse to (+)
    }
  }

  // --- moved verbatim from ProductCard (they only need `product` + context) ---

  Future<void> _handleAddTap(BuildContext context, Offset from) async {
    final ok = await ensureLoggedIn(context);
    if (!ok || !context.mounted) return;
    try {
      if (product.soldByWeight) {
        final selector = WeightSelector(
          stepG: product.weightStepG ?? 500,
          minG: product.minG,
          maxG: product.maxG,
        );
        await context.read<CartStore>().add(product, qtyKg: selector.kg);
      } else {
        await context.read<CartStore>().add(product);
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, e);
      return;
    }
    if (!context.mounted) return;
    _celebrateAdd(context, from);
  }

  void _celebrateAdd(BuildContext context, Offset from) {
    final controller = CartFlyScope.maybeOf(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (controller != null && !reduceMotion) {
      controller.fly(
        from: from,
        image: _flyImage(),
        overlay: Overlay.of(context),
      );
    } else {
      showAddedToBasketSnackBar(context);
    }
  }

  ImageProvider? _flyImage() {
    final url = product.imageUrl;
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }
}
```

Leave the existing `_AddButton` `StatefulWidget` (currently ~line 254) exactly as-is. Remove the now-dead `_handleAddTap` / `_celebrateAdd` / `_flyImage` from `ProductCard` (they moved into `_CardCartControl`).

- [ ] **Step 5: Reserve the extra row height in every fixed-size caller**

`lib/features/product/paged_products_view.dart` — the 2-column grid delegate (currently `childAspectRatio: 0.62` at line ~267): make cells taller so the control row fits at the narrowest phone width:

```dart
              // Taller cells reserve the always-present control row
              // (kProductCardControlHeight + gap). Verified against a ~360dp
              // device in Step 8 — lower further if a small phone overflows.
              childAspectRatio: 0.5,
```

`lib/features/category/category_browser_page.dart:39`:

```dart
  static const double _cellHeight =
      250 + kProductCardControlHeight + kProductCardControlGap;
```

`lib/features/category/widgets/category_products_skeleton.dart:11` (default value):

```dart
  const CategoryProductsSkeleton({
    this.cellHeight = 250 + kProductCardControlHeight + kProductCardControlGap,
    super.key,
  });
```

`lib/features/home/widgets/best_deal_list.dart:15`:

```dart
      height: 244 + kProductCardControlHeight + kProductCardControlGap,
```

(All four files already `import '../../core/constants.dart'` / `'../../../core/constants.dart'`, so the constants resolve with no new import.)

- [ ] **Step 6: Bump the narrow-cell height in the width test**

`test/features/product/product_card_width_test.dart:58` — the taller card needs a taller cell to prove "nothing overflows":

```dart
          child: SizedBox(
            width: 124,
            height: 320,
            child: ProductCard(product: _product()),
          ),
```

- [ ] **Step 7: Run the card + layout tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/features/product/ test/features/best_deal_test.dart test/features/category/ test/features/home/`
Expected: PASS — the three new stepper tests, the four existing add tests, both width tests, and the grid/best-deal/home tests all green (no overflow exceptions).

- [ ] **Step 8: Run the full suite**

Run: `~/.flutter-sdk/bin/flutter test`
Expected: PASS. (If a grid test reports a RenderFlex overflow on a small surface, lower `childAspectRatio` in `paged_products_view.dart` a notch — e.g. 0.48 — and re-run.)

- [ ] **Step 9: Commit**

```bash
git add lib/core/constants.dart lib/features/home/widgets/product_card.dart \
  lib/features/product/paged_products_view.dart \
  lib/features/category/category_browser_page.dart \
  lib/features/category/widgets/category_products_skeleton.dart \
  lib/features/home/widgets/best_deal_list.dart \
  test/features/product/product_card_add_test.dart \
  test/features/product/product_card_width_test.dart
git commit -m "feat(card): inline add/qty/weight stepper on product cards"
```

---

## Verification (post-implementation)

- [ ] Run `~/.flutter-sdk/bin/flutter analyze` — no new warnings.
- [ ] Run `~/.flutter-sdk/bin/flutter test` — all green.
- [ ] Drive the real change (invoke the `verify` skill): on a ~360dp device/emulator (built the user's usual way, `--dart-define=API_BASE_URL=https://zad.micronext.net`, Gradle capped per the RAM constraint):
  - Tap `+` on a home best-deals card and a category-grid card → item adds, no navigation, card morphs to the stepper; the fly-to-basket animation plays once.
  - Step `+`/`−`; confirm the basket badge and totals track; `−` at 1 (or min weight) removes and collapses to `+`.
  - Confirm a weight item shows `500 g` / `1.5 kg` and steps by its `weight_step_g`.
  - Confirm no card overflows in the home list, the paged category grid, search results, and favourites; re-open a listing with items already in the basket → their cards show the stepper pre-populated.

## Notes / follow-ups

- The `+` in the not-in-cart state sits trailing-aligned on its reserved row (faithful to the approved mockup). If the user later prefers a full-width "Add" bar that morphs into the stepper, that's a localized change to `_CardCartControl._addButton`.
- `childAspectRatio: 0.5` is a safe starting value for the ratio-based paged grid; Step 8 tunes it against a real small-phone width. The fixed-`mainAxisExtent` callers (category browser, skeleton) and the horizontal best-deals list are already exact via the reserved-height constants.
