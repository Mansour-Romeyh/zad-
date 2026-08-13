# Design: In-place category browser (Shop by Category)

Date: 2026-07-19
Branch: feature/zad-mvp
Status: Approved (design)

## Problem

Tapping **"See All"** next to the home **Shop by Category** section opens
`CategoriesPage` (`/categories`), a flat 4-column grid of Item Groups. Tapping
any category — from that grid or from the home preview grid — opens
`CategoryPage` (`/category`), a separate paged product grid for one group.
Browsing across categories means bouncing in and out of pages.

We want a single **two-pane browser** (per the reference screenshot): a
scrollable rail of categories on the left, the selected category's products on
the right, switchable in place without navigation.

## Backend constraint

`grocery.api.catalog.get_categories` returns a **flat list** of Item Groups
(`{name, label, image, item_count}`) — no parent/child hierarchy is exposed.
Products for a group come from `catalog.items_by_category` (paged envelope
`{items, page, has_more}`, page_size 20). This design uses the flat list
directly; **no backend/API change**.

## Behavior

Route `/categories` renders the new two-pane browser:

- **Left rail** — a vertical, independently-scrollable list of *every* Item
  Group (image thumbnail + label). The selected group is highlighted with a
  light-green rounded background and a green left accent bar.
- **Right pane** — the selected group's products in a 2-column, infinite-scroll
  grid.
- Tapping a rail item swaps the right pane **in place** — no navigation, same
  page.
- **RTL-aware**: the rail sits on the *start* side (logical layout), so it flips
  to the right in Arabic automatically.
- **App bar**: static localized title **"Shop by Category"** (`l10n.shopByCategory`).
  The rail highlight already indicates the active group, so a changing title
  would be redundant.

### Entry points (both open route `/categories`)

- **"See All"** (home section header) → opens with the **first** category
  selected (no arg).
- **Home category tile** (`CategoryGrid`) → opens **pre-selected** to the tapped
  category via a new `CategoryBrowserArgs { String? initialGroupId }` route
  argument. If the id is absent from the loaded list (or null), fall back to the
  first category.

The old single-category page (`CategoryPage` / `/category`) and old grid page
(`CategoriesPage`) are **retired**.

## Architecture

Reuse the existing `PagedProductsView` — the proven pagination / empty / error /
auto-load-when-underfilled engine — **keyed by the selected category id**
(`key: ValueKey(selectedGroupId)`). Changing selection recreates the widget,
which fetches page 1 fresh for the new group. No pagination logic is duplicated.

- **Trade-off (accepted):** switching back to a previously-viewed category
  refetches page 1 — no per-category page/scroll cache. Simple and predictable.
  A caching pane (retain each category's loaded pages + scroll offset) is a
  possible later upgrade, explicitly **out of scope** here.

### Two-column products pane + adaptive ProductCard

The right pane shows **2 columns** to match the reference image. `ProductCard`
is currently **fixed at 160 px wide**, and two of those cannot fit in the narrow
right pane (~120 px cells). So `ProductCard` becomes **width-adaptive**: its
outer `SizedBox(width: 160)` is removed and the image box's `width: 160` becomes
`width: double.infinity`, so the card fills whatever cell/box it is given. Its
**height is unchanged** (image stays 140 px tall), so no existing grid overflows.

- `ProductCard`'s only unbounded-width caller is `BestDealList` (a horizontal
  `ListView`), which now wraps each card in `SizedBox(width: 160)` to preserve
  today's sizing. The other callers (`PagedProductsView`, `favourites_tab`,
  `search_page`) place the card in bounded grid cells, where the adaptive card
  simply fills the cell — same height as before, so they are unaffected.

Because the narrow 2-column cells are shorter than a full-width cell, the
browser needs taller cells than the default aspect ratio would give.
`PagedProductsView` gains **one optional param**, `mainAxisExtent` (`double?`,
default `null`). When null it keeps today's `childAspectRatio: 0.62` behavior
(full-width callers untouched); the browser passes a fixed `mainAxisExtent`
(~250 px) so the 2-column cells are tall enough for the card and never overflow.

### State / data flow

`CategoryBrowserPage` (StatefulWidget):

1. `initState` → load `CatalogRepository.getCategories()` into a
   `SectionState<List<GroceryCategory>>` (loading → data / error).
2. Rendered through `AsyncSection`: spinner while loading, retry on error,
   localized empty message (`l10n.categoriesEmpty`) when the list is empty.
3. On first successful load, resolve the initial selection: the arg's
   `initialGroupId` if present in the list, else the first category. Store the
   selected group id in state.
4. Body = `Row(children: [ CategoryRail(...), Expanded(PagedProductsView(...)) ])`.
   `PagedProductsView.fetchPage = (page) => repo.itemsByCategory(selectedId, page: page)`,
   `key: ValueKey(selectedId)`, `emptyText: l10n.categoryItemsEmpty`.
5. Tapping a rail item calls `setState` to change the selected id → the keyed
   `PagedProductsView` is rebuilt and reloads.

`CategoryRail` (StatelessWidget):
- Inputs: `categories`, `selectedId`, `onSelect(String groupId)`.
- Fixed-width vertical `ListView` of tiles (thumbnail via `RemoteImage` with the
  `Iconsax.category` placeholder + label via `nameFor(languageCode)`).
- Selected tile: light-green background + green left accent bar. Others plain.

## Components / files

New:
- `lib/features/category/category_browser_page.dart` — the two-pane page + the
  `CategoryBrowserArgs` route-args type.
- `lib/features/category/widgets/category_rail.dart` — the left rail widget.

Edited:
- `lib/features/product/paged_products_view.dart` — add optional
  `mainAxisExtent` param (default `null` preserves current behavior); remove the
  `Center` wrapper so the adaptive card fills the cell.
- `lib/features/home/widgets/product_card.dart` — make width-adaptive (drop the
  fixed 160-px width; image box `width: double.infinity`).
- `lib/features/home/widgets/best_deal_list.dart` — wrap each `ProductCard` in
  `SizedBox(width: 160)` to keep the horizontal list's card size.
- `lib/app.dart` — `/categories` → `CategoryBrowserPage`; remove the `/category`
  route.
- `lib/features/home/widgets/category_grid.dart` — tiles push `/categories` with
  `CategoryBrowserArgs(initialGroupId: category.id)`; stop importing
  `CategoryPageArgs`.
- `lib/features/home/home_page.dart` — no change to the See All target
  (`/categories`), confirm it passes no arg.

Deleted:
- `lib/features/category/category_page.dart`
- `lib/features/category/categories_page.dart`

## Error / empty / loading handling

- **Categories load**: `AsyncSection` — full-pane spinner (loading), retry
  affordance (error), `l10n.categoriesEmpty` (empty).
- **Products per category**: handled inside `PagedProductsView` — its own
  spinner, `l10n.categoryItemsEmpty` empty text, retry on first-page error, and
  silent drop of a failed subsequent page.

## Testing

New widget tests:
- `test/features/category/category_browser_page_test.dart`
  - loads categories and selects the first by default;
  - honors `CategoryBrowserArgs.initialGroupId` pre-selection;
  - tapping a rail item swaps the products pane (fetches the new group);
  - error / empty categories states render.
- `test/features/category/category_rail_test.dart`
  - renders one tile per category with labels;
  - marks exactly the selected tile;
  - `onSelect` fires with the tapped group id.

Preserve pagination coverage (retarget, don't drop):
- `test/features/category/category_page_test.dart` →
  `test/features/product/paged_products_view_test.dart` — the existing
  pagination / auto-load / empty / error tests are moved to mount
  `PagedProductsView` **directly** (with a `fetchPage` closure over
  `CatalogRepository.itemsByCategory`) instead of `CategoryPage`. This keeps the
  now-more-critical shared engine covered after `CategoryPage` is deleted, and
  adds a test for the new `mainAxisExtent` param.

Updated:
- `test/rtl_smoke_test.dart` — the "category page renders RTL" test mounts
  `CategoryBrowserPage` (its fake server answers both `get_categories` and
  `items_by_category`) instead of the retired `CategoryPage`.
- `test/features/home_content_test.dart` (or a new small nav test) — tapping a
  home `CategoryGrid` tile pushes `/categories` with `CategoryBrowserArgs`.
- `test/features/home_see_all_test.dart` — unchanged: See All still navigates to
  `/categories` (already stubbed as a marker route).

Removed (retired page):
- `test/features/category/categories_page_test.dart`

## Out of scope

- Backend category hierarchy (parent → sub-categories).
- Per-category page/scroll caching for instant switch-back.
- Sorting/filtering within the browser.
