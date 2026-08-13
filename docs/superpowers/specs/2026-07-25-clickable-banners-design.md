# Clickable Banners with Typed Link Targets

**Date:** 2026-07-25
**Status:** Approved (design) — not yet deployed to prod

## Problem

The home promo banner supports a `link_type` (`None`/`Item`/`Item Group`/`URL`)
and a `link_value`, but two things are broken:

1. **Backend authoring.** `App Banner.link_value` is a plain free-text `Data`
   field. To point a banner at an Item or Item Group, the admin must hand-type
   the exact Frappe docname with no lookup and no validation — error-prone and
   opaque. When `link_type == 'Item'` the admin should get a Link picker for
   the **Item** doctype; when `Item Group`, a Link picker for **Item Group**;
   when `URL`, a normal URL text field.

2. **App behavior.** `AppBannerModel` already parses `link_type`/`link_value`,
   but `_BannerCard` has **no tap handler** — banners are not clickable at all.
   Tapping should: open the item detail page (Item), open the category browser
   at that group (Item Group), or open the external link (URL).

## Current State (verified)

- **Doctype** `App Banner`
  (`apps/grocery/grocery/grocery/doctype/app_banner/app_banner.json`):
  fields `image`, `title`, `link_type` (Select `None\nItem\nItem Group\nURL`),
  `link_value` (Data), `sequence`, `valid_from`, `valid_to`, `is_active`.
  Controller `app_banner.py` is an empty `Document` subclass.
- **API** `grocery.api.home.get_banners` returns
  `[{image, title, link_type, link_value}]` for active, in-window banners
  ordered by `sequence`.
- **App** `AppBannerModel` (`lib/models/app_banner.dart`) → `{imageUrl, title,
  linkType, linkValue}`. `PromoBanner` renders `_BannerCard` (single) or a
  `_BannerCarousel` of them. `_BannerCard` is image-only with **no** `onTap`.
- **Navigation targets already exist** (`lib/app.dart` route table):
  - `/product` — arg is a **String item code**; `product_detail_page.dart`
    reads `args is String` and calls `CatalogRepository.getItem(itemCode)`,
    which resolves via `frappe.db.get_value("Item", item_code, ...)` — i.e. the
    Item **docname**. An Item Link value flows straight through.
  - `/categories` — arg is `CategoryBrowserArgs(initialGroupId: <id>)`;
    `category_browser_page.dart` matches `initialGroupId` against
    `category.id`, which is the **Item Group docname**. An Item Group Link
    value flows straight through.
- **URL seam already exists:** `Provider<UrlOpener>` in `lib/app.dart`
  (`lib/core/services/url_opener.dart`) — `open(url)` returns whether the OS
  accepted the URL; `DefaultUrlOpener` uses
  `launchUrl(mode: LaunchMode.externalApplication)` and returns false for a
  scheme-less/invalid URL.
- **Error affordance already exists:** `showErrorSnackBar(context, error)`
  (`lib/core/errors/user_error.dart`).

## Design

### 1. Backend — `App Banner` doctype

Chosen approach: **conditional per-type fields** (over a single Dynamic Link,
which cannot represent the non-doctype `URL`/`None` cases cleanly).

New/changed fields:

| Field | Type | `depends_on` |
|---|---|---|
| `link_type` | Select `None\nItem\nItem Group\nURL` | always |
| `link_item` | Link → **Item** | `eval:doc.link_type=='Item'` |
| `link_item_group` | Link → **Item Group** | `eval:doc.link_type=='Item Group'` |
| `link_url` | Data (URL) | `eval:doc.link_type=='URL'` |
| `link_value` | Data, **read_only** | always (auto-derived) |

Field order places the three helper fields between `link_type` and
`link_value`.

`app_banner.py` gains `validate()`:

- Set `self.link_value` from the field matching `link_type`:
  - `Item` → `link_item`
  - `Item Group` → `link_item_group`
  - `URL` → `link_url`
  - `None`/blank → `""`
- Clear the two non-selected helper fields so no stale value persists.
- Validate that a non-empty `link_url` starts with `http://` or `https://`
  (else `frappe.throw`).

**Data contract is unchanged:** `get_banners` still returns
`{image, title, link_type, link_value}`. No API change, and the app keeps
reading `link_value`. `link_value` stays read-only rather than hidden so admins
can see the resolved target.

**Migration.** New patch
`grocery.patches.v1_0.backfill_app_banner_link_fields` (added to
`patches.txt`): for each existing `App Banner`, copy the current `link_value`
into `link_item` / `link_item_group` / `link_url` according to `link_type`, so
prod banners render correctly in the new form. Idempotent (skips rows whose
helper field is already set).

### 2. App — clickable banners

**Pure resolver** (new, testable without a widget tree). Maps a banner to a
typed action:

```
sealed BannerAction:
  BannerProduct(itemCode)
  BannerItemGroup(groupId)
  BannerUrl(url)
  BannerNone

BannerAction resolveBannerAction(AppBannerModel b):
  value = b.linkValue?.trim()
  switch b.linkType:
    'Item'       -> value empty ? none : product(value)
    'Item Group' -> value empty ? none : itemGroup(value)
    'URL'        -> value empty ? none : url(value)
    else         -> none   // 'None', null, unknown
```

Location: alongside the model (e.g. `lib/models/app_banner.dart` or a sibling
`banner_action.dart`).

**`_BannerCard` dispatch.** Compute `resolveBannerAction(banner)` in `build`:

- `BannerNone` → render exactly as today (no `GestureDetector`, not tappable).
- otherwise wrap the card in a tap handler that runs:
  - `BannerProduct` → `Navigator.pushNamed('/product', arguments: itemCode)`
  - `BannerItemGroup` →
    `Navigator.pushNamed('/categories', arguments: CategoryBrowserArgs(initialGroupId: groupId))`
  - `BannerUrl` → `ok = await context.read<UrlOpener>().open(url)`; if `!ok`,
    `showErrorSnackBar(context, ...)` (guard `context.mounted` across the await).

Reuses the existing `UrlOpener` provider and `showErrorSnackBar`. No new
dependencies. Applies in both the single-card and carousel paths because both
render `_BannerCard`.

### 3. Edge cases

- **Item Group not in the loaded category list** → `category_browser_page`
  falls back to its first group (existing behavior). Accepted; not addressed
  here.
- **Deleted/disabled Item** → `/product` → `get_item` throws → detail page
  shows its normal error state (existing behavior).
- **Empty/malformed URL** → `UrlOpener.open` returns false → error snackbar.
  Backend URL validation makes a scheme-less value unsavable in the first place.

### 4. Testing

**Backend** (`test_app_banner.py`):
- `validate()` derives `link_value` correctly for each `link_type` and clears
  the non-selected helper fields.
- Scheme-less `link_url` is rejected; `http(s)://…` is accepted.

**App:**
- Resolver unit tests: `Item`, `Item Group`, `URL`, `None`, and empty
  `link_value` for each typed case → `BannerNone`.
- Widget test: tapping an Item banner pushes `/product` with the item code
  (via a `NavigatorObserver`); tapping a URL banner calls a fake `UrlOpener`;
  a `BannerNone` banner has no tap target.

## Out of Scope

- Deploying to prod (build + test only, per project convention — surface to the
  user; do not deploy unless asked).
- Fixing the "Item Group not in loaded list" fallback.
- In-app webview for URLs (external browser only).
