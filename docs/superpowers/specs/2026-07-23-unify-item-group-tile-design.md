# Unify Item Group tile — Home grid & category rail

**Date:** 2026-07-23
**Status:** Approved (design), pending implementation plan

## Problem

The same Item Group image is presented two different ways:

- **Home page** (`lib/features/home/widgets/category_grid.dart`, `CategoryGrid`):
  a rounded-square tile — soft grey `ZadColors.surface` panel (radius
  `ZadRadii.tile` = 14), the image *contained* with 10px padding, and an
  `Iconsax.category` placeholder, with the label below.
- **Sidebar rail** (`lib/features/category/widgets/category_rail.dart`,
  `CategoryRail`, used by the "Shop By Category" browser opened from a Home
  tile): a **circular** avatar — `ClipOval`, white fill, a ring border, the
  image *cover*-cropped — plus a pale-green selected pill.

The two treatments (square-contained vs circle-cover) make the same catalog
image look inconsistent across the app.

## Decision

Unify to the **rounded-square tile** (Home's current look). The Home grid stays
visually as-is; the rail's circular avatar is replaced by the same rounded-square
tile. The rail keeps its selection affordance (which the grid doesn't have).

## Approach — one shared widget

Extract a small, presentational `CategoryTile` widget: the rounded-square image
container, so both surfaces render the Item Group image identically and can't
drift apart again.

### `CategoryTile` (new)

- Location: `lib/features/category/widgets/category_tile.dart` (shared between
  the home and category features).
- Renders a rounded square: `borderRadius` = `ZadRadii.tile` (14), image
  *contained* (`RemoteImage` with `BoxFit.contain`) with inner padding, and the
  `Iconsax.category` placeholder (via `RemoteImage.placeholder`) on empty/failed
  loads.
- Inputs: `imageUrl` (`String?`), and styling that lets each surface supply its
  own fill/border so the tile can contrast with its background:
  - `fillColor` (`Color`) — tile background.
  - `borderColor` (`Color?`) — optional hairline/emphasis border; null = no border.
  - `borderWidth` (`double`, default hairline) — used when `borderColor` is set.
- The tile itself is a plain `StatelessWidget`; animation and press/selection
  behaviour stay in the callers (the rail animates fill/border; the grid is
  static). Any `AspectRatio`/sizing wrapper stays with the caller so each layout
  controls its own dimensions.

### Home grid (`category_grid.dart`)

- Replace the inline `Container` + `RemoteImage` square with `CategoryTile`.
- Fill = `ZadColors.surface`, no border → visually identical to today.
- The `AspectRatio(1)`, label, spacing, 4-column grid, and the tap →
  `/categories` navigation are unchanged.

### Category rail (`category_rail.dart`)

- Replace the circular avatar block (`AnimatedScale` → `AnimatedContainer`
  circle → `ClipOval` → `AspectRatio` → `RemoteImage(cover)`) with the shared
  `CategoryTile` (image now `contain`, matching the grid).
- Rail panel background stays grey `ZadColors.surface` (keeps the existing
  inner-edge shadow that separates the rail from the white products pane). So
  rail tiles use a **white** fill for contrast against the panel:
  - **Unselected:** `CategoryTile` fill = `ZadColors.white`, hairline border
    `ZadColors.muted` @ ~0.2 alpha; label `ZadColors.muted`, weight w500.
  - **Selected:** the tile sits in the existing pale-green pill
    (`AnimatedContainer` with `color: ZadColors.paleGreen`, radius 18 — the
    invariant the rail test asserts). The tile's own fill becomes
    `ZadColors.paleGreen` with a `ZadColors.primary` border (~1.5px); label
    `ZadColors.ink`, weight w600.
- Keep: the press-scale (`AnimatedScale` 0.96 on tap), the implicit selection
  animations (fill/border/label transitions via `AnimatedContainer` /
  `AnimatedDefaultTextStyle`), the `railTile-<id>` keys, `onSelect`, and RTL
  directionality.
- Drop: `ClipOval`, the circular ring `AnimatedContainer`, and the selected
  avatar `scale: 1.06` enlargement (a subtle selected emphasis can remain via
  the pill + border; not required).

## Data flow

No data or navigation changes. `CategoryTile` is purely presentational; both
callers already have the `GroceryCategory` and its `imageUrl`.

## Error / edge handling

- Null/empty/failed image → `Iconsax.category` placeholder, unchanged, now
  centralised in `CategoryTile`.
- `surface` (#FAFAFA) ≈ `white` (#FFFFFF): the differing fills per surface
  (grey-on-white in the grid, white-on-grey in the rail) are intentional so the
  tile edge reads on either background; the hairline border reinforces the edge.

## Testing

- **Existing rail test** (`test/features/category/category_rail_test.dart`)
  must keep passing unchanged: a keyed `railTile-<id>` per category, tap
  reporting, and exactly one `ZadColors.paleGreen` (#EFF9F0) `Container` for the
  selected pill. The redesign preserves all three.
- **New `CategoryTile` widget test**: renders the placeholder when `imageUrl`
  is null/empty; renders an `Image` when a url is provided; applies the given
  fill (and border when supplied).
- **Home grid**: existing home/category-grid tests must keep passing (tiles
  render, tap navigates to `/categories` with the category id). Adjust only if a
  test asserted the old inline structure.
- Full `flutter test` run must stay green.

## Out of scope

- No change to the rail's width, the products pane, navigation, or the
  `GroceryCategory` model.
- No change to Home's grid layout (columns, spacing, aspect ratio) or label
  styling.
- The alternative "white rail panel + hairline divider so rail tiles are grey
  `surface`" (literally-identical fills) was considered and rejected as more
  disruptive to the rail's panel separation; the recommended grey-panel /
  white-tile approach was approved.
