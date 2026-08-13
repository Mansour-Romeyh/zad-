# Fly-to-basket animation — design

Date: 2026-07-23
Status: approved (design)

## Problem

Tapping the (+) button on an item card adds the item to the basket, but gives
no visible feedback beyond the bottom-nav count badge quietly ticking up. Users
don't notice the item was added. We want an add-to-basket animation that draws
the eye toward the basket.

(A separate, already-fixed issue — the (+) button opening the detail page for
weight-sold items — is **out of scope here**; the working tree already routes
weight items to `cart.add` and `product_card_add_test.dart` covers it. This spec
is only the animation.)

## Goal

When the user taps (+) on an item card **on the Home shell** (Home tab or
Favourites tab), a small rounded photo of the item flies in a curved arc from
the (+) button to the bottom-nav basket icon, shrinking as it travels
(~500 ms). On landing, the basket icon does a quick scale bounce and the count
badge pops. This makes "the basket now has your item" unmistakable.

## Non-goals

- Flying into a basket target on **pushed routes** (category browser, search,
  best-deals listing, product detail). Those pages have no bottom nav / basket
  icon on screen. They instead show a brief "Added ✓" toast. (This was the
  "Everywhere" option, explicitly deferred.)
- A new persistent floating basket button (FAB). The fly target is the existing
  bottom-nav basket icon.
- Changing the guest login-gate on add, or the weight/unit add logic.

## Scope decision (why Home + Favourites only)

The basket icon lives only in `ZadBottomNav`, which renders only on the
`HomePage` shell (an `IndexedStack` of Home / Favourites / Basket / Profile
behind the nav bar). The Home "Best deals" list and the Favourites grid are
`ProductCard`s **inside** that shell, so the basket icon is on screen and is a
valid fly target. Category, search, best-deals-listing and detail are separate
routes pushed on the root `Navigator`, above the shell — the nav bar is covered,
so there is no visible target. Those get the toast fallback.

## Architecture

Four small, isolated units.

### 1. `CartFlyController` + `CartFlyScope` — new file `lib/features/home/widgets/cart_fly.dart`

`CartFlyScope` is an `InheritedWidget` that wraps **only the Home shell**
(`HomePage`'s `Scaffold`). Its presence is the single source of truth for
"a fly is possible from here":

- `CartFlyScope.maybeOf(context)` returns the controller when the calling widget
  is inside the shell subtree, and `null` when it is on a pushed route (pushed
  routes are not descendants of `HomePage`, so they don't inherit the scope).
  This replaces any fragile "which screen am I on?" logic.

`CartFlyController` (a plain `ChangeNotifier`-free object; exposes a
`ValueListenable` for the bounce):

- `GlobalKey basketKey` — the key the bottom-nav basket icon attaches to, used to
  read the target's global center via its `RenderBox`.
- `ValueListenable<int> landings` — a counter incremented each time a flying
  photo lands. The basket icon listens and runs its bounce on change.
- `void fly({required Offset from, required ImageProvider image, required OverlayState overlay})`
  — inserts an `OverlayEntry` into the **root overlay** (above the nav bar),
  animates a rounded thumbnail along a quadratic-bezier arc from `from` to the
  basket center, shrinking + fading near the end (~500 ms,
  `Curves.easeInOutCubic`). On completion: remove the entry, then increment
  `landings`. Guards against a missing/unattached `basketKey` (no-op if the
  target can't be located).

The controller is created and owned by `_HomePageState` (one instance per shell)
and disposed with it. Any in-flight `OverlayEntry` is removed on dispose so a
route pushed mid-flight can't strand it.

### 2. Bottom-nav basket icon — edit `lib/features/home/widgets/zad_bottom_nav.dart`

The basket `_NavItem` (index `kBasketNavIndex`) becomes a small stateful icon
that:

- attaches `controller.basketKey` to its `Icon` so the controller can find its
  position;
- rebuilds via `ValueListenableBuilder(controller.landings)` and, on increment,
  runs a short scale bounce (an `AnimationController`, ~1.0 → 1.25 → 1.0,
  ~300 ms, `Curves.easeOut`);
- pops the existing `_CountBadge` with a brief scale when it appears / increments.

It reads the controller from `CartFlyScope.of(context)` (the nav bar is inside
the shell, so the scope is always present there). The other three nav items are
unchanged. The existing cart-count badge and its "9+" cap are unchanged.

### 3. The (+) button — edit `lib/features/home/widgets/product_card.dart`

Extract the (+) button into its own small `StatefulWidget` (`_AddButton`) so it
can report its exact on-screen center from its own `context.findRenderObject()`
(no `GlobalKey` churn on a rebuilt `StatelessWidget`).

`_handleAddTap` flow, after the **existing** login gate + `cart.add` succeed:

1. `final scope = CartFlyScope.maybeOf(context);`
2. If `scope != null` **and** `!MediaQuery.of(context).disableAnimations`:
   read the button center, build the item `ImageProvider`
   (`NetworkImage(product.imageUrl)`, or a bag-icon fallback when the url is
   null/empty), and call `scope.fly(from: center, image: img, overlay: Overlay.of(context))`.
3. Else: show a localized "Added ✓" `SnackBar` (`showAddedToBasketSnackBar`).

The add itself (weight → min weight, unit → 1) is unchanged. On `ApiException`
the existing `showErrorSnackBar` path runs and **no** fly plays (fly is
success-only).

### 4. Localization — edit `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`

Add `addedToBasket`:
- en: "Added to basket"
- ar: "أُضيف إلى السلة"

Regenerate `app_localizations*.dart` via the normal l10n build.

## Data flow

```
tap (+)  ──►  ensureLoggedIn ──► cart.add (await, success)
                                        │
                     ┌──────────────────┴───────────────────┐
             scope != null &&                          scope == null  OR
             !disableAnimations                        disableAnimations
                     │                                        │
       read (+) center → scope.fly(...)              showAddedToBasketSnackBar
                     │
      OverlayEntry: photo arcs → basket center (~500ms)
                     │
      entry removed → controller.landings++
                     │
      basket icon bounce + badge pop
```

## Behavior rules

- **Reduce motion** (`MediaQuery.disableAnimations`): no fly; toast + badge only.
- **Guest**: unchanged — (+) shows the login sheet first; no add, no fly.
- **Add fails**: existing error snackbar; no fly.
- **Image missing**: flying element is a basket/bag icon on a primary-color chip.
- **Route pushed mid-flight**: controller removes its entry on dispose.

## Files touched

- **New** `lib/features/home/widgets/cart_fly.dart` — `CartFlyScope`,
  `CartFlyController`, the flying-thumbnail overlay widget, and
  `showAddedToBasketSnackBar` helper.
- **Edit** `lib/features/home/home_page.dart` — own a `CartFlyController`; wrap
  the shell `Scaffold` in `CartFlyScope`.
- **Edit** `lib/features/home/widgets/zad_bottom_nav.dart` — basket icon: attach
  key, bounce on `landings`, badge pop.
- **Edit** `lib/features/home/widgets/product_card.dart` — `_AddButton` widget;
  fly-or-toast branch after a successful add.
- **Edit** `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` — `addedToBasket`.

## Testing

- **`product_card_add_test.dart` (extend):** with a `CartFlyScope` + a fake
  controller present, tapping (+) calls `fly` once with the item's image and does
  **not** navigate; cart still gets the line (weight + unit cases already exist).
- **New pushed-route case:** `ProductCard` with **no** `CartFlyScope` → tapping
  (+) shows the `addedToBasket` toast and adds to cart (no fly, no navigation).
- **Reduce-motion:** `MediaQuery(disableAnimations: true)` + scope present →
  no `fly` call; toast/badge path taken.
- **Bounce:** incrementing `controller.landings` rebuilds the basket icon with a
  scale bounce (assert a `Transform`/`ScaleTransition` runs).
- **Regression:** existing bottom-nav badge-count test still passes.

## Rollout

Ships with the next release APK (built against `https://zad.micronext.net` per
the standard `--dart-define=API_BASE_URL` build). No backend change.
