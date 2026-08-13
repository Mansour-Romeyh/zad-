# Delivery Fees Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a configurable global delivery fee (flat, waived above a subtotal threshold) that is charged on the Sales Order at checkout and shown in the app's checkout and order-detail summaries.

**Architecture:** The fee is two `App Settings` fields surfaced to the app via `content.get_app_config`. One rule — `fee = 0 if fee<=0; 0 if threshold>0 and net_total>=threshold; else fee` — is implemented once in Python (`grocery/services/delivery.py`, authoritative at `place_order`, which appends an ERPNext "Actual" Sales Taxes and Charges line so `grand_total = net_total + fee`) and once in Dart (`AppConfig.deliveryFeeFor`, advisory display). The app shows a Delivery line only when a positive fee is configured, so a fee of 0 behaves exactly as today.

**Tech Stack:** Frappe/ERPNext v16 (Python) for the `grocery` app; Flutter/Dart for the `zad` app; `flutter_gen_l10n` for localization.

## Global Constraints

- **Currency:** IQD (Iraq market). Amounts are integer IQD; use `flt(...)` in Python and `double` in Dart.
- **Fee rule (verbatim, both languages):** `if delivery_fee <= 0 → 0`; `if free_delivery_over > 0 and net_total >= free_delivery_over → 0`; `else → delivery_fee`. `net_total` is the item subtotal (cart/SO `net_total`, before charges). `>=` is the free boundary.
- **Show the Delivery line only when `delivery_fee > 0` is configured.** An unset/0 fee ⇒ no line, Total == Subtotal (identical to current behaviour — safe rollout).
- **Server authoritative, app advisory** — the app's computed fee/total is for display; `place_order` recomputes and is the source of truth (same split as store working-hours).
- **Backend site:** `grocery.localhost` in the bench at `~/Frappe/grocery-bench`.
- **Flutter SDK:** not on PATH — invoke as `~/.flutter-sdk/bin/flutter`.
- **Charge account:** the SO taxes line's `account_head` is the App Settings `delivery_charge_account`, else the SO company's `Freight and Forwarding Charges - {abbr}` (present by default; confirmed `Freight and Forwarding Charges - ZG` for company Zad Grocery).

---

## File structure

**Backend (`~/Frappe/grocery-bench/apps/grocery`):**
- Create `grocery/services/delivery.py` — the fee rule + charge-account resolution (single source of truth).
- Create `grocery/tests/test_delivery.py` — unit tests for the above.
- Modify `grocery/grocery/doctype/app_settings/app_settings.json` — 3 new fields + a Delivery section break.
- Modify `grocery/grocery/doctype/app_settings/app_settings.py` — `validate()`.
- Modify `grocery/grocery/doctype/app_settings/test_app_settings.py` — validation tests.
- Modify `grocery/api/content.py` — expose `delivery_fee`, `free_delivery_over`.
- Modify `grocery/tests/test_content.py` — config-shape + echo tests.
- Modify `grocery/api/order.py` — append the charge in `_build_sales_order`; add `delivery_fee` to `detail` totals.
- Modify `grocery/tests/test_order.py` — charge + detail tests.

**App (`~/Flutter/zad`):**
- Modify `lib/models/app_config.dart` — `deliveryFee`, `freeDeliveryOver`, `deliveryFeeFor`, `hasDeliveryFee`.
- Modify `test/models/app_config_test.dart` — parse/round-trip/rule tests.
- Modify `lib/data/cart_repository.dart` — `CartTotals.deliveryFee`.
- Modify `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb` — `checkoutDelivery`, `checkoutDeliveryFree`.
- Modify `lib/features/checkout/checkout_page.dart` — Delivery row + Total in `_SummaryCard`.
- Modify `test/features/checkout/checkout_page_test.dart` — Delivery-line widget tests.
- Modify `lib/features/orders/order_detail_page.dart` — Delivery row.
- Modify `test/features/orders/order_detail_page_test.dart` — Delivery-line widget test.

---

## Task 1: Delivery fee rule + charge-account resolution (`grocery/services/delivery.py`)

**Files:**
- Create: `~/Frappe/grocery-bench/apps/grocery/grocery/services/delivery.py`
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_delivery.py`

**Interfaces:**
- Produces: `delivery_fee_for(net_total, settings=None) -> float` and `resolve_charge_account(company: str, configured: str | None = None) -> str | None`. `delivery_fee_for` reads `delivery_fee`/`free_delivery_over` from `settings` when given, else from `App Settings` via `frappe.db.get_single_value` (transaction-visible). `resolve_charge_account` returns `configured` if it's an existing Account, else `Freight and Forwarding Charges - {abbr}` for `company` if it exists, else `None`.

- [ ] **Step 1: Write the failing tests**

Create `grocery/tests/test_delivery.py`:

```python
# Copyright (c) 2026, Zad Grocery and contributors
# For license information, please see license.txt

"""Unit tests for the delivery-fee rule + charge-account resolution
(``grocery/services/delivery.py``). See ``test_warehouse_zone.py`` for why
these live flat under ``grocery/tests/``."""

import frappe
from frappe.tests import IntegrationTestCase

from grocery.services import delivery


class IntegrationTestDeliveryService(IntegrationTestCase):
	def _settings(self, fee, over):
		s = frappe.get_single("App Settings")
		s.delivery_fee = fee
		s.free_delivery_over = over
		return s

	def _company(self):
		warehouse = frappe.db.get_single_value("App Settings", "default_warehouse")
		return frappe.db.get_value("Warehouse", warehouse, "company")

	def test_fee_charged_below_threshold(self):
		s = self._settings(2000, 25000)
		self.assertEqual(delivery.delivery_fee_for(18000, settings=s), 2000)

	def test_free_at_or_above_threshold(self):
		s = self._settings(2000, 25000)
		self.assertEqual(delivery.delivery_fee_for(25000, settings=s), 0)
		self.assertEqual(delivery.delivery_fee_for(30000, settings=s), 0)

	def test_threshold_zero_always_charges(self):
		s = self._settings(2000, 0)
		self.assertEqual(delivery.delivery_fee_for(9_999_999, settings=s), 2000)

	def test_fee_zero_always_free(self):
		s = self._settings(0, 25000)
		self.assertEqual(delivery.delivery_fee_for(1000, settings=s), 0)

	def test_resolve_prefers_existing_configured_account(self):
		company = self._company()
		abbr = frappe.db.get_value("Company", company, "abbr")
		freight = f"Freight and Forwarding Charges - {abbr}"
		self.assertEqual(delivery.resolve_charge_account(company, configured=freight), freight)

	def test_resolve_falls_back_to_freight_when_configured_missing(self):
		company = self._company()
		abbr = frappe.db.get_value("Company", company, "abbr")
		freight = f"Freight and Forwarding Charges - {abbr}"
		self.assertEqual(
			delivery.resolve_charge_account(company, configured="No Such Account - ZZ"),
			freight,
		)

	def test_resolve_returns_none_for_unknown_company(self):
		self.assertIsNone(delivery.resolve_charge_account("Nonexistent Company XYZ"))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_delivery`
Expected: FAIL — `ModuleNotFoundError: No module named 'grocery.services.delivery'`.

- [ ] **Step 3: Write the implementation**

Create `grocery/services/delivery.py`:

```python
# Copyright (c) 2026, Zad Grocery and contributors
# For license information, please see license.txt

"""Delivery-fee rule + charge-account resolution — the single source of
truth shared by ``App Settings`` validation and ``order.place_order``.

The fee is a flat amount (``App Settings.delivery_fee``) waived once the item
subtotal reaches ``App Settings.free_delivery_over`` ("free over N"). The app
mirrors this rule in ``AppConfig.deliveryFeeFor`` for display; this module is
authoritative at checkout.
"""

import frappe
from frappe.utils import flt


def delivery_fee_for(net_total, settings=None) -> float:
	"""The delivery fee for a basket whose item subtotal is ``net_total``.

	``settings`` is an ``App Settings`` doc when the caller already holds one
	(e.g. ``validate`` on the in-flight doc); otherwise the values are read
	fresh from the DB (transaction-visible, so a same-request write is seen).
	Rule: fee<=0 → 0; threshold>0 and net_total>=threshold → 0; else fee.
	"""
	if settings is not None:
		fee = flt(settings.delivery_fee)
		threshold = flt(settings.free_delivery_over)
	else:
		fee = flt(frappe.db.get_single_value("App Settings", "delivery_fee"))
		threshold = flt(frappe.db.get_single_value("App Settings", "free_delivery_over"))

	if fee <= 0:
		return 0.0
	if threshold > 0 and flt(net_total) >= threshold:
		return 0.0
	return fee


def resolve_charge_account(company: str, configured: str | None = None) -> str | None:
	"""The Account head for the delivery Sales Taxes and Charges line.

	``configured`` (``App Settings.delivery_charge_account``) wins when it is
	a real Account; otherwise fall back to the company's default
	``Freight and Forwarding Charges - {abbr}`` (created by ERPNext's chart of
	accounts). Returns ``None`` when neither resolves.
	"""
	if configured and frappe.db.exists("Account", configured):
		return configured
	abbr = frappe.db.get_value("Company", company, "abbr")
	if abbr:
		candidate = f"Freight and Forwarding Charges - {abbr}"
		if frappe.db.exists("Account", candidate):
			return candidate
	return None
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_delivery`
Expected: PASS (all 7).

- [ ] **Step 5: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/services/delivery.py grocery/tests/test_delivery.py
git commit -m "feat(delivery): fee rule + charge-account resolution service"
```

---

## Task 2: App Settings fields + validation

**Files:**
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/grocery/doctype/app_settings/app_settings.json`
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/grocery/doctype/app_settings/app_settings.py`
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/grocery/doctype/app_settings/test_app_settings.py`

**Interfaces:**
- Consumes: `grocery.services.delivery.resolve_charge_account` (Task 1).
- Produces: `App Settings` fields `delivery_fee` (Currency), `free_delivery_over` (Currency), `delivery_charge_account` (Link → Account). `validate()` rejects negatives and (fee>0 with no resolvable account).

- [ ] **Step 1: Add the fields to the doctype JSON**

In `app_settings.json`, add these entries to `field_order` immediately after `"privacy_url"`:

```json
  "delivery_section",
  "delivery_fee",
  "free_delivery_over",
  "delivery_charge_account"
```

And append these objects to the `fields` array (after the `privacy_url` field object):

```json
  {
   "fieldname": "delivery_section",
   "fieldtype": "Section Break",
   "label": "Delivery"
  },
  {
   "default": "0",
   "fieldname": "delivery_fee",
   "fieldtype": "Currency",
   "label": "Delivery Fee",
   "description": "Flat delivery fee added to every order's total. 0 disables the fee."
  },
  {
   "default": "0",
   "fieldname": "free_delivery_over",
   "fieldtype": "Currency",
   "label": "Free Delivery Over",
   "description": "Waive the delivery fee when the item subtotal reaches this amount. 0 = never waive."
  },
  {
   "fieldname": "delivery_charge_account",
   "fieldtype": "Link",
   "label": "Delivery Charge Account",
   "options": "Account",
   "description": "Account head for the delivery charge line. Leave blank to use the company's Freight and Forwarding Charges account."
  }
```

- [ ] **Step 2: Write the failing tests**

Replace the body of `test_app_settings.py` with:

```python
# Copyright (c) 2026, Zad Grocery and Contributors
# See license.txt

import frappe
from frappe.tests import IntegrationTestCase


class IntegrationTestAppSettings(IntegrationTestCase):
	def _save(self, fee, over=0, account=None):
		s = frappe.get_single("App Settings")
		orig = (s.delivery_fee, s.free_delivery_over, s.delivery_charge_account)

		def restore():
			s2 = frappe.get_single("App Settings")
			s2.delivery_fee, s2.free_delivery_over, s2.delivery_charge_account = orig
			s2.save(ignore_permissions=True)

		self.addCleanup(restore)
		s.delivery_fee = fee
		s.free_delivery_over = over
		s.delivery_charge_account = account
		s.save(ignore_permissions=True)
		return frappe.get_single("App Settings")

	def test_negative_fee_rejected(self):
		with self.assertRaises(frappe.ValidationError):
			self._save(-1)

	def test_negative_threshold_rejected(self):
		with self.assertRaises(frappe.ValidationError):
			self._save(0, over=-1)

	def test_positive_fee_saves_with_default_freight_account(self):
		s = self._save(2000, 25000)
		self.assertEqual(s.delivery_fee, 2000)
		self.assertEqual(s.free_delivery_over, 25000)

	def test_zero_fee_saves_without_account(self):
		s = self._save(0)
		self.assertEqual(s.delivery_fee, 0)
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.grocery.doctype.app_settings.test_app_settings`
Expected: FAIL — `test_negative_fee_rejected` does not raise (no `validate` yet).

- [ ] **Step 4: Implement `validate`**

Replace `app_settings.py` with:

```python
# Copyright (c) 2026, Zad Grocery and contributors
# For license information, please see license.txt

import frappe
from frappe import _
from frappe.model.document import Document
from frappe.utils import flt

from grocery.services import delivery


class AppSettings(Document):
	def validate(self):
		self._validate_delivery()

	def _validate_delivery(self):
		"""Front-load the only delivery misconfiguration that could otherwise
		fail a live checkout: a fee with no resolvable charge account."""
		if flt(self.delivery_fee) < 0:
			frappe.throw(_("Delivery Fee cannot be negative."))
		if flt(self.free_delivery_over) < 0:
			frappe.throw(_("Free Delivery Over cannot be negative."))
		if flt(self.delivery_fee) > 0:
			company = self._company()
			account = delivery.resolve_charge_account(company, configured=self.delivery_charge_account)
			if not account:
				frappe.throw(
					_(
						"Set a Delivery Charge Account (or create the company's "
						"Freight and Forwarding Charges account) before setting a Delivery Fee."
					)
				)

	def _company(self) -> str | None:
		"""Best-effort company for save-time account validation: the default
		warehouse's company, else the global default company. ``place_order``
		resolves against the actual SO company, so this is only the guard."""
		if self.default_warehouse:
			company = frappe.db.get_value("Warehouse", self.default_warehouse, "company")
			if company:
				return company
		return frappe.defaults.get_global_default("company")
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.grocery.doctype.app_settings.test_app_settings`
Expected: PASS (all 4).

- [ ] **Step 6: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/grocery/doctype/app_settings/
git commit -m "feat(delivery): App Settings delivery fee fields + validation"
```

---

## Task 3: Expose the fee in `content.get_app_config`

**Files:**
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/api/content.py`
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_content.py`

**Interfaces:**
- Produces: `get_app_config()` return dict gains `"delivery_fee"` (float) and `"free_delivery_over"` (float).

- [ ] **Step 1: Update the failing tests**

In `test_content.py`, add `"delivery_fee"` and `"free_delivery_over"` to the `expected_keys` set in `test_get_app_config_shape` (after `"store_is_open"`), and add this test method to the class:

```python
	def test_get_app_config_echoes_delivery_fee(self):
		original = {
			"delivery_fee": frappe.db.get_single_value("App Settings", "delivery_fee"),
			"free_delivery_over": frappe.db.get_single_value("App Settings", "free_delivery_over"),
		}

		def restore():
			for field, value in original.items():
				frappe.db.set_single_value("App Settings", field, value)

		self.addCleanup(restore)
		frappe.db.set_single_value("App Settings", "delivery_fee", 2000)
		frappe.db.set_single_value("App Settings", "free_delivery_over", 25000)

		config = content.get_app_config()
		self.assertEqual(config["delivery_fee"], 2000)
		self.assertEqual(config["free_delivery_over"], 25000)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_content`
Expected: FAIL — `test_get_app_config_shape` key mismatch and `test_get_app_config_echoes_delivery_fee` KeyError.

- [ ] **Step 3: Implement**

In `content.py`, add `from frappe.utils import flt` to the imports, and add these two keys to the dict returned by `get_app_config` (after `"store_is_open": hours["is_open"],`):

```python
		"delivery_fee": flt(settings.delivery_fee),
		"free_delivery_over": flt(settings.free_delivery_over),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_content`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/api/content.py grocery/tests/test_content.py
git commit -m "feat(delivery): surface delivery_fee + free_delivery_over in get_app_config"
```

---

## Task 4: Charge the fee on the Sales Order + surface it in `order.detail`

**Files:**
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/api/order.py`
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_order.py`

**Interfaces:**
- Consumes: `grocery.services.delivery.delivery_fee_for`, `grocery.services.delivery.resolve_charge_account` (Task 1).
- Produces: a placed Sales Order carries a "Delivery Charges" Sales Taxes and Charges line (`grand_total == net_total + fee`) when a fee applies; `order.detail` `totals` gains `"delivery_fee"` (= `flt(so.total_taxes_and_charges)`).

- [ ] **Step 1: Write the failing tests**

Add a delivery helper + tests to `test_order.py`. First, add this helper method to `IntegrationTestPlaceOrder` (next to `_set_hours_window`):

```python
	def _set_delivery(self, fee, over=0):
		original = {
			"delivery_fee": frappe.db.get_single_value("App Settings", "delivery_fee"),
			"free_delivery_over": frappe.db.get_single_value("App Settings", "free_delivery_over"),
		}

		def restore():
			for field, value in original.items():
				frappe.db.set_single_value("App Settings", field, value)

		self.addCleanup(restore)
		frappe.db.set_single_value("App Settings", "delivery_fee", fee)
		frappe.db.set_single_value("App Settings", "free_delivery_over", over)
```

Then add these test methods (they rely on the existing `self._set_hours_window`, `self._add`, `fx`, and `flt` — add `from frappe.utils import flt` to the imports if not already present; note `add_to_date, now_datetime` are already imported):

```python
	def test_place_order_adds_delivery_charge(self):
		self._set_delivery(fee=2000, over=0)  # over=0 → always charge
		self._set_hours_window(-1, 1)
		item = fx.make_stock_item(qty=10, rate=2500, item_name="Task5 Deliv Apples")
		self._add(item.item_code, 2)  # net_total 5000

		result = order.place_order(address=self.address, idempotency_key="deliv-charge-1")
		so = frappe.get_doc("Sales Order", result["order"])

		self.assertEqual(flt(so.total_taxes_and_charges), 2000)
		self.assertEqual(flt(so.grand_total), flt(so.net_total) + 2000)
		self.assertTrue(any(row.description == "Delivery Charges" for row in so.taxes))

	def test_place_order_free_over_threshold(self):
		self._set_delivery(fee=2000, over=4000)  # net 5000 >= 4000 → free
		self._set_hours_window(-1, 1)
		item = fx.make_stock_item(qty=10, rate=2500, item_name="Task5 Deliv Free")
		self._add(item.item_code, 2)  # net_total 5000

		result = order.place_order(address=self.address, idempotency_key="deliv-free-1")
		so = frappe.get_doc("Sales Order", result["order"])

		self.assertEqual(flt(so.total_taxes_and_charges), 0)
		self.assertEqual(flt(so.grand_total), flt(so.net_total))

	def test_place_order_no_charge_when_fee_zero(self):
		self._set_delivery(fee=0, over=0)
		self._set_hours_window(-1, 1)
		item = fx.make_stock_item(qty=10, rate=2500, item_name="Task5 Deliv Zero")
		self._add(item.item_code, 1)

		result = order.place_order(address=self.address, idempotency_key="deliv-zero-1")
		so = frappe.get_doc("Sales Order", result["order"])

		self.assertEqual(flt(so.total_taxes_and_charges), 0)
		self.assertEqual(flt(so.grand_total), flt(so.net_total))

	def test_detail_includes_delivery_fee(self):
		self._set_delivery(fee=1500, over=0)
		self._set_hours_window(-1, 1)
		item = fx.make_stock_item(qty=10, rate=2000, item_name="Task5 Deliv Detail")
		self._add(item.item_code, 1)  # net_total 2000

		result = order.place_order(address=self.address, idempotency_key="deliv-detail-1")
		detail = order.detail(result["order"])

		self.assertEqual(detail["totals"]["delivery_fee"], 1500)
		self.assertEqual(
			detail["totals"]["grand_total"], detail["totals"]["net_total"] + 1500
		)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_order --test test_place_order_adds_delivery_charge`
Expected: FAIL — `total_taxes_and_charges` is 0 (no charge added yet).

- [ ] **Step 3: Implement the charge in `_build_sales_order`**

In `order.py`, extend the services import:

```python
from grocery.services import assignment, delivery, zones
```

In `_build_sales_order`, after the existing `company = ...` / `expiry_minutes = ...` lines and before `so = frappe.get_doc({...})`, compute the charge:

```python
	fee = delivery.delivery_fee_for(flt(cart.net_total))
	taxes = []
	if fee > 0:
		account = delivery.resolve_charge_account(
			company,
			configured=frappe.db.get_single_value("App Settings", "delivery_charge_account"),
		)
		if account:
			taxes.append(
				{
					"charge_type": "Actual",
					"account_head": account,
					"description": _("Delivery Charges"),
					"tax_amount": fee,
					"cost_center": frappe.db.get_value("Company", company, "cost_center"),
				}
			)
		else:
			# Save-time App Settings validation guarantees an account when a
			# fee is set, so this is defence in depth: never fail checkout —
			# place the order without the charge and flag it for ops.
			frappe.log_error(
				title="grocery.api.order: delivery charge account unresolved",
				message=f"company={company} fee={fee}",
			)
```

Then add `"taxes": taxes,` to the `frappe.get_doc({...})` dict (e.g. immediately after the `"custom_zone": zone["name"],` line):

```python
			"taxes": taxes,
```

- [ ] **Step 4: Add `delivery_fee` to `order.detail` totals**

In `order.py` `detail`, change the `totals` dict to include the fee:

```python
		"totals": {
			"net_total": flt(so.net_total),
			"delivery_fee": flt(so.total_taxes_and_charges),
			"grand_total": flt(so.grand_total),
			"currency": so.currency,
		},
```

- [ ] **Step 5: Run the delivery tests to verify they pass**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_order --test test_place_order_adds_delivery_charge`
Then: `bench --site grocery.localhost run-tests --module grocery.tests.test_order --test test_place_order_free_over_threshold`
Then: `bench --site grocery.localhost run-tests --module grocery.tests.test_order --test test_detail_includes_delivery_fee`
Expected: PASS.

- [ ] **Step 6: Run the full order module to guard against regressions**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_order`
Expected: PASS (existing happy-path/idempotency/coverage tests unaffected — `grand_total == net_total` still holds because those tests leave `delivery_fee` at 0).

- [ ] **Step 7: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/api/order.py grocery/tests/test_order.py
git commit -m "feat(delivery): charge delivery fee on Sales Order + expose in order.detail"
```

---

## Task 5: `AppConfig` — parse the fee + expose the rule (app)

**Files:**
- Modify: `~/Flutter/zad/lib/models/app_config.dart`
- Test: `~/Flutter/zad/test/models/app_config_test.dart`

**Interfaces:**
- Produces: `AppConfig.deliveryFee` (`double?`), `AppConfig.freeDeliveryOver` (`double?`), `AppConfig.hasDeliveryFee` (`bool`, true iff `deliveryFee > 0`), `AppConfig.deliveryFeeFor(double netTotal) -> double` (the Global-Constraints rule). Parsed from `delivery_fee` / `free_delivery_over`; round-tripped in `toJson`.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/app_config_test.dart` (inside `main()`):

```dart
  test('parses delivery fee fields and round-trips them', () {
    final config = AppConfig.fromJson({
      'delivery_fee': 2000,
      'free_delivery_over': 25000,
    });
    expect(config.deliveryFee, 2000);
    expect(config.freeDeliveryOver, 25000);

    final round = AppConfig.fromJson(config.toJson());
    expect(round.deliveryFee, 2000);
    expect(round.freeDeliveryOver, 25000);
  });

  test('deliveryFeeFor applies the fee below the threshold', () {
    const config = AppConfig(deliveryFee: 2000, freeDeliveryOver: 25000);
    expect(config.hasDeliveryFee, isTrue);
    expect(config.deliveryFeeFor(18000), 2000);
  });

  test('deliveryFeeFor waives the fee at or above the threshold', () {
    const config = AppConfig(deliveryFee: 2000, freeDeliveryOver: 25000);
    expect(config.deliveryFeeFor(25000), 0);
    expect(config.deliveryFeeFor(30000), 0);
  });

  test('deliveryFeeFor always charges when the threshold is 0/unset', () {
    const config = AppConfig(deliveryFee: 2000);
    expect(config.deliveryFeeFor(9999999), 2000);
  });

  test('deliveryFeeFor is free and hasDeliveryFee false when fee is unset', () {
    const config = AppConfig();
    expect(config.hasDeliveryFee, isFalse);
    expect(config.deliveryFeeFor(1000), 0);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/models/app_config_test.dart`
Expected: FAIL — `deliveryFee`/`freeDeliveryOver`/`deliveryFeeFor`/`hasDeliveryFee` are not defined.

- [ ] **Step 3: Implement the fields + methods**

In `lib/models/app_config.dart`:

Add two constructor params (after `this.storeCloseTime,`):

```dart
    this.deliveryFee,
    this.freeDeliveryOver,
```

Add the fields (after `final String? storeCloseTime;`):

```dart
  /// Flat delivery fee (IQD) from App Settings; null/0 = no fee configured.
  final double? deliveryFee;

  /// Item-subtotal at/above which delivery is free (IQD); null/0 = never.
  final double? freeDeliveryOver;
```

In `fromJson`, add (after `storeCloseTime: json['store_close_time'] as String?,`):

```dart
      deliveryFee: toDouble(json['delivery_fee']),
      freeDeliveryOver: toDouble(json['free_delivery_over']),
```

In `toJson`, add (after `'store_close_time': storeCloseTime,`):

```dart
        'delivery_fee': deliveryFee,
        'free_delivery_over': freeDeliveryOver,
```

Add these methods (e.g. after `isStoreOpenAt`):

```dart
  /// Whether a positive delivery fee is configured. Drives whether checkout
  /// shows a Delivery line at all — an unset/0 fee behaves exactly as before
  /// (no line, Total == Subtotal).
  bool get hasDeliveryFee => (deliveryFee ?? 0) > 0;

  /// The delivery fee applied to a basket whose item subtotal is [netTotal]
  /// — the app's advisory copy of the backend rule (`delivery_fee_for`); the
  /// server recomputes authoritatively at `place_order`. 0 when no fee is
  /// configured or the subtotal reaches the free-delivery threshold.
  double deliveryFeeFor(double netTotal) {
    final fee = deliveryFee ?? 0;
    final threshold = freeDeliveryOver ?? 0;
    if (fee <= 0) return 0;
    if (threshold > 0 && netTotal >= threshold) return 0;
    return fee;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/models/app_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Flutter/zad
git add lib/models/app_config.dart test/models/app_config_test.dart
git commit -m "feat(delivery): AppConfig delivery fee fields + deliveryFeeFor rule"
```

---

## Task 6: Checkout summary — Delivery line + Total (app)

**Files:**
- Modify: `~/Flutter/zad/lib/l10n/app_en.arb`, `~/Flutter/zad/lib/l10n/app_ar.arb`
- Modify: `~/Flutter/zad/lib/features/checkout/checkout_page.dart`
- Test: `~/Flutter/zad/test/features/checkout/checkout_page_test.dart`

**Interfaces:**
- Consumes: `AppConfig.hasDeliveryFee`, `AppConfig.deliveryFeeFor` (Task 5); l10n `checkoutDelivery`, `checkoutDeliveryFree`.
- Produces: `_SummaryCard` renders a Delivery row (amount or "Free") when `config.hasDeliveryFee`, and its Total = `netTotal + config.deliveryFeeFor(netTotal)`.

- [ ] **Step 1: Add the l10n strings**

In `lib/l10n/app_en.arb`, add after the `"checkoutOrderSummary": "Order Summary",` line:

```json
  "checkoutDelivery": "Delivery",
  "checkoutDeliveryFree": "Free",
```

In `lib/l10n/app_ar.arb`, add after the `"checkoutOrderSummary": "ملخص الطلب",` line:

```json
  "checkoutDelivery": "التوصيل",
  "checkoutDeliveryFree": "مجاني",
```

- [ ] **Step 2: Regenerate localizations**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter gen-l10n`
Expected: regenerates `lib/l10n/app_localizations*.dart` with `checkoutDelivery` / `checkoutDeliveryFree` getters, no errors.

- [ ] **Step 3: Write the failing widget tests**

In `test/features/checkout/checkout_page_test.dart`, add these two tests inside `main()` (they reuse the file's `buildCheckout` and `_loadedConfigStore` helpers; the fake cart's `net_total` is 4750):

```dart
  testWidgets('shows the delivery fee line and adds it to the total', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final configStore = await _loadedConfigStore(
      tester,
      {'delivery_fee': 2000, 'free_delivery_over': 25000},
    );
    await tester.pumpWidget(await buildCheckout(tester, appConfigStore: configStore));
    await tester.pumpAndSettle();

    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('IQD 2,000'), findsOneWidget); // fee line
    expect(find.text('IQD 4,750'), findsOneWidget); // subtotal
    expect(find.text('IQD 6,750'), findsOneWidget); // subtotal + fee
  });

  testWidgets('shows Free when the basket clears the free-delivery threshold', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final configStore = await _loadedConfigStore(
      tester,
      {'delivery_fee': 2000, 'free_delivery_over': 1000}, // 4750 >= 1000 → free
    );
    await tester.pumpWidget(await buildCheckout(tester, appConfigStore: configStore));
    await tester.pumpAndSettle();

    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('IQD 4,750'), findsNWidgets(2)); // subtotal + total (no fee added)
  });
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/features/checkout/checkout_page_test.dart`
Expected: FAIL — no "Delivery"/"Free" text; total is 4,750 not 6,750.

- [ ] **Step 5: Implement the Delivery row**

In `lib/features/checkout/checkout_page.dart`:

Pass the config into the card — in `_buildBody`, change the `_SummaryCard(...)` call to include `config` (already in scope as the `config` local):

```dart
              _SummaryCard(items: items, totals: cart.totals, l10n: l10n, config: config),
```

Add the field + constructor param to `_SummaryCard`:

```dart
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.items,
    required this.totals,
    required this.l10n,
    required this.config,
  });

  final List<CartLineView> items;
  final CartTotals totals;
  final AppLocalizations l10n;
  final AppConfig config;
```

In `_SummaryCard.build`, right after `final languageCode = Localizations.localeOf(context).languageCode;`, compute the fee:

```dart
    final deliveryFee = config.deliveryFeeFor(totals.netTotal);
```

Between the subtotal `Row` and the `const SizedBox(height: 6),`-then-total `Row`, insert the Delivery row (only when a fee is configured):

```dart
          if (config.hasDeliveryFee) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.checkoutDelivery,
                  style: const TextStyle(fontSize: 13, color: ZadColors.muted),
                ),
                Text(
                  deliveryFee > 0
                      ? formatPrice(deliveryFee, languageCode)
                      : l10n.checkoutDeliveryFree,
                  style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                ),
              ],
            ),
          ],
```

Change the Total value from `totals.grandTotal` to the subtotal-plus-fee figure:

```dart
                formatPrice(totals.netTotal + deliveryFee, languageCode),
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/features/checkout/checkout_page_test.dart`
Expected: PASS — including the existing `renders the default-preselected address, summary lines, COD and totals` test (default config has no fee ⇒ no Delivery row, total stays `IQD 4,750`).

- [ ] **Step 7: Commit**

```bash
cd ~/Flutter/zad
git add lib/l10n/ lib/features/checkout/checkout_page.dart test/features/checkout/checkout_page_test.dart
git commit -m "feat(delivery): checkout Delivery line + fee-inclusive total"
```

---

## Task 7: Order detail — Delivery line (app)

**Files:**
- Modify: `~/Flutter/zad/lib/data/cart_repository.dart`
- Modify: `~/Flutter/zad/lib/features/orders/order_detail_page.dart`
- Test: `~/Flutter/zad/test/features/orders/order_detail_page_test.dart`

**Interfaces:**
- Consumes: l10n `checkoutDelivery` (Task 6); `order.detail` `totals.delivery_fee` (Task 4).
- Produces: `CartTotals.deliveryFee` (`double`, default 0, parsed from `delivery_fee`); order detail renders a Delivery row when `totals.deliveryFee > 0`.

- [ ] **Step 1: Write the failing widget test**

In `test/features/orders/order_detail_page_test.dart`, add this test inside `main()` (it overrides `order.detail` with a fee-bearing totals block; `order.changes` falls back to the default `_changesJson`):

```dart
  testWidgets('renders a Delivery line when the order carries a delivery fee',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final detailWithFee = {
      ..._detailJson,
      'totals': {
        'net_total': 4975,
        'delivery_fee': 1000,
        'grand_total': 5975,
        'currency': 'IQD',
      },
    };

    await tester.pumpWidget(_page(tester, detail: detailWithFee));
    await tester.pumpAndSettle();

    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('IQD 1,000'), findsOneWidget); // fee line (distinct from any line rate)
    expect(find.text('IQD 4,975'), findsOneWidget); // subtotal
    expect(find.text('IQD 5,975'), findsOneWidget); // grand total (fee included)
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/features/orders/order_detail_page_test.dart`
Expected: FAIL — no "Delivery" text; `IQD 2,000` not found (the fee is parsed but not rendered).

- [ ] **Step 3: Add `deliveryFee` to `CartTotals`**

In `lib/data/cart_repository.dart`, update `CartTotals`:

```dart
class CartTotals {
  const CartTotals({
    required this.netTotal,
    required this.grandTotal,
    this.deliveryFee = 0,
    this.currency,
  });

  final double netTotal;
  final double grandTotal;
  final double deliveryFee;
  final String? currency;

  factory CartTotals.fromJson(dynamic json) {
    if (json is! Map) return const CartTotals(netTotal: 0, grandTotal: 0);
    return CartTotals(
      netTotal: toDouble(json['net_total']) ?? 0,
      grandTotal: toDouble(json['grand_total']) ?? 0,
      deliveryFee: toDouble(json['delivery_fee']) ?? 0,
      currency: json['currency'] as String?,
    );
  }
}
```

- [ ] **Step 4: Render the Delivery row in order detail**

In `lib/features/orders/order_detail_page.dart`, between the subtotal `Row` (ends at its closing `),` after `line ~186`) and the following `const SizedBox(height: 6),`, insert:

```dart
              if (detail.totals.deliveryFee > 0) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.checkoutDelivery,
                      style: const TextStyle(fontSize: 13, color: ZadColors.muted),
                    ),
                    Text(
                      formatPrice(detail.totals.deliveryFee, languageCode),
                      style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                    ),
                  ],
                ),
              ],
```

(The Total row is unchanged — `detail.totals.grandTotal` already includes the fee from the backend.)

- [ ] **Step 5: Run test to verify it passes**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/features/orders/order_detail_page_test.dart`
Expected: PASS — including the existing totals test (default `_detailJson` has no `delivery_fee` ⇒ no Delivery row, `IQD 4,975` ×2).

- [ ] **Step 6: Commit**

```bash
cd ~/Flutter/zad
git add lib/data/cart_repository.dart lib/features/orders/order_detail_page.dart test/features/orders/order_detail_page_test.dart
git commit -m "feat(delivery): order-detail Delivery line"
```

---

## Task 8: Full-suite verification

**Files:** none (verification only).

- [ ] **Step 1: Backend — run the full grocery test app**

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --app grocery`
Expected: PASS (no regressions in cart/order/content/app_settings/checkout-concurrency).

- [ ] **Step 2: App — analyze + full test suite**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter analyze && ~/.flutter-sdk/bin/flutter test`
Expected: analyze clean; all tests PASS.

- [ ] **Step 3: Post-deploy setup note (manual, not code)**

After deploying both apps, an admin opens **App Settings → Delivery** and sets `Delivery Fee` (e.g. 2000) and `Free Delivery Over` (e.g. 25000); `Delivery Charge Account` may stay blank (defaults to `Freight and Forwarding Charges - ZG`). Until a positive fee is set, the app shows no Delivery line and Total == Subtotal.

---

## Self-review notes

- **Spec coverage:** App Settings fields + validation → Task 2; `get_app_config` exposure → Task 3; real SO charge → Task 4; `order.detail` fee → Task 4; `AppConfig` fields + rule → Task 5; checkout Delivery line + total → Task 6; order-detail line → Task 7; l10n → Task 6; single fee rule shared → Task 1 (Python) + Task 5 (Dart); tests → every task + Task 8. The spec's "insert a Delivery row" is refined to "insert when `delivery_fee > 0`" to honor the spec's own "fee 0 ⇒ exactly as today" rollout guarantee.
- **Type consistency:** `delivery_fee_for` / `resolve_charge_account` signatures identical across Tasks 1, 2, 4; `deliveryFeeFor` / `hasDeliveryFee` / `deliveryFee` / `freeDeliveryOver` identical across Tasks 5, 6; `CartTotals.deliveryFee` (Task 7) matches its `order.detail` producer key `delivery_fee` (Task 4).
- **No placeholders:** every code and test step carries complete content.
