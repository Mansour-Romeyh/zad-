# Banner → multiple items ("Items" link type)

**Date:** 2026-08-29
**Status:** Design — awaiting review
**Extends:** [2026-07-25-clickable-banners-design.md](./2026-07-25-clickable-banners-design.md)

## Goal

Let an admin link a single App Banner to **several** Items (a table-multiselect
in the backend). Tapping such a banner in the app opens a **new screen** that
lists exactly those items in the standard product grid.

This is additive: the existing single **Item**, **Item Group**, **URL**, and
**None** link types are unchanged. A new **Items** (plural) link type is added
alongside them.

## Decisions (locked)

- **New link type** `Items`, kept separate from the single `Item` type — no
  migration of existing banners.
- **Tap target** is a product grid identical to the Best Deals screen
  (`PagedProductsView` + `ProductCard`), titled with the banner's title.
- **Order** = the admin's selection order.

## Backend (grocery app)

### New child doctype: `App Banner Item`
- `istable = 1`, module `Grocery`.
- One field: `item` — Link → `Item`, `in_list_view = 1`, `reqd = 1`.
- Purpose: the row type for the parent's Table MultiSelect.

### `App Banner` doctype changes
- `link_type` Select options become: `None\nItem\nItem Group\nItems\nURL`.
- New field `link_items` — **Table MultiSelect**, `options = "App Banner Item"`,
  `depends_on = "eval:doc.link_type=='Items'"`, placed after `link_url`.
- `field_order` updated to include `link_items`.

### `app_banner.py` (`AppBanner.validate`)
- Extend the helper-field logic: for `link_type == "Items"`, `link_value` is
  left blank (the items live in the child table), and the single-link helper
  fields (`link_item`/`link_item_group`/`link_url`) are cleared as today.
- Validate: `Items` requires **≥1** row in `link_items`, else
  `frappe.throw(_("Select at least one item for an 'Items' banner."))`.
- When `link_type` changes **away** from `Items`, clear `link_items` (mirror of
  how the single helpers are blanked), so stale rows never leak into the API.

### `api/home.py` (`get_banners`)
- For each banner, when `link_type == "Items"`, attach
  `link_items: [item_code, ...]` (child rows in `idx` order). Other banners get
  `link_items: []` (or omit — the app treats missing as empty).
- Existing `image/title/link_type/link_value` fields are unchanged.
- Implementation: fetch the parent rows as today; for `Items` banners, read the
  child table (`frappe.get_all("App Banner Item", filters={"parent": name},
  fields=["item"], order_by="idx asc", pluck="item")`). Batched per-banner is
  fine — banners are few.

### `api/catalog.py` — new endpoint `get_items_by_codes`
```python
@frappe.whitelist(allow_guest=True)
def get_items_by_codes(item_codes):
    """ItemCards for an explicit set of codes, in the given order.
    Returns the standard paged envelope with everything on page 1
    (has_more: False) so the app reuses PagedProductsView unchanged."""
```
- Parse `item_codes` (JSON string or list; guard non-list → empty).
- Clamp count to `MAX_PAGE_SIZE` (guest-facing amplification guard).
- Fetch visible/sellable rows only — same guard as `get_item`:
  `_VISIBLE_ITEM_FILTERS` + `item_group in visible_item_group_names()`.
- Reorder to match the requested `item_codes`, dropping any code that isn't
  visible/found (silently — a delisted item just disappears from the banner).
- Build cards via `build_item_cards` (one shared context, order preserved).
- Return `{"items": [...], "page": 1, "has_more": False}`.

## App (Flutter)

### Model — `AppBannerModel`
- Add `final List<String> linkItems;` (default `const []`).
- `fromJson`: parse `json['link_items']` as `List<String>` (tolerant: missing
  or non-list → `[]`).

### Action — `BannerAction`
- New variant `class BannerItemList extends BannerAction { final List<String>
  itemCodes; final String title; }`.
- `resolveBannerAction`: `case 'Items':` → when `banner.linkItems` is non-empty,
  return `BannerItemList(banner.linkItems, banner.title)`; else `BannerNone`.
  (Keep the existing blank-`link_value` guard for the other types.)

### Repository — `CatalogRepository`
- Add `Future<PagedItems<Product>> getItemsByCodes(List<String> codes)` calling
  `grocery.api.catalog.get_items_by_codes` and parsing via
  `PagedItems.fromJson` (same as `getBestItems`).

### Screen — `lib/features/product/banner_items_page.dart`
- New `BannerItemsPage` mirroring `BestDealsPage`: `AppBar(title: <banner
  title>)`, `CartFab`, body = `PagedProductsView(fetchPage: (page) => page == 1
  ? repo.getItemsByCodes(codes) : Future.value(const PagedItems(items: [],
  hasMore: false)), emptyText: <"no items" string>)`.
- Args passed via a small `BannerItemsArgs(codes, title)` (mirrors
  `CategoryBrowserArgs`).

### Route + dispatch
- `lib/app.dart`: add `'/banner-items': (_) => const BannerItemsPage()`.
- `promo_banner.dart` `_dispatch`: `case BannerItemList(:final itemCodes, :final
  title):` → `Navigator.pushNamed(context, '/banner-items', arguments:
  BannerItemsArgs(itemCodes, title))`.

### Localization
- Add `bannerItemsEmpty` (AR + EN) for the empty state. Screen title uses the
  banner's own title (no new string); if a banner has a blank title, fall back
  to an existing generic products string.

## Data flow

```
Admin: App Banner (link_type=Items, link_items=[A,B,C])
   → home.get_banners → {..., link_type:"Items", link_items:["A","B","C"]}
   → AppBannerModel.linkItems=[A,B,C]
   → tap → resolveBannerAction → BannerItemList([A,B,C], title)
   → /banner-items → CatalogRepository.getItemsByCodes([A,B,C])
   → catalog.get_items_by_codes → {items:[cardA,cardB,cardC], has_more:false}
   → PagedProductsView grid
```

## Error / edge handling
- **No visible items** (all delisted): endpoint returns `items: []` → grid shows
  `bannerItemsEmpty`. Banner still renders and is still tappable.
- **Empty selection** saved: blocked by `validate` (≥1 required); defensively,
  `resolveBannerAction` returns `BannerNone` so the banner is non-tappable.
- **Fetch failure**: `PagedProductsView` already renders its error/retry state.
- **Guest amplification**: count clamped to `MAX_PAGE_SIZE`; endpoint is
  read-only and guest-safe like the other catalog list endpoints.

## Testing
- **Backend** (`test_app_banner.py`, `tests/test_home.py`, catalog tests):
  - `validate` blanks/derives correctly for `Items`; rejects zero rows; clears
    `link_items` when switching away from `Items`.
  - `get_banners` returns `link_items` in `idx` order for an `Items` banner and
    `[]`/absent for others.
  - `get_items_by_codes`: preserves requested order; drops delisted/invisible
    codes; clamps oversized lists; empty input → empty envelope.
- **App**:
  - `banner_action` test: `'Items'` + non-empty list → `BannerItemList`;
    `'Items'` + empty → `BannerNone`.
  - `AppBannerModel.fromJson` parses/omits `link_items` tolerantly.
  - Widget test: tapping an `Items` banner pushes `/banner-items`; the screen
    renders the returned cards (fake `CatalogRepository`).

## Out of scope
- Reordering items by anything other than admin selection order.
- Pagination of the banner list screen (selection is bounded by
  `MAX_PAGE_SIZE`).
- Deploying to prod / backfill patches (tracked separately, like other banner
  work which is built-but-not-deployed).
```
