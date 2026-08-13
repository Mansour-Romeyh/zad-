# Friendly Errors + Cart/Checkout Permission Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make add-to-cart and checkout succeed for the Grocery Customer role on production, and ensure the app never shows raw server/system error strings — every user-facing error is a friendly, localized, app-owned message.

**Architecture:** Backend — one reusable `privileged_session()` context manager elevates the session to `Administrator` around the two server-authoritative writes (cart Quotation persist, checkout Sales Order insert/submit), so ERPNext's nested `Account` permission check passes regardless of production's accounting config. Frontend — one central `userErrorMessage(l10n, error)` mapper (by exception type) plus a `showErrorSnackBar` helper, wired into every display site; raw `ApiException.message` is never rendered.

**Tech Stack:** Backend: Frappe/ERPNext (Python 3.14), `bench`, `IntegrationTestCase`. Frontend: Flutter/Dart, `flutter_localizations` (ARB → generated `AppLocalizations`), `flutter test`.

## Global Constraints

- **Two repos.** Backend changes live in `~/Frappe/grocery-bench/apps/grocery`; frontend in `/home/frappe/Flutter/zad`. They are separate git repos — commit each independently.
- **Flutter SDK is not on PATH.** Use `~/.flutter-sdk/bin/flutter` for every flutter command.
- **Backend test/dev site:** `grocery.localhost` (bench at `~/Frappe/grocery-bench`). Running tests pollutes this dev site (setUpClass records may persist) — acceptable here; do not point at production.
- **Elevation identity is `Administrator`** (approved). Order/cart visibility is customer-based (`so.customer`, `party_name`), not `owner`, so elevation has no visibility side-effect — no owner-preservation code.
- **Localization:** every new l10n key MUST be added to BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_ar.arb`, then regenerated. `nullable-getter: false`, template is `app_en.arb`.
- **Do NOT commit until the user asks** is overridden for THIS plan: the user approved implementing it; commit each task per its Commit step. Backend commits use the grocery repo; frontend commits use the zad repo. End commit messages with the `Co-Authored-By` trailer.
- **Production caveat:** the exact `Account`-read trigger is production-config-specific and cannot be reproduced on `grocery.localhost` (dev has no tax template; a customer can insert a tax-bearing Quotation there with no permission error). The backend tests therefore verify the *elevation mechanism* deterministically; final end-to-end confirmation is a manual production step (Task 4).

---

## Phase 1 — Backend (grocery app)

### Task 1: `privileged_session()` helper + tests

**Files:**
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/api/utils.py`
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_utils.py` (create)

**Interfaces:**
- Produces: `grocery.api.utils.privileged_session()` — a `contextlib.contextmanager` taking no args; sets `frappe.session.user = "Administrator"` for the block and restores the original user in a `finally` (even on exception).

- [ ] **Step 1: Write the failing tests**

Create `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_utils.py`:

```python
# Copyright (c) 2026, Zad Grocery and contributors
# For license information, please see license.txt

"""Shared endpoint helpers — grocery.api.utils. Covers privileged_session(),
the elevation used so customer-facing cart/checkout writes pass ERPNext's
nested Account permission check (see the 2026-07-21 friendly-errors design)."""

import frappe
from frappe.tests import IntegrationTestCase

from grocery.api import cart
from grocery.api.utils import privileged_session
from grocery.tests import order_fixtures as fx


class IntegrationTestPrivilegedSession(IntegrationTestCase):
    def setUp(self):
        super().setUp()
        self.addCleanup(lambda: frappe.set_user("Administrator"))
        self.user, self.customer = fx.make_customer_user("Task Utils User")
        # An Account the Grocery Customer role cannot read (db.get_value
        # bypasses permissions so we can resolve the name as the customer).
        self.account = frappe.db.get_value(
            "Account", {"is_group": 0, "company": cart._company()}, "name"
        )
        frappe.set_user(self.user)

    def test_customer_cannot_read_account_but_can_inside_block(self):
        # Baseline: the customer is denied Account read (the production trigger).
        with self.assertRaises(frappe.PermissionError):
            frappe.get_doc("Account", self.account).check_permission("read")
        # Inside the elevated block the same check passes.
        with privileged_session():
            frappe.get_doc("Account", self.account).check_permission("read")
        # Session user is restored afterwards.
        self.assertEqual(frappe.session.user, self.user)

    def test_restores_user_even_when_block_raises(self):
        with self.assertRaises(ValueError):
            with privileged_session():
                self.assertEqual(frappe.session.user, "Administrator")
                raise ValueError("boom")
        self.assertEqual(frappe.session.user, self.user)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_utils`
Expected: FAIL — `ImportError: cannot import name 'privileged_session' from 'grocery.api.utils'`.

- [ ] **Step 3: Implement the helper**

In `~/Frappe/grocery-bench/apps/grocery/grocery/api/utils.py`, add `import contextlib` at the top of the import block (after the module docstring, alongside `import frappe`), then append this function to the end of the file:

```python
@contextlib.contextmanager
def privileged_session():
	"""Run a block as ``Administrator`` so nested permission checks pass.

	Customer-facing cart/checkout endpoints create ERPNext sales documents
	(Quotation, Sales Order) on the authenticated customer's behalf. ERPNext
	validation reads accounting masters (e.g. tax ``Account`` heads) the
	Grocery Customer role cannot read, and neither the document's own
	``ignore_permissions`` flag nor ``frappe.flags.ignore_permissions``
	suppress that nested ``Account`` check — only an elevated *user* does.
	Authorization is already enforced at the endpoint boundary
	(``require_role``/``require_customer``); the client cannot influence price
	or party, so elevating just the persist is safe. Order/cart visibility is
	customer-based, so the resulting ``owner`` = Administrator is harmless.
	"""
	original = frappe.session.user
	frappe.set_user("Administrator")
	try:
		yield
	finally:
		frappe.set_user(original)
```

> Note: the file is tab-indented (Frappe convention) — match it exactly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_utils`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/api/utils.py grocery/tests/test_utils.py
git commit -m "feat(api): privileged_session() elevation helper for customer-side sales writes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Elevate the cart Quotation persist

**Files:**
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/api/cart.py` (import line ~24; `_save_cart` at lines 188-199)
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_cart.py` (existing — regression only)

**Interfaces:**
- Consumes: `grocery.api.utils.privileged_session` (Task 1).

- [ ] **Step 1: Add the import**

In `~/Frappe/grocery-bench/apps/grocery/grocery/api/cart.py`, change the existing import (line ~24):

```python
from grocery.api.utils import customer_for_user, require_role
```
to:
```python
from grocery.api.utils import customer_for_user, privileged_session, require_role
```

- [ ] **Step 2: Wrap the persist in `_save_cart`**

Replace the tail of `_save_cart` (lines ~195-199):

```python
	if cart.is_new():
		cart.insert(ignore_permissions=True)
	else:
		cart.save(ignore_permissions=True)
	return cart
```
with:
```python
	with privileged_session():
		if cart.is_new():
			cart.insert(ignore_permissions=True)
		else:
			cart.save(ignore_permissions=True)
	return cart
```

- [ ] **Step 3: Run the cart test suite (regression)**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_cart`
Expected: PASS (all existing cart tests — add_item/update_item/merge still work; no owner/party assertions break).

- [ ] **Step 4: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/api/cart.py
git commit -m "fix(cart): elevate cart Quotation persist so Account perm check passes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Elevate the checkout Sales Order insert/submit

**Files:**
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/api/order.py` (add import after line 34; `_build_sales_order` at lines 289-291)
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_order.py` + `test_checkout_concurrency.py` (existing — regression only)

**Interfaces:**
- Consumes: `grocery.api.utils.privileged_session` (Task 1).

- [ ] **Step 1: Add the import**

In `~/Frappe/grocery-bench/apps/grocery/grocery/api/order.py`, immediately after line 34 (`from grocery.api import catalog`), add:

```python
from grocery.api.utils import privileged_session
```

- [ ] **Step 2: Wrap the Sales Order insert/submit**

Replace lines 289-291 in `_build_sales_order`:

```python
	so.insert(ignore_permissions=True)
	so.submit()
	return so
```
with:
```python
	with privileged_session():
		so.insert(ignore_permissions=True)
		so.submit()
	return so
```

- [ ] **Step 3: Run the order/checkout test suites (regression)**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_order`
Then: `bench --site grocery.localhost run-tests --module grocery.tests.test_checkout_concurrency`
Expected: PASS for both. In particular the idempotency/duplicate-key replay path (`UniqueValidationError`/`DuplicateEntryError` caught in `place_order`) still behaves — the elevation is scoped strictly to insert+submit and does not swallow those errors.

- [ ] **Step 4: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/api/order.py
git commit -m "fix(checkout): elevate Sales Order insert/submit so Account perm check passes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Manual production verification (checklist, no code)

**Files:** none.

This confirms the fix resolves the real production error, which is not reproducible on the dev site.

- [ ] **Step 1: Deploy** the three backend commits to production (`zad.micronext.net`) via the normal deploy path.
- [ ] **Step 2: Add to cart** as a real customer in the app. Expected: item is added, no permission error.
- [ ] **Step 3: Checkout** that cart. Expected: order places successfully.
- [ ] **Step 4: If either still 403s**, capture the production traceback (Frappe Desk → Error Log, newest entry) and paste it — it will name the exact triggering line so the elevation scope can be adjusted. (Not expected: elevation to Administrator bypasses any session-user permission check inside insert/submit.)

---

## Phase 2 — Frontend (zad app)

### Task 5: Add localized `error*` strings

**Files:**
- Modify: `/home/frappe/Flutter/zad/lib/l10n/app_en.arb`
- Modify: `/home/frappe/Flutter/zad/lib/l10n/app_ar.arb`
- Generated (do not hand-edit): `lib/l10n/app_localizations*.dart`

**Interfaces:**
- Produces (on `AppLocalizations`): `errorGeneric`, `errorNetwork`, `errorSessionExpired`, `errorOutOfStock`, `errorOutsideCoverage`, `errorStoreClosed`, `errorOtpExpired` (all `String`), and `errorOtpCooldown(int seconds) → String`.

- [ ] **Step 1: Add keys to `app_en.arb`**

Add these entries (place them together, e.g. after the existing `sectionErrorMessage` entry — JSON key order is not significant, but keep the file valid: comma-separate correctly):

```json
  "errorGeneric": "Something went wrong. Please try again.",
  "errorNetwork": "No internet connection. Please check and try again.",
  "errorSessionExpired": "Your session has expired. Please sign in again.",
  "errorOutOfStock": "Some items are no longer available.",
  "errorOutsideCoverage": "This address is outside our delivery area.",
  "errorStoreClosed": "Sorry, the store is currently closed.",
  "errorOtpExpired": "Your code has expired. Please request a new one.",
  "errorOtpCooldown": "Please wait {seconds}s before requesting a new code.",
  "@errorOtpCooldown": {
    "placeholders": {
      "seconds": {
        "type": "int"
      }
    }
  },
```

- [ ] **Step 2: Add the same keys to `app_ar.arb`**

```json
  "errorGeneric": "حدث خطأ ما. يرجى المحاولة مرة أخرى.",
  "errorNetwork": "لا يوجد اتصال بالإنترنت. تحقق من اتصالك وحاول مجدداً.",
  "errorSessionExpired": "انتهت صلاحية جلستك. يرجى تسجيل الدخول مرة أخرى.",
  "errorOutOfStock": "بعض المنتجات لم تعد متوفرة.",
  "errorOutsideCoverage": "هذا العنوان خارج نطاق التوصيل.",
  "errorStoreClosed": "عذراً، المتجر مغلق حالياً.",
  "errorOtpExpired": "انتهت صلاحية الرمز. يرجى طلب رمز جديد.",
  "errorOtpCooldown": "يرجى الانتظار {seconds} ث قبل طلب رمز جديد.",
  "@errorOtpCooldown": {
    "placeholders": {
      "seconds": {
        "type": "int"
      }
    }
  },
```

(The Arabic copy is a solid default; the user may refine wording later.)

- [ ] **Step 3: Regenerate localizations**

Run: `cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter gen-l10n`
Expected: no errors; `lib/l10n/app_localizations.dart`, `_en.dart`, `_ar.dart` now declare the new getters/method.

- [ ] **Step 4: Verify generation**

Run: `grep -n "errorOtpCooldown\|errorGeneric" lib/l10n/app_localizations_en.dart`
Expected: shows `String errorGeneric` and `String errorOtpCooldown(int seconds)`.

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add lib/l10n/
git commit -m "feat(l10n): add friendly error* strings (en + ar)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Central error mapper + unit tests

**Files:**
- Create: `/home/frappe/Flutter/zad/lib/core/errors/user_error.dart`
- Test: `/home/frappe/Flutter/zad/test/core/errors/user_error_test.dart` (create)

**Interfaces:**
- Consumes: `AppLocalizations` (Task 5); the exception types in `lib/core/api/api_exceptions.dart` (`ApiException`, `ApiNetworkException`, `UnauthenticatedException`, `ForbiddenException`, `OutOfStockException`, `OutsideCoverageException`, `StoreClosedException`, `OtpCooldownException` (field `cooldownSec`), `OtpExpiredException`).
- Produces: `String userErrorMessage(AppLocalizations l10n, Object error)` and `void showErrorSnackBar(BuildContext context, Object error)`.

- [ ] **Step 1: Write the failing tests**

Create `/home/frappe/Flutter/zad/test/core/errors/user_error_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/errors/user_error.dart';
import 'package:zad/l10n/app_localizations.dart';

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('network error maps to friendly network message', () {
    expect(userErrorMessage(en, const ApiNetworkException()), en.errorNetwork);
  });

  test('unauthenticated maps to session-expired message', () {
    expect(userErrorMessage(en, const UnauthenticatedException('x')),
        en.errorSessionExpired);
  });

  test('out of stock maps to friendly out-of-stock message', () {
    expect(userErrorMessage(en, const OutOfStockException('x', [])),
        en.errorOutOfStock);
  });

  test('outside coverage maps to coverage message', () {
    expect(userErrorMessage(en, const OutsideCoverageException('x')),
        en.errorOutsideCoverage);
  });

  test('store closed maps to store-closed message', () {
    expect(userErrorMessage(en, const StoreClosedException('x')),
        en.errorStoreClosed);
  });

  test('otp cooldown maps to cooldown message with seconds', () {
    expect(userErrorMessage(en, const OtpCooldownException('x', 30)),
        en.errorOtpCooldown(30));
  });

  test('otp expired maps to expired message', () {
    expect(userErrorMessage(en, const OtpExpiredException('x')),
        en.errorOtpExpired);
  });

  test('forbidden maps to generic (never reveals permission internals)', () {
    final e = const ForbiddenException(
        'لا يملك المستخدم +964...@app.local حق الوصول الى المستند عبر اذن دور المستند Account');
    expect(userErrorMessage(en, e), en.errorGeneric);
    expect(userErrorMessage(en, e), isNot(contains('Account')));
  });

  test('generic ApiException never leaks the raw server string', () {
    expect(userErrorMessage(en, const ApiException('raw server traceback')),
        en.errorGeneric);
  });

  test('non-ApiException (Dart error) maps to generic', () {
    expect(userErrorMessage(en, StateError('boom')), en.errorGeneric);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/core/errors/user_error_test.dart`
Expected: FAIL — `user_error.dart` does not exist / `userErrorMessage` undefined.

- [ ] **Step 3: Implement the mapper**

Create `/home/frappe/Flutter/zad/lib/core/errors/user_error.dart`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_exceptions.dart';

/// Maps any thrown [error] to a friendly, localized, app-owned message.
///
/// Selection is by exception *type*. Raw server strings
/// ([ApiException.message]) are NEVER returned: `ForbiddenException`, the
/// generic `ApiException`, and any non-`ApiException` (Dart errors,
/// `e.toString()`) all fall through to [AppLocalizations.errorGeneric], so no
/// backend or framework internals ever reach the user. The specific subtypes
/// are checked before the generic fall-through because they all extend
/// `ApiException`. See
/// docs/superpowers/specs/2026-07-21-friendly-errors-and-cart-permission-design.md.
String userErrorMessage(AppLocalizations l10n, Object error) {
  if (error is ApiNetworkException) return l10n.errorNetwork;
  if (error is UnauthenticatedException) return l10n.errorSessionExpired;
  if (error is OutOfStockException) return l10n.errorOutOfStock;
  if (error is OutsideCoverageException) return l10n.errorOutsideCoverage;
  if (error is StoreClosedException) return l10n.errorStoreClosed;
  if (error is OtpCooldownException) {
    return l10n.errorOtpCooldown(error.cooldownSec);
  }
  if (error is OtpExpiredException) return l10n.errorOtpExpired;
  return l10n.errorGeneric;
}

/// Shows [error] as a friendly SnackBar. Callers must guard `context.mounted`.
void showErrorSnackBar(BuildContext context, Object error) {
  final l10n = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(userErrorMessage(l10n, error))),
  );
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/core/errors/user_error_test.dart`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add lib/core/errors/user_error.dart test/core/errors/user_error_test.dart
git commit -m "feat(errors): central userErrorMessage mapper + showErrorSnackBar

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Migrate SnackBar / feature display sites

**Files (all under `/home/frappe/Flutter/zad`):**
- Modify: `lib/features/home/widgets/product_card.dart` (~52-56)
- Modify: `lib/features/product/product_detail_page.dart` (~121-123)
- Modify: `lib/features/basket/basket_page.dart` (~43-47)
- Modify: `lib/features/addresses/address_list_page.dart` (~48-52)
- Modify: `lib/features/addresses/address_form_page.dart` (~154-156)
- Modify: `lib/features/checkout/checkout_page.dart` (~141-147)
- Modify: `lib/features/profile/profile_tab.dart` (~286-289)

**Interfaces:**
- Consumes: `userErrorMessage` / `showErrorSnackBar` (Task 6).

For each file, add the import `import '../../core/errors/user_error.dart';` (adjust the relative depth: from `lib/features/<area>/…` it is `../../core/errors/user_error.dart`; from `lib/features/<area>/widgets/…` it is `../../../core/errors/user_error.dart`).

- [ ] **Step 1: `product_card.dart`** — replace the raw SnackBar in the `on ApiException catch (e)` block:

```dart
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
```
with:
```dart
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, e);
    }
```
Import path here: `../../../core/errors/user_error.dart`.

- [ ] **Step 2: `product_detail_page.dart`** — replace:
```dart
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
```
with:
```dart
      showErrorSnackBar(context, e);
```

- [ ] **Step 3: `basket_page.dart`** — in the `_runMutation` catch, replace:
```dart
        ).showSnackBar(SnackBar(content: Text(e.message)));
```
(the full `ScaffoldMessenger.of(context)...` statement) with:
```dart
        showErrorSnackBar(context, e);
```
Keep the surrounding `if (!mounted) return;` guard.

- [ ] **Step 4: `address_list_page.dart`** — same `_runMutation` pattern; replace the `ScaffoldMessenger...Text(e.message)` statement with `showErrorSnackBar(context, e);`.

- [ ] **Step 5: `address_form_page.dart`** — replace `_showMessage(e.message)` (the `on ApiException catch (e)` branch, ~line 156) with:
```dart
      _showMessage(userErrorMessage(AppLocalizations.of(context), e));
```
Leave the `LocationException` branch (`_showMessage(message)`) unchanged. Ensure `import '../../l10n/app_localizations.dart';` is present (it is used elsewhere in the file).

- [ ] **Step 6: `checkout_page.dart`** — in the trailing `on ApiException catch (e)` fallback (keep the typed `OutOfStock`/`OutsideCoverage`/`StoreClosed` branches above it untouched), replace:
```dart
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e is ApiNetworkException ? l10n.sectionErrorMessage : e.message)));
```
with:
```dart
      showErrorSnackBar(context, e);
```

- [ ] **Step 7: `profile_tab.dart`** — replace the SnackBar content expression:
```dart
          content: Text(e is ApiException ? e.message : l10n.sectionErrorMessage),
```
with:
```dart
          content: Text(userErrorMessage(l10n, e)),
```

- [ ] **Step 8: Analyze + run affected widget tests**

Run: `cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter analyze lib/features`
Expected: no new errors (unused-import warnings mean a path needs fixing).

Run the widget tests that exercise these screens:
`~/.flutter-sdk/bin/flutter test test/features/best_deal_test.dart test/features/favourites/favourites_tab_test.dart test/features/home_async_test.dart`
Expected: PASS. If any test asserted a raw error message (e.g. expected literal `'Out of Stock'` server text), update the expectation to the new localized string (`errorOutOfStock`, `errorGeneric`, etc.).

- [ ] **Step 9: Commit**

```bash
cd /home/frappe/Flutter/zad
git add lib/features test/features
git commit -m "refactor(errors): route feature-screen errors through userErrorMessage

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Migrate auth inline-error pages

**Files (all under `/home/frappe/Flutter/zad`):**
- Modify: `lib/features/auth/login_page.dart` (~57-60)
- Modify: `lib/features/auth/register_page.dart` (~71-74)
- Modify: `lib/features/profile/change_password_page.dart` (~71-74)
- Modify: `lib/features/auth/reset_password_page.dart` (~53)
- Modify: `lib/features/auth/otp_page.dart` (~48)
- Optional doc-only: `lib/features/auth/widgets/auth_error_banner.dart` (comment mentions `ApiException.message` — no code change; the banner still takes a `String`).

**Interfaces:**
- Consumes: `userErrorMessage` (Task 6). These pages compute a message string (`_errorMessage` / `_messageFor`) that feeds `AuthErrorBanner`.

Add `import '../../core/errors/user_error.dart';` to each file (from `lib/features/auth/…` that is `../../core/errors/user_error.dart`). `AppLocalizations.of(context)` is available in these `State` classes via `context`.

- [ ] **Step 1: `login_page.dart`** — replace:
```dart
        _errorMessage = e is ApiException ? e.message : e.toString();
```
with:
```dart
        _errorMessage = userErrorMessage(AppLocalizations.of(context), e);
```

- [ ] **Step 2: `register_page.dart`** — replace the identical `_errorMessage = e is ApiException ? e.message : e.toString();` line with the same `userErrorMessage(AppLocalizations.of(context), e)` assignment.

- [ ] **Step 3: `change_password_page.dart`** — replace the identical `_errorMessage = e is ApiException ? e.message : e.toString();` line with the same `userErrorMessage(AppLocalizations.of(context), e)` assignment.

- [ ] **Step 4: `reset_password_page.dart`** — replace the helper:
```dart
  String _messageFor(Object e) => e is ApiException ? e.message : e.toString();
```
with:
```dart
  String _messageFor(Object e) => userErrorMessage(AppLocalizations.of(context), e);
```

- [ ] **Step 5: `otp_page.dart`** — replace the identical `_messageFor` helper with the same `userErrorMessage(AppLocalizations.of(context), e)` body.

- [ ] **Step 6: Analyze + run auth tests**

Run: `cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter analyze lib/features/auth lib/features/profile`
Expected: no new errors.

Run: `~/.flutter-sdk/bin/flutter test test/features/auth/login_page_test.dart test/features/auth/register_page_test.dart`
Expected: PASS. Any test that pumped an `ApiException('some message')` and asserted that literal text appears must now assert the mapped localized string (load `AppLocalizations` in the test, or match on the known English value e.g. `errorSessionExpired`/`errorGeneric`).

- [ ] **Step 7: Commit**

```bash
cd /home/frappe/Flutter/zad
git add lib/features/auth lib/features/profile test/features/auth
git commit -m "refactor(errors): route auth inline errors through userErrorMessage

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: Sweep for stragglers + full test run

**Files:** any remaining display site surfaced by the grep.

- [ ] **Step 1: Grep for any remaining raw-message display**

Run:
```bash
cd /home/frappe/Flutter/zad
grep -rn "Text(e.message)\|Text(e\.toString\|e.message : e.toString\|? e.message" lib --include=*.dart
```
Expected: no matches. If any remain (e.g. a store surfacing `.error` raw, or a site missed above), route it through `userErrorMessage`/`showErrorSnackBar` the same way and note it in the commit.

- [ ] **Step 2: Full analyze + full test suite**

Run: `cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter analyze`
Expected: clean (or only pre-existing, unrelated warnings).

Run: `~/.flutter-sdk/bin/flutter test`
Expected: PASS. Fix any remaining assertions on old raw messages.

- [ ] **Step 3: Commit any straggler fixes**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "chore(errors): sweep remaining raw error displays through the mapper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review (completed by plan author)

**Spec coverage:**
- Backend `privileged_session()` helper → Task 1. ✅
- Apply at cart `_save_cart` → Task 2. ✅
- Apply at checkout Sales Order insert/submit → Task 3. ✅
- Backend testing (mechanism + regression) → Tasks 1-3; production e2e → Task 4. ✅
- Ownership preservation risk → resolved in Global Constraints (customer-based visibility confirmed; no code needed). ✅
- Central mapper + snackbar helper → Task 6. ✅
- Error type → message table (all 8 types) → Task 5 keys + Task 6 mapper. ✅
- l10n keys en + ar + regen → Task 5. ✅
- All ~13 call sites migrated → Tasks 7 (7 sites) + 8 (5 sites + banner note) + 9 (sweep). ✅
- Frontend tests (mapper unit + widget updates) → Task 6 + Tasks 7-9. ✅
- Non-goals respected: no backend error-code contract; checkout typed dialogs preserved (Task 7 Step 6 keeps them); cart warnings untouched. ✅

**Placeholder scan:** No TBD/TODO; every code step shows full code; every command has an expected result. ✅

**Type consistency:** `userErrorMessage(AppLocalizations, Object) → String` and `showErrorSnackBar(BuildContext, Object) → void` used identically across Tasks 6-9. `OtpCooldownException.cooldownSec` matches `api_exceptions.dart`. `errorOtpCooldown(int seconds)` matches the ARB placeholder. `privileged_session()` signature identical across Tasks 1-3. ✅
```
