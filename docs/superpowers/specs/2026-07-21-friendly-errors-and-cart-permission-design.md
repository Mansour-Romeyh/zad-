# App-wide friendly errors + cart/checkout permission fix — Design

**Date:** 2026-07-21
**Status:** Approved (design), pending spec review
**Repos touched:** `zad` (Flutter app) and `grocery` app in `~/Frappe/grocery-bench`

## Problem

Adding any item to the basket shows the user a raw, translated Frappe framework
error:

> لا يملك المستخدم +9647703438790@app.local حق الوصول الى المستند عبر اذن دور المستند Account
> ("User … does not have access to the document via Document Role Permission: Account")

Two distinct defects sit behind this:

1. **Backend — add-to-cart (and checkout) genuinely fail on production.** The
   error is a Frappe `PermissionError` (HTTP 403), not just an ugly string. The
   customer literally cannot add to cart or check out.
2. **Frontend — the app leaks raw server/system error strings to users.** The
   API layer copies the raw Frappe message verbatim into the exception, and ~13
   screens display it directly (`SnackBar(Text(e.message))`, inline banners,
   error state text). Any backend or framework error surfaces untranslated and
   unfriendly.

The user wants **both** fixed: make the purchase flow work, and never show
system errors anywhere in the app.

## Root cause (backend) — confirmed on the dev bench

- `grocery.api.cart.add_item` creates a **draft `Quotation`** (the cart) and
  persists it via `_save_cart` → `cart.insert(ignore_permissions=True)` /
  `cart.save(ignore_permissions=True)`. All three cart mutations
  (`add_item`, `update_item`, `merge`) funnel through `_save_cart`.
- `grocery.api.order.place_order` (checkout) builds and **submits a
  `Sales Order`** the same way: `so.insert(ignore_permissions=True); so.submit()`.
- The **Grocery Customer role has no read permission on `Account`** — verified
  directly: `frappe.has_permission("Account", "read")` → `False`;
  `frappe.get_doc("Account", x).check_permission("read")` → raises the exact
  `PermissionError`.
- On **production**, ERPNext's Quotation/Sales Order validation reads an
  `Account` (a default **Sales Taxes & Charges** template's `account_head`,
  and/or the company receivable account) → the nested permission check fires
  against the customer → 403. On **dev there is no tax template**, so validation
  never touches an `Account` and the same call succeeds — which is exactly why
  the bug is production-only.
- **Proven non-fixes:** neither the document's own `ignore_permissions=True`
  flag nor a global `frappe.flags.ignore_permissions` suppresses the nested
  `Account` `check_permission`. Only the *user* matters — an elevated user
  (e.g. Administrator) short-circuits `has_permission` to `True`.

> Note: The exact triggering line is production-config-dependent (tax template
> present there, absent on dev). The fix below is **config-independent** — it
> works regardless of which accounting master ERPNext happens to read. If a
> production Error Log traceback becomes available, it will confirm the precise
> trigger, but is not required.

## Goals

- Add-to-cart, update-cart, merge-cart, and checkout succeed for the Grocery
  Customer role on production, without widening what customers can read via the
  API.
- No screen in the app ever displays a raw server/framework error string.
- Every user-facing error is a friendly, **app-owned, localized** message
  (English + Arabic), selected by error *type*.
- A single, testable choke point for error→message mapping, reused everywhere.

## Non-goals

- No backend "error code" contract (option B was declined). The app maps by
  exception type only.
- Cart **warnings** (soft-stock "Only N available…") are intentional,
  data-bearing, backend-localized messages — out of scope, left as-is.
- Checkout's existing bespoke dialogs for out-of-stock / outside-coverage /
  store-closed stay as they are (already friendly and do more than show text).
  Only their raw-`message` fallback is rerouted.
- No broad ERPNext permission model changes; no granting customers read on
  `Account` (rejected: exposes the chart of accounts via `/api/resource/Account`).

## Backend design (grocery app)

### Privileged-execution helper

Add one reusable helper in `grocery/api/utils.py`:

```python
import contextlib

@contextlib.contextmanager
def privileged_session():
    """Run a block as an elevated user so nested ERPNext permission checks pass.

    Customer-facing cart/checkout endpoints must create ERPNext sales documents
    (Quotation, Sales Order) on the authenticated customer's behalf. ERPNext
    validation reads accounting masters (e.g. tax Account heads) the Grocery
    Customer role cannot read, and neither the document's own
    ``ignore_permissions`` flag nor ``frappe.flags.ignore_permissions`` suppress
    that nested ``Account`` check. Elevating the session user for the duration
    of the persist is the robust, config-independent way to let these
    server-authoritative writes through. Authorization is already enforced at
    the endpoint boundary (``require_customer``); the client cannot influence
    price or party.
    """
    original = frappe.session.user
    frappe.set_user("Administrator")
    try:
        yield
    finally:
        frappe.set_user(original)
```

### Apply at the two write choke points

- **`cart._save_cart`** — wrap the `insert()` / `save()` in `privileged_session()`.
- **`order.place_order`'s Sales Order build/submit** — wrap the
  `so.insert()` / `so.submit()` in `privileged_session()`.

### Ownership preservation

`frappe.set_user("Administrator")` makes the new doc's `owner` = Administrator.
Before shipping, verify the customer-facing read guards do **not** rely on
`owner`:
- `cart.get_open_cart` filters by `party_name` (customer) — safe.
- `order._load_order` / order listing must filter by `customer`, not `owner`.

If any guard relies on `owner`, set `doc.owner = <customer user>` explicitly
before insert (Frappe keeps a pre-set owner on privileged insert). This will be
confirmed during implementation; default assumption is that guards are
customer-based (they already are for the cart).

### Backend testing

- New/updated pytest that reproduces the production condition on the test site:
  create a default Sales Taxes & Charges template with a tax `account_head`, act
  as a Grocery Customer user, and assert:
  - **Before fix:** `add_item` / `place_order` raise `PermissionError`.
  - **After fix:** both succeed and return correct totals/order.
- Ensure existing cart/order tests still pass (owner/party assertions).
- Roll back / isolate test data per the repo's existing test conventions.

## Frontend design (Flutter app)

### Central mapper

New file `lib/core/errors/user_error.dart`:

```dart
/// Pure map from any thrown error to a friendly, localized, app-owned message.
/// Raw server strings (ApiException.message) are NEVER returned.
String userErrorMessage(AppLocalizations l10n, Object error) { … }

/// Convenience for the common SnackBar case.
void showErrorSnackBar(BuildContext context, Object error) { … }
```

`userErrorMessage` switches on exception *type* (see table). `ApiException`
(the generic case) and any non-`ApiException` (`e.toString()` today) both fall
through to a generic message — so Dart errors and raw Frappe strings are both
suppressed.

### Error type → message mapping

| Exception type | Message (semantic key) |
|---|---|
| `ApiNetworkException` | `errorNetwork` — "No internet connection. Please check and try again." |
| `UnauthenticatedException` | `errorSessionExpired` — "Your session has expired. Please sign in again." |
| `ForbiddenException` | `errorGeneric` (never hint at internal permission detail) |
| `OutOfStockException` | `errorOutOfStock` — "Some items are no longer available." |
| `OutsideCoverageException` | `errorOutsideCoverage` — "This address is outside our delivery area." |
| `StoreClosedException` | `errorStoreClosed` — "Sorry, the store is currently closed." |
| `OtpCooldownException` | `errorOtpCooldown(seconds)` — "Please wait {seconds}s before requesting a new code." |
| `OtpExpiredException` | `errorOtpExpired` — "Your code has expired. Please request a new one." |
| generic `ApiException` / anything else | `errorGeneric` — "Something went wrong. Please try again." |

Introduce a dedicated `error*` key family for all messages in the table above.
Leave the existing `sectionErrorMessage` as-is for section-load empty/error
states (it keeps its current meaning and call sites). Add every new key to
**both** `app_en.arb` and `app_ar.arb` (+ regenerated `app_localizations*.dart`).

### Call sites to migrate (raw message → mapper)

Replace `e.message` / `e.toString()` display with `userErrorMessage(l10n, e)`
(or `showErrorSnackBar`):

- `features/home/widgets/product_card.dart` (add-to-cart SnackBar)
- `features/product/product_detail_page.dart`
- `features/basket/basket_page.dart`
- `features/checkout/checkout_page.dart` (only the trailing `ApiException`
  fallback; keep the typed dialogs)
- `features/addresses/address_list_page.dart`
- `features/addresses/address_form_page.dart`
- `features/profile/profile_tab.dart`
- `features/profile/change_password_page.dart`
- `features/auth/login_page.dart`
- `features/auth/register_page.dart`
- `features/auth/reset_password_page.dart`
- `features/auth/otp_page.dart`
- `features/auth/widgets/auth_error_banner.dart`

Any store that exposes an error object for the UI to render (e.g. `CartStore`)
keeps storing the exception; the UI maps it at display time.

### Frontend testing

- Unit tests for `userErrorMessage`: every exception type → its expected
  localized string, and a raw-message `ApiException("لا يملك المستخدم…")` →
  `errorGeneric` (proves no leak).
- Update existing widget tests that asserted on raw messages to assert on the
  new friendly strings.

## Files touched (summary)

**Backend (`~/Frappe/grocery-bench/apps/grocery`)**
- `grocery/api/utils.py` — add `privileged_session()`
- `grocery/api/cart.py` — wrap `_save_cart` persist
- `grocery/api/order.py` — wrap Sales Order insert/submit
- tests under `grocery/**/test_*` — reproduce + assert fix

**Frontend (`zad`)**
- `lib/core/errors/user_error.dart` — new mapper + snackbar helper
- `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` (+ generated localizations)
- ~13 call sites above
- `test/core/errors/user_error_test.dart` — new; plus updates to widget tests

## Risks / watch-outs

- **Owner change from elevation** — mitigate by confirming read guards are
  customer-based (they are for the cart); set `owner` explicitly if checkout
  order visibility depends on it.
- **Over-elevation** — the privileged block is scoped to only the persist call,
  not the whole endpoint; business validation and the endpoint-level role guard
  still run as the real user.
- **Missed call sites** — a grep for `e.message` / `\.toString()` in display
  code is part of implementation to catch any site not listed.
- **Localization drift** — every new key must exist in both `.arb` files;
  the build fails if the Arabic entry is missing, which is the safety net.
```
