# Category Browser Redesign — Design Spec

**Date:** 2026-07-21
**Page:** `/categories` (`lib/features/category/category_browser_page.dart`, `widgets/category_rail.dart`)
**Direction:** Elevate the existing two-pane layout · **Motion:** refined & subtle
**Approved:** yes (design brainstorm)

## Goal

Make the "Shop By Category" browser feel smooth, elegant, and modern by removing
the current hard state-swaps (abrupt selected-tile change, spinner-flash on every
category switch, cards popping in with no motion) — **without** changing the proven
structure or RTL behavior.

## Non-goals

- No layout re-architecture (rail + grid stays).
- No new packages — all motion via Flutter built-ins.
- No change to `PagedProductsView`'s existing callers (best-deals listing) beyond a
  backward-compatible optional param.

## Structure (unchanged)

`Row[ CategoryRail | products pane ]`, selection swapped in place (no navigation),
directional widgets so Arabic flips the rail to the right edge. Products pane keyed by
selected group id so it reloads on switch.

## Components & changes

### 1. Left rail → floating panel (`CategoryRail`)
- Rail column sits on a soft `ZadColors.surface` panel with a subtle right-edge
  `BoxShadow`; the hard `VerticalDivider` in the page is removed.
- Each group tile:
  - **Circular** image avatar (`ClipOval`) with a thin ring — primary-green ring when
    selected, faint ring otherwise.
  - Selected highlight = rounded **paleGreen pill** via `AnimatedContainer` (~220ms
    ease) plus an animated green start-edge accent bar.
  - Avatar scales gently to ~1.06 when selected; label animates to `ink` / `w600` via
    `AnimatedDefaultTextStyle`.
  - Switching selection cross-fades the pill old→new tile, reading as a smooth slide.
  - Tap feedback: light press-scale (~0.96) via `AnimatedScale`.

### 2. Products pane → animated switch (`CategoryBrowserPage`)
- Wrap the keyed `PagedProductsView` in an `AnimatedSwitcher` (~250ms): outgoing pane
  fades + slides out a few px, incoming fades + slides in. Removes the spinner-flash swap.
- Loading state uses a **static skeleton grid** of soft placeholder cards instead of a
  lone spinner. Delivered via a new **optional** `skeleton` param on `PagedProductsView`
  (default keeps the current `CircularProgressIndicator`, so best-deals is untouched).

### 3. Product cards → staggered entrance
- Each card fades in + rises 8px on mount; delay = `min(index, 8) × 30ms` (capped so
  later / paged-in cards never lag). One-shot per card; resets on category switch.

## Hard constraints (from existing tests)

1. `category_rail_test` "highlights exactly the selected tile" asserts exactly **one**
   `Container` painted `paleGreen (0xFFEFF9F0)`. Preserve that single-paleGreen invariant
   (or update the test to a Key-based selected assertion).
2. `category_browser_page_test` taps a group and, after `pumpAndSettle`, expects the old
   product gone / new shown. Therefore **every animation must be one-shot / implicit — no
   infinitely-repeating `AnimationController`** (a repeating shimmer would deadlock
   `pumpAndSettle`). The loading skeleton is static for this reason.

## Testing

- Update `category_rail_test` to assert the animated selected state robustly while keeping
  the single-paleGreen invariant.
- Keep all `category_browser_page_test` contracts green (first/arg selection, swap, empty,
  retry).
- Add coverage: products pane wrapped in `AnimatedSwitcher`; skeleton renders while a page
  loads.
- Gate: `flutter analyze` clean; full suite green except the 5 known pre-existing
  basket/checkout failures.

## Rollout

App-side only. No backend or API changes. Ships in the next APK build.
