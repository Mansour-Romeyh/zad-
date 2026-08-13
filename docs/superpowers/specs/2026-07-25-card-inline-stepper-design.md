# Inline add / qty / weight stepper on the product card — design

Date: 2026-07-25
Status: approved (design)

## Problem

The (+) button on a `ProductCard` has two problems:

1. **It can open the item detail page instead of adding.** The whole card body
   is wrapped in one detail-opening `GestureDetector` (`product_card.dart`), and
   on a real device that outer tap can win the gesture arena over the nested
   (+) — so tapping (+) navigates to `/product` instead of adding to the basket.
2. **There is no way to see or change the quantity from the list.** Once an item
   is added, the card looks unchanged. To adjust qty (or grams for weight items)
   the shopper must open the item detail page. The detail page already has a
   `[ − value + ]` stepper (`product_detail_page.dart`); the card has nothing.

We want the card's (+) to add directly, then **become an inline stepper** that
adjusts the real cart line — mirroring the detail page — so shoppers never have
to open an item just to change how much they want.

## Goal

- Tapping (+) on a card adds the item to the basket **without navigating**:
  - unit item → qty 1;
  - weight item → the minimum sellable weight (`weight_step_g` clamped up to
    `min_g`), the same value the detail page's selector starts at.
- Once the item is in the cart, the card's control zone shows a full-width
  **stepper `[ − value + ]`** on its own row below the price:
  - unit item → integer qty (`2`);
  - weight item → formatted weight (`500 g`, `1.5 kg`) via the existing
    `formatWeightGrams`.
- `+` steps up by 1 / one `weight_step_g` (disabled at `max_g` for weight items).
- `−` steps down by 1 / one `weight_step_g`; **at the minimum, `−` removes the
  line and the zone collapses back to a single (+)** (standard grocery pattern).
- The stepper reflects the **live cart line**: opening a listing shows the
  stepper already populated for anything currently in the basket.

## Non-goals

- **No change to the login gate.** The first add still calls `ensureLoggedIn`
  exactly as the detail page and current card do. Guests still get the login
  sheet before an add.
- **No change to the weight/qty stepping math or the cart API.** We reuse
  `CartStore.increment/decrement/canIncrement/canDecrement/remove` unchanged.
- **No backend work.**
- **No new persistent floating basket / redesign of the detail page.**
- The fly-to-basket animation is unchanged in behavior — it still plays once, on
  the first add from the Home shell (see Behavior rules).

## Design decisions (from brainstorming)

- **− at the minimum removes the line** and collapses to (+), rather than
  greying out (the detail page greys out; the card removes — the standard
  grocery-list behavior the user chose).
- **The stepper sits on its own full-width row below the price.** The control
  zone is a **fixed-height** row that is always present (showing either the (+)
  or the stepper), so every grid cell grows by the same amount and card heights
  stay uniform — no per-state height change, no grid overflow.

## Architecture

Three small, isolated changes. No new files.

### 1. `CartStore.lineFor(itemCode)` — edit `lib/core/stores/cart_store.dart`

Add a single read-only accessor:

```dart
/// The cart line for [itemCode] (guest or authed), or null if the item is
/// not in the cart. Lets a ProductCard reflect and drive its own line.
CartLineView? lineFor(String itemCode) {
  for (final l in items) {
    if (l.itemCode == itemCode) return l;
  }
  return null;
}
```

`items` already composes the optimistic overlay (authed) or the guest views, so
`lineFor` is correct in both modes with no extra state. All mutation still goes
through the existing `add` / `increment` / `decrement` / `remove`.

### 2. Card control zone + tap regions — edit `lib/features/home/widgets/product_card.dart`

**Restructure the tap regions (fixes bug 1 by construction):**

- Wrap **only** the image stack + name + unit + price in the detail-opening
  `GestureDetector` (`onTap: _openDetail`).
- Render the **control zone as a sibling below it, outside that detector**, so a
  tap on (+) / − / stepper can never be claimed by the card-body tap. Tapping
  the photo / name / price still opens `/product`.
- The favourite heart keeps its own nested `GestureDetector` on the image stack
  (unchanged).

**Control zone (new `_CardCartControl` widget), fixed height:**

- Reads its line via `context.select<CartStore, _LineSnapshot?>(...)` keyed on
  `itemCode`, so only this card's zone repaints when its own qty changes — not
  the whole grid on every cart tick. The selected value is a small comparable
  snapshot (present flag, qty, canIncrement, canDecrement, soldByWeight,
  weightStepG/minG/maxG) so `select` rebuilds only on a real change.
- **No line (not in cart):** show the existing rounded green (+) button
  (kept as `_AddButton` so it can still report its own center for the fly
  animation). `onTap` → `_handleAddTap` (unchanged add + fly/toast logic).
  Disabled + greyed when `!inStock` (as today).
- **Line present (in cart):** show a full-width pill `[ −  value  + ]`:
  - value: `'$qty'` for unit items; `formatWeightGrams(qty * 1000, …)` for
    weight items.
  - `+` → `cart.read.increment(line)`, disabled when `!cart.canIncrement(line)`.
  - `−` → if `cart.canDecrement(line)` then `cart.decrement(line)`, else
    `cart.remove(line.id)` (removes and collapses back to (+)).
  - The `+`/`−` are `IconButton`s using the same `Iconsax.add_circle` /
    `Iconsax.minus_cirlce` icons as the detail-page stepper, with semantics
    labels.

The card remains a `StatelessWidget`; the control zone (`_CardCartControl`)
does the `select`. `increment`/`decrement`/`remove` are called via
`context.read<CartStore>()` at tap time, and the *current* line is re-read from
the store at tap time (so a fast burst of taps compounds on fresh state, exactly
like the basket page relies on `_liveLine`).

### 3. Grid cell height — edit `lib/features/product/paged_products_view.dart` (+ any fixed `mainAxisExtent` / `childAspectRatio` callers)

The control row adds a fixed height to every card. Adjust the grid so cells
reserve it:

- `_ProductsGrid` uses `childAspectRatio: 0.62`; lower it (taller cells) by the
  control-row height so the always-present zone never overflows.
- Callers that pass a fixed `mainAxisExtent` (the category browser's narrow
  pane) get a matching bump.
- The horizontal best-deals list (`best_deal_list.dart`) sizes its cards too;
  verify its item height reserves the control row.

Exact px values are tuned during implementation against the real rendered
height (verified with the running app), not guessed here.

## Data flow

```
                      ┌───────────────── card control zone ─────────────────┐
 cart.lineFor(code) ─►│  line == null            │        line != null      │
                      │        │                 │             │            │
                      │   [ + ] button           │   [ −   value   + ]      │
                      │        │                 │      │            │      │
                      │  ensureLoggedIn          │  minimum? ─yes─► remove  │
                      │        │                 │      │no                 │
                      │  cart.add(qty1 / minKg)  │  cart.decrement / +      │
                      │        │                 │             │            │
                      │  fly-to-basket / toast   │  optimistic repaint,     │
                      │  (first add, unchanged)  │  debounced server sync   │
                      └──────────────────────────┴──────────────────────────┘
   any change ─► items / lineFor recompute ─► select fires ─► this card repaints
```

## Behavior rules

- **Reflects live cart:** entering any listing, a card already in the basket
  shows its stepper at the current qty/weight; removing it elsewhere collapses
  the card back to (+).
- **− at minimum:** removes the line, zone collapses to (+).
- **+ at max (weight):** disabled at `max_g` (via `canIncrement`).
- **Guest:** first (+) shows the login sheet (unchanged). After login the add
  proceeds and the stepper appears.
- **Out of stock:** no line → disabled (+) and the greyscale card (as today); a
  line that exists while out of stock still shows the stepper so it can be
  reduced/removed.
- **Fly animation:** plays once on the first add from the Home shell (unchanged);
  subsequent +/− steps just repaint the stepper (no fly).
- **Rebuild scope:** only the tapped card's control zone repaints (via `select`).

## Files touched

- **Edit** `lib/core/stores/cart_store.dart` — add `lineFor(itemCode)`.
- **Edit** `lib/features/home/widgets/product_card.dart` — split detail-tap
  region from a new fixed-height `_CardCartControl` zone; (+)-or-stepper morph;
  keep `_AddButton` for the fly center.
- **Edit** `lib/features/product/paged_products_view.dart` — taller grid cells
  (`childAspectRatio` / `mainAxisExtent`) to reserve the control row.
- **Verify/adjust** `lib/features/home/widgets/best_deal_list.dart` — horizontal
  card height reserves the control row.
- **Possibly edit** `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` — a11y labels
  for the stepper `−`/`+` if no existing string fits (regenerate localizations).

## Testing

- **`product_card_add_test.dart` (extend):**
  - Not in cart → card shows (+), no stepper. Tap (+) → `cart.add` called with
    qty 1 (unit) / min Kg (weight); **no navigation** to `/product`.
  - After add → card shows the stepper at the right value (unit `1`; weight the
    min-weight label).
- **Stepper drives the cart (new cases):**
  - `+` calls `increment` (qty/weight goes up; clamped at `max_g` → `+` disabled).
  - `−` above minimum calls `decrement`.
  - `−` at the minimum calls `remove(line.id)` and the card collapses to (+).
- **Reflects existing cart:** build a card for an item already in the cart →
  stepper renders at that qty without tapping.
- **Tap isolation:** tapping the stepper area does **not** navigate; tapping the
  image/name/price **does** open `/product` (guards the bug-1 fix).
- **Weight formatting:** weight line shows `500 g` / `1.5 kg` via
  `formatWeightGrams`.
- **Regression:** existing fly-to-basket test and grid/pagination tests still
  pass; every `ProductCard` caller (home best-deals, category grid, search,
  favourites) still lays out without overflow.

## Rollout

Ships with the next release APK (built against `https://zad.micronext.net` per
the standard `--dart-define=API_BASE_URL` build). No backend change; no
migration.
