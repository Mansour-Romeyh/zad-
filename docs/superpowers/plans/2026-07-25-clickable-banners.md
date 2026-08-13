# Clickable Banners with Typed Link Targets — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give App Banner admins a proper Link picker per link type (Item / Item Group / URL) and make home banners tappable so a tap opens the item, the category, or the external URL.

**Architecture:** Two independent codebases. **Backend** (Frappe app at `~/Frappe/grocery-bench/apps/grocery`): the `App Banner` doctype gains three conditional helper fields; a `validate()` hook derives the existing `link_value` from whichever helper matches `link_type`, so the `get_banners` API and its data contract are unchanged; a patch backfills existing rows. **App** (Flutter at `/home/frappe/Flutter/zad`): a pure resolver maps a banner to a typed `BannerAction`; `_BannerCard` dispatches a tap to `Navigator`/`UrlOpener`, reusing the existing `UrlOpener` provider and `showZadSnack` error affordance.

**Tech Stack:** Frappe/Python (`IntegrationTestCase`), Flutter/Dart 3.11 (`flutter_test`, `provider`).

## Global Constraints

- Backend app root: `~/Frappe/grocery-bench/apps/grocery` (module `grocery`). Bench: `~/Frappe/grocery-bench`, dev site is the default site.
- Backend tests pollute the dev site — run against the bench's test runner, not by hand-inserting into the dev DB. Run backend tests with: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module <dotted.module>` (use the same site these tests already run under).
- App SDK floor: Dart `^3.11.3`. Flutter analyze must stay clean: `flutter analyze` (SDK is at `~/.flutter-sdk`, not on PATH — invoke via its absolute path, e.g. `~/.flutter-sdk/bin/flutter`).
- The `get_banners` API contract stays exactly `[{image, title, link_type, link_value}]`. Do not change the API or the app's `AppBannerModel` JSON shape.
- `link_value` remains the single value the app reads; it is **derived** server-side and is read-only on the form.
- URL open failures surface via `showZadSnack(context, l10n.sectionErrorMessage, variant: ZadSnackVariant.error)` — identical to `profile_tab.dart:_openUrl`. Do not invent a new copy string.
- No new dependencies in either codebase. `url_launcher` and the `UrlOpener` seam already exist.
- Do NOT deploy to prod. Build + test only (project convention).

---

## File Structure

**Backend (`~/Frappe/grocery-bench/apps/grocery/grocery`):**
- Modify `grocery/doctype/app_banner/app_banner.json` — add `link_item`, `link_item_group`, `link_url`; make `link_value` read-only; update `field_order`.
- Modify `grocery/doctype/app_banner/app_banner.py` — add `validate()`.
- Modify `grocery/doctype/app_banner/test_app_banner.py` — unit tests for `validate()`.
- Create `grocery/patches/v1_0/backfill_app_banner_link_fields.py` — backfill helper fields from `link_value`.
- Modify `grocery/patches.txt` — register the patch.

**App (`/home/frappe/Flutter/zad`):**
- Create `lib/models/banner_action.dart` — `BannerAction` sealed class + `resolveBannerAction`.
- Modify `lib/features/home/widgets/promo_banner.dart` — dispatch a tap in `_BannerCard`.
- Create `test/models/banner_action_test.dart` — resolver unit tests.
- Modify `test/features/promo_banner_test.dart` — tap/navigation/URL widget tests.

---

## Task 1: Backend — conditional per-type fields on the doctype

**Files:**
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/doctype/app_banner/app_banner.json`

**Interfaces:**
- Consumes: nothing.
- Produces: fieldnames `link_item` (Link→Item), `link_item_group` (Link→Item Group), `link_url` (Data/URL), and a now-read-only `link_value` — consumed by Task 2's `validate()` and Task 4's patch.

- [ ] **Step 1: Add the three helper fields and make `link_value` read-only**

In `app_banner.json`, replace the `field_order` array (currently lines 10–19) with the version below (inserts the three helper fields right after `link_type`):

```json
 "field_order": [
  "image",
  "title",
  "link_type",
  "link_item",
  "link_item_group",
  "link_url",
  "link_value",
  "sequence",
  "valid_from",
  "valid_to",
  "is_active"
 ],
```

Then, inside the `fields` array, replace the single `link_value` field object (currently lines 39–43) with these four field objects (the three helpers plus the now-read-only, describe-derived `link_value`):

```json
  {
   "depends_on": "eval:doc.link_type=='Item'",
   "fieldname": "link_item",
   "fieldtype": "Link",
   "label": "Link Item",
   "options": "Item"
  },
  {
   "depends_on": "eval:doc.link_type=='Item Group'",
   "fieldname": "link_item_group",
   "fieldtype": "Link",
   "label": "Link Item Group",
   "options": "Item Group"
  },
  {
   "depends_on": "eval:doc.link_type=='URL'",
   "fieldname": "link_url",
   "fieldtype": "Data",
   "label": "Link URL",
   "options": "URL"
  },
  {
   "description": "Auto-filled from the selected link target. Read-only.",
   "fieldname": "link_value",
   "fieldtype": "Data",
   "label": "Link Value",
   "read_only": 1
  },
```

- [ ] **Step 2: Verify the JSON is well-formed**

Run: `python3 -m json.tool ~/Frappe/grocery-bench/apps/grocery/grocery/doctype/app_banner/app_banner.json > /dev/null && echo OK`
Expected: `OK` (no JSON error).

- [ ] **Step 3: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/doctype/app_banner/app_banner.json
git commit -m "feat(app-banner): per-type link fields (Item/Item Group/URL)"
```

---

## Task 2: Backend — `validate()` derives `link_value` and clears stale helpers

**Files:**
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/doctype/app_banner/app_banner.py`
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/doctype/app_banner/test_app_banner.py`

**Interfaces:**
- Consumes: the fields from Task 1.
- Produces: `AppBanner.validate()` — after any save, `link_value` equals the helper field selected by `link_type` (empty for `None`/blank), and the two non-selected helper fields are blanked. A non-empty `link_url` must start with `http://` or `https://` (else `frappe.throw`).

- [ ] **Step 1: Write the failing tests**

Replace the body of `test_app_banner.py` (the `IntegrationTestAppBanner` class) with these tests. Each builds an in-memory doc and calls `run_method("validate")` so no DB write is needed for the derivation checks; the URL-validation test inserts to exercise the throw path.

```python
# Copyright (c) 2026, Zad Grocery and Contributors
# See license.txt

import frappe
from frappe.tests import IntegrationTestCase


class IntegrationTestAppBanner(IntegrationTestCase):
	def _banner(self, **overrides):
		doc = frappe.get_doc(
			{
				"doctype": "App Banner",
				"image": "/files/x.png",
				"title": "T",
				"is_active": 1,
			}
		)
		doc.update(overrides)
		return doc

	def test_item_type_derives_link_value_from_link_item(self):
		doc = self._banner(link_type="Item", link_item="ITEM-1", link_url="http://stale")
		doc.run_method("validate")
		self.assertEqual(doc.link_value, "ITEM-1")
		self.assertFalse(doc.link_url)
		self.assertFalse(doc.link_item_group)

	def test_item_group_type_derives_link_value_from_link_item_group(self):
		doc = self._banner(link_type="Item Group", link_item_group="Products", link_item="ITEM-1")
		doc.run_method("validate")
		self.assertEqual(doc.link_value, "Products")
		self.assertFalse(doc.link_item)

	def test_url_type_derives_link_value_from_link_url(self):
		doc = self._banner(link_type="URL", link_url="https://zad.example/x", link_item="ITEM-1")
		doc.run_method("validate")
		self.assertEqual(doc.link_value, "https://zad.example/x")
		self.assertFalse(doc.link_item)

	def test_none_type_clears_link_value(self):
		doc = self._banner(link_type="None", link_item="ITEM-1")
		doc.run_method("validate")
		self.assertFalse(doc.link_value)
		self.assertFalse(doc.link_item)

	def test_scheme_less_url_is_rejected(self):
		doc = self._banner(link_type="URL", link_url="zad.example/x")
		with self.assertRaises(frappe.ValidationError):
			doc.run_method("validate")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.grocery.doctype.app_banner.test_app_banner`
Expected: FAIL — `validate` currently does nothing, so `link_value` stays empty/unchanged and no error is raised (assertions and `assertRaises` fail).

- [ ] **Step 3: Implement `validate()`**

Replace the whole body of `app_banner.py` with:

```python
# Copyright (c) 2026, Zad Grocery and contributors
# For license information, please see license.txt

import frappe
from frappe import _
from frappe.model.document import Document

# link_type -> the helper field that holds its target
_LINK_FIELD_BY_TYPE = {
	"Item": "link_item",
	"Item Group": "link_item_group",
	"URL": "link_url",
}


class AppBanner(Document):
	def validate(self):
		"""Derive ``link_value`` from the helper field matching ``link_type``
		(empty for ``None``/blank) and blank the non-selected helpers, so
		``link_value`` is a single source of truth for ``home.get_banners``.
		"""
		source = _LINK_FIELD_BY_TYPE.get(self.link_type)
		self.link_value = (self.get(source) or "").strip() if source else ""

		for field in _LINK_FIELD_BY_TYPE.values():
			if field != source:
				self.set(field, None)

		if self.link_type == "URL" and self.link_value and not self.link_value.startswith(
			("http://", "https://")
		):
			frappe.throw(_("Link URL must start with http:// or https://."))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.grocery.doctype.app_banner.test_app_banner`
Expected: PASS (5 tests).

- [ ] **Step 5: Run the existing banner API test to confirm no regression**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_home`
Expected: PASS. (The existing `banner_current_window` sets `link_value="Products"` directly with no `link_item_group`; `validate()` now blanks it to `""`, but that test only asserts titles and ordering, so it still passes.)

- [ ] **Step 6: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/doctype/app_banner/app_banner.py grocery/doctype/app_banner/test_app_banner.py
git commit -m "feat(app-banner): derive link_value from typed link fields"
```

---

## Task 3: Backend — backfill patch for existing banners

**Files:**
- Create: `~/Frappe/grocery-bench/apps/grocery/grocery/patches/v1_0/backfill_app_banner_link_fields.py`
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/patches.txt`

**Interfaces:**
- Consumes: Task 1 fields, Task 2 semantics.
- Produces: existing rows get `link_item`/`link_item_group`/`link_url` populated from their current `link_value`, so prod banners render correctly in the new form. Idempotent.

- [ ] **Step 1: Write the patch**

Create `backfill_app_banner_link_fields.py` with:

```python
# Copyright (c) 2026, Zad Grocery and contributors
# For license information, please see license.txt

"""Backfill App Banner typed link fields from the legacy ``link_value``.

``App Banner`` gained per-type link fields (``link_item``/``link_item_group``/
``link_url``); existing rows only carry the derived ``link_value``. Copy each
row's value into the field matching its ``link_type`` so it shows correctly in
the redesigned form. Uses ``db.set_value`` (no ``validate``) so a dangling
legacy reference is preserved as-is rather than raising a link error.
Idempotent — rows whose target field is already set are skipped.
"""

import frappe

_FIELD_BY_TYPE = {
	"Item": "link_item",
	"Item Group": "link_item_group",
	"URL": "link_url",
}


def execute():
	rows = frappe.get_all(
		"App Banner",
		filters={"link_type": ["in", list(_FIELD_BY_TYPE)], "link_value": ["is", "set"]},
		fields=["name", "link_type", "link_value"],
	)
	for row in rows:
		field = _FIELD_BY_TYPE[row.link_type]
		if frappe.db.get_value("App Banner", row.name, field):
			continue
		frappe.db.set_value("App Banner", row.name, field, row.link_value, update_modified=False)
```

- [ ] **Step 2: Register the patch**

Append this line to the end of `patches.txt` (after `grocery.patches.v1_0.populate_policy_web_pages`):

```
grocery.patches.v1_0.backfill_app_banner_link_fields
```

- [ ] **Step 3: Run the patch and confirm it is idempotent**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost migrate`
Expected: migrate completes; the patch runs once with no error. Run `bench --site grocery.localhost migrate` a second time — the patch is recorded as already-applied and does not re-run (and even if forced, the "already set" skip makes it safe).

- [ ] **Step 4: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/patches/v1_0/backfill_app_banner_link_fields.py grocery/patches.txt
git commit -m "feat(app-banner): backfill typed link fields from link_value"
```

---

## Task 4: App — `BannerAction` resolver

**Files:**
- Create: `/home/frappe/Flutter/zad/lib/models/banner_action.dart`
- Test: `/home/frappe/Flutter/zad/test/models/banner_action_test.dart`

**Interfaces:**
- Consumes: `AppBannerModel` (`lib/models/app_banner.dart`) with `String? linkType`, `String? linkValue`.
- Produces:
  - `sealed class BannerAction`
  - `class BannerProduct extends BannerAction { final String itemCode; }`
  - `class BannerItemGroup extends BannerAction { final String groupId; }`
  - `class BannerUrl extends BannerAction { final String url; }`
  - `class BannerNone extends BannerAction {}`
  - `BannerAction resolveBannerAction(AppBannerModel banner)`
  — all consumed by Task 5.

- [ ] **Step 1: Write the failing tests**

Create `test/models/banner_action_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/models/app_banner.dart';
import 'package:zad/models/banner_action.dart';

AppBannerModel _banner(String? type, String? value) =>
    AppBannerModel(title: 'T', linkType: type, linkValue: value);

void main() {
  test('Item type resolves to BannerProduct with the item code', () {
    final action = resolveBannerAction(_banner('Item', 'ITEM-1'));
    expect(action, isA<BannerProduct>());
    expect((action as BannerProduct).itemCode, 'ITEM-1');
  });

  test('Item Group type resolves to BannerItemGroup with the group id', () {
    final action = resolveBannerAction(_banner('Item Group', 'Products'));
    expect(action, isA<BannerItemGroup>());
    expect((action as BannerItemGroup).groupId, 'Products');
  });

  test('URL type resolves to BannerUrl with the url', () {
    final action = resolveBannerAction(_banner('URL', 'https://zad.example'));
    expect(action, isA<BannerUrl>());
    expect((action as BannerUrl).url, 'https://zad.example');
  });

  test('None type resolves to BannerNone', () {
    expect(resolveBannerAction(_banner('None', 'ignored')), isA<BannerNone>());
  });

  test('null type resolves to BannerNone', () {
    expect(resolveBannerAction(_banner(null, 'ITEM-1')), isA<BannerNone>());
  });

  test('a typed banner with a blank value resolves to BannerNone', () {
    expect(resolveBannerAction(_banner('Item', '   ')), isA<BannerNone>());
    expect(resolveBannerAction(_banner('URL', null)), isA<BannerNone>());
  });

  test('value is trimmed before use', () {
    final action = resolveBannerAction(_banner('Item', '  ITEM-9 '));
    expect((action as BannerProduct).itemCode, 'ITEM-9');
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.flutter-sdk/bin/flutter test test/models/banner_action_test.dart`
Expected: FAIL — compile error, `banner_action.dart` / `resolveBannerAction` does not exist.

- [ ] **Step 3: Write the resolver**

Create `lib/models/banner_action.dart`:

```dart
import 'app_banner.dart';

/// A typed intent describing what tapping a home banner should do (PRD F2).
/// Produced by [resolveBannerAction] from a banner's `link_type`/`link_value`.
sealed class BannerAction {
  const BannerAction();
}

/// Open the product detail page for [itemCode] (`/product`).
class BannerProduct extends BannerAction {
  const BannerProduct(this.itemCode);
  final String itemCode;
}

/// Open the category browser focused on [groupId] (`/categories`).
class BannerItemGroup extends BannerAction {
  const BannerItemGroup(this.groupId);
  final String groupId;
}

/// Open [url] in the external browser.
class BannerUrl extends BannerAction {
  const BannerUrl(this.url);
  final String url;
}

/// The banner is not linked — render it, but do not make it tappable.
class BannerNone extends BannerAction {
  const BannerNone();
}

/// Maps a banner's `link_type`/`link_value` to the action a tap performs.
/// Unknown or `None` types, and any type whose value is blank, resolve to
/// [BannerNone].
BannerAction resolveBannerAction(AppBannerModel banner) {
  final value = banner.linkValue?.trim() ?? '';
  if (value.isEmpty) return const BannerNone();
  switch (banner.linkType) {
    case 'Item':
      return BannerProduct(value);
    case 'Item Group':
      return BannerItemGroup(value);
    case 'URL':
      return BannerUrl(value);
    default:
      return const BannerNone();
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/models/banner_action_test.dart`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add lib/models/banner_action.dart test/models/banner_action_test.dart
git commit -m "feat(banner): resolveBannerAction maps link_type to a typed action"
```

---

## Task 5: App — dispatch a tap in `_BannerCard`

**Files:**
- Modify: `/home/frappe/Flutter/zad/lib/features/home/widgets/promo_banner.dart`
- Test: `/home/frappe/Flutter/zad/test/features/promo_banner_test.dart`

**Interfaces:**
- Consumes: `resolveBannerAction` + the `BannerAction` subclasses (Task 4); `CategoryBrowserArgs` (`lib/features/category/category_browser_page.dart`); `UrlOpener` (`lib/core/services/url_opener.dart`) via `context.read`; `showZadSnack`/`ZadSnackVariant` (`lib/core/widgets/zad_snack.dart`); `AppLocalizations` (`lib/l10n/app_localizations.dart`).
- Produces: a tappable `_BannerCard` — routes `/product` (Item), `/categories` with `CategoryBrowserArgs` (Item Group), or opens the URL; `BannerNone` renders unchanged and is not tappable.

- [ ] **Step 1: Write the failing widget tests**

Add these imports to the top of `test/features/promo_banner_test.dart` (alongside the existing ones):

```dart
import 'package:provider/provider.dart';
import 'package:zad/core/services/url_opener.dart';
import 'package:zad/features/category/category_browser_page.dart';

import '../helpers.dart';
```

Then add these tests inside `main()` (after the existing two). The stub-route pattern captures `pushNamed` arguments by rendering them; `FakeUrlOpener` comes from `helpers.dart`.

```dart
  // A single banner with the given link, mounted with route stubs that echo
  // their pushed arguments as Text, plus a Provider<UrlOpener> for URL taps.
  Widget _linkedBannerApp(AppBannerModel banner, {UrlOpener? opener}) {
    Widget stub(String label) => Builder(
          builder: (context) {
            final args = ModalRoute.of(context)!.settings.arguments;
            final detail = args is CategoryBrowserArgs
                ? args.initialGroupId
                : args?.toString();
            return Scaffold(body: Text('$label:$detail'));
          },
        );
    return Provider<UrlOpener>.value(
      value: opener ?? FakeUrlOpener(),
      child: MaterialApp(
        home: Scaffold(body: PromoBanner(banners: [banner])),
        routes: {
          '/product': (_) => stub('product'),
          '/categories': (_) => stub('categories'),
        },
      ),
    );
  }

  testWidgets('tapping an Item banner routes to /product with the item code', (
    tester,
  ) async {
    await tester.pumpWidget(_linkedBannerApp(
      const AppBannerModel(title: 'B', linkType: 'Item', linkValue: 'ITEM-1'),
    ));
    await tester.pump();

    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(find.text('product:ITEM-1'), findsOneWidget);
  });

  testWidgets('tapping an Item Group banner routes to /categories with the id', (
    tester,
  ) async {
    await tester.pumpWidget(_linkedBannerApp(
      const AppBannerModel(
          title: 'B', linkType: 'Item Group', linkValue: 'Products'),
    ));
    await tester.pump();

    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(find.text('categories:Products'), findsOneWidget);
  });

  testWidgets('tapping a URL banner hands the url to UrlOpener', (tester) async {
    final opener = FakeUrlOpener();
    await tester.pumpWidget(_linkedBannerApp(
      const AppBannerModel(
          title: 'B', linkType: 'URL', linkValue: 'https://zad.example'),
      opener: opener,
    ));
    await tester.pump();

    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(opener.opened, ['https://zad.example']);
  });

  testWidgets('a URL that fails to open shows an error snackbar', (tester) async {
    final opener = FakeUrlOpener()..result = false;
    await tester.pumpWidget(_linkedBannerApp(
      const AppBannerModel(
          title: 'B', linkType: 'URL', linkValue: 'https://zad.example'),
      opener: opener,
    ));
    await tester.pump();

    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('an unlinked banner is not tappable (no GestureDetector added)', (
    tester,
  ) async {
    await tester.pumpWidget(_linkedBannerApp(
      const AppBannerModel(title: 'B', linkType: 'None', linkValue: null),
    ));
    await tester.pump();

    // No route stub content ever appears; nothing to assert beyond a clean tap.
    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(find.text('product:null'), findsNothing);
    expect(find.text('categories:null'), findsNothing);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.flutter-sdk/bin/flutter test test/features/promo_banner_test.dart`
Expected: FAIL — `_BannerCard` has no tap handler, so `find.text('product:ITEM-1')` etc. are not found (and the imports for `UrlOpener`/`CategoryBrowserArgs` are needed by the new helper).

- [ ] **Step 3: Add the dispatch to `_BannerCard`**

In `lib/features/home/widgets/promo_banner.dart`, add these imports below the existing import block (after `import '../../../models/app_banner.dart';`):

```dart
import 'package:provider/provider.dart';

import '../../../core/services/url_opener.dart';
import '../../../core/widgets/zad_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/banner_action.dart';
import '../../category/category_browser_page.dart';
```

Then replace the `_BannerCard.build` method (currently the `return ClipRRect(...)` block, lines 98–121) so the card is wrapped in a tap handler only when it resolves to a real action:

```dart
  @override
  Widget build(BuildContext context) {
    // Image-only banner: the artwork fills the whole card edge-to-edge
    // (BoxFit.cover), no overlaid headline or "Shop Now" CTA. The paleGreen
    // ground shows through only for the placeholder fallback (below) or the
    // brief moment before a network image paints.
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(ZadRadii.banner),
      child: Container(
        height: 160,
        width: double.infinity,
        color: ZadColors.paleGreen,
        child: RemoteImage(
          url: banner.imageUrl,
          fit: BoxFit.cover,
          placeholder: Image.asset(
            _bannerPlaceholderImagePath,
            fit: BoxFit.contain,
            alignment: AlignmentDirectional.bottomEnd,
          ),
        ),
      ),
    );

    // An unlinked banner (link_type None/blank or a blank value) renders
    // exactly as before — no tap target.
    final action = resolveBannerAction(banner);
    if (action is BannerNone) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _dispatch(context, action),
      child: card,
    );
  }

  /// Runs the banner's link: routes to the product/category page, or opens
  /// the external URL (mirroring `profile_tab.dart:_openUrl` for failures).
  Future<void> _dispatch(BuildContext context, BannerAction action) async {
    switch (action) {
      case BannerProduct(:final itemCode):
        Navigator.pushNamed(context, '/product', arguments: itemCode);
      case BannerItemGroup(:final groupId):
        Navigator.pushNamed(
          context,
          '/categories',
          arguments: CategoryBrowserArgs(initialGroupId: groupId),
        );
      case BannerUrl(:final url):
        final l10n = AppLocalizations.of(context);
        final ok = await context.read<UrlOpener>().open(url);
        if (!ok && context.mounted) {
          showZadSnack(
            context,
            l10n.sectionErrorMessage,
            variant: ZadSnackVariant.error,
          );
        }
      case BannerNone():
        break;
    }
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/features/promo_banner_test.dart`
Expected: PASS (the two existing carousel tests plus the five new tap tests).

- [ ] **Step 5: Analyze and run the full app test suite**

Run: `~/.flutter-sdk/bin/flutter analyze && ~/.flutter-sdk/bin/flutter test`
Expected: analyze clean; all tests pass (confirms the `_BannerCard` change did not regress `home_content_test.dart` or `home_async_test.dart`, which render `PromoBanner`).

- [ ] **Step 6: Commit**

```bash
cd /home/frappe/Flutter/zad
git add lib/features/home/widgets/promo_banner.dart test/features/promo_banner_test.dart
git commit -m "feat(banner): tap opens item / category / external url"
```

---

## Self-Review

**Spec coverage:**
- Backend Item/Item Group Link pickers + URL field → Task 1. ✓
- `link_value` derived, contract unchanged → Task 2. ✓
- Existing prod banners migrate → Task 3. ✓
- App: Item tap → item profile; Item Group tap → category browser; URL tap → clickable/open → Task 5. ✓
- Pure, testable mapping → Task 4. ✓
- Edge cases (blank value, None, URL open failure) → Tasks 4 & 5 tests. ✓
- Backend URL validation → Task 2. ✓
- Testing (backend validate, resolver units, widget navigation/URL) → Tasks 2, 4, 5. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code. The only `grocery.localhost` token is an intentional, environment-specific bench site name the executor substitutes (memory: dev site under `~/Frappe/grocery-bench`).

**Type consistency:** `resolveBannerAction` / `BannerAction` / `BannerProduct.itemCode` / `BannerItemGroup.groupId` / `BannerUrl.url` / `BannerNone` are defined identically in Task 4 and consumed with the same names/patterns in Task 5. `_LINK_FIELD_BY_TYPE` (py) and the JSON fieldnames `link_item`/`link_item_group`/`link_url`/`link_value` match across Tasks 1–3. `CategoryBrowserArgs(initialGroupId:)` and route names `/product`, `/categories` match the app's route table (`lib/app.dart`) and existing call sites.

**Task independence:** Backend (Tasks 1–3) and app (Tasks 4–5) are independent; within each, later tasks build on earlier deliverables. Each task ends green and committed.
