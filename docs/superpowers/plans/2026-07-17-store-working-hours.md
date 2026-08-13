# Store Working Hours Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admins set a daily store open/close time in the Frappe backend; checkout (`place_order`) is blocked server-side outside that window, and the Flutter checkout page shows a localized "store closed" notice with a disabled submit button.

**Architecture:** Two `Time` fields on the `App Settings` single doctype. A `store_hours()` helper in `grocery/api/utils.py` computes open/closed on the server clock (site timezone), supporting overnight windows. `place_order` throws a new `StoreClosedError` (HTTP 425) when closed; `get_app_config` exposes the times so the Flutter app computes open/closed locally with the device clock. The Flutter `ApiClient` maps 425 to a new `StoreClosedException`; the checkout page disables its CTA and shows a notice when closed (locally computed OR server-reported).

**Tech Stack:** Frappe/ERPNext v16 (Python 3.14), Flutter (Dart, provider, dio), flutter gen-l10n.

**Spec:** `docs/superpowers/specs/2026-07-17-store-working-hours-design.md`

## Global Constraints

- Backend repo: `/home/frappe/Frappe/grocery-bench/apps/grocery` (git branch `version-16`). Flutter repo: `/home/frappe/Flutter/zad` (git branch `feature/zad-mvp`). Commit each task in the repo it touches.
- Bench commands need Python 3.14 on PATH: prefix with `env PATH="$HOME/.local/bin:$PATH"` and run from `/home/frappe/Frappe/grocery-bench`. Site is `grocery.localhost`.
- If bench commands fail with a Redis connection error, start redis first (from the bench root): `redis-server config/redis_queue.conf --daemonize yes && redis-server config/redis_cache.conf --daemonize yes`.
- Flutter SDK is NOT on PATH: use `~/.flutter-sdk/bin/flutter`.
- Backend tests run against the live dev site — every test that changes `App Settings` singles MUST capture the original values and restore them in `addCleanup`.
- Backend code style: tabs for indentation (match existing files). Flutter: 2-space, match existing style.
- Window semantics (identical on both sides): both times unset, either unset, or `open == close` → always open; `open < close` → open when `open ≤ now < close`; `open > close` → overnight, open when `now ≥ open` OR `now < close`.
- New HTTP status contract: **425 = store_closed** (409 out_of_stock, 417 outside_coverage, 423 otp_cooldown are taken).

---

### Task 1: App Settings doctype fields (backend)

**Files:**
- Modify: `/home/frappe/Frappe/grocery-bench/apps/grocery/grocery/grocery/doctype/app_settings/app_settings.json`

**Interfaces:**
- Produces: `App Settings.store_open_time` and `App Settings.store_close_time` (fieldtype `Time`, optional) readable via `frappe.db.get_single_value("App Settings", "store_open_time")` → `"HH:MM:SS"` string or `None`.

- [ ] **Step 1: Add the two fields to the doctype JSON**

In `app_settings.json`, change the `field_order` array to insert the two new fieldnames right after `"maintenance_mode"`:

```json
 "field_order": [
  "splash_image",
  "splash_bg_color",
  "splash_duration_sec",
  "app_min_version",
  "maintenance_mode",
  "store_open_time",
  "store_close_time",
  "default_warehouse",
  "default_price_list",
  "order_expiry_minutes",
  "picker_accept_timeout_min",
  "driver_accept_timeout_min",
  "support_phone"
 ],
```

And in the `fields` array, insert these two objects between the `maintenance_mode` object and the `default_warehouse` object:

```json
  {
   "fieldname": "store_open_time",
   "fieldtype": "Time",
   "label": "Store Open Time"
  },
  {
   "fieldname": "store_close_time",
   "fieldtype": "Time",
   "label": "Store Close Time"
  },
```

- [ ] **Step 2: Migrate the site so the doctype reloads**

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost migrate
```

Expected: migration completes without error (ends with queue/cache lines, exit code 0).

- [ ] **Step 3: Verify the fields exist in meta**

```bash
cd /home/frappe/Frappe/grocery-bench && echo 'print(frappe.get_meta("App Settings").has_field("store_open_time"), frappe.get_meta("App Settings").has_field("store_close_time"))' | env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost console
```

Expected output contains: `True True`

- [ ] **Step 4: Commit (backend repo)**

```bash
cd /home/frappe/Frappe/grocery-bench/apps/grocery && git add grocery/grocery/doctype/app_settings/app_settings.json && git commit -m "feat(settings): store_open_time / store_close_time fields on App Settings"
```

---

### Task 2: `store_hours()` helper (backend, TDD)

**Files:**
- Create: `/home/frappe/Frappe/grocery-bench/apps/grocery/grocery/tests/test_store_hours.py`
- Modify: `/home/frappe/Frappe/grocery-bench/apps/grocery/grocery/api/utils.py`

**Interfaces:**
- Consumes: the Task 1 fields via `frappe.db.get_single_value`.
- Produces: `grocery.api.utils.store_hours() -> dict` returning `{"is_open": bool, "open_time": "HH:MM:SS" | None, "close_time": "HH:MM:SS" | None}`. `now_datetime` is imported INTO `grocery.api.utils` namespace so tests patch `grocery.api.utils.now_datetime`.

- [ ] **Step 1: Write the failing tests**

Create `grocery/tests/test_store_hours.py` (tabs for indentation):

```python
# Copyright (c) 2026, Zad Grocery and contributors
# For license information, please see license.txt

"""``utils.store_hours`` — working-hours window semantics (design doc
2026-07-17-store-working-hours). Clock is patched (``grocery.api.utils.
now_datetime``) so every case is deterministic; App Settings values are
captured and restored because tests run against the live dev site."""

from datetime import datetime
from unittest.mock import patch

import frappe
from frappe.tests import IntegrationTestCase

from grocery.api import utils

NOON = datetime(2026, 7, 17, 12, 0, 0)
LATE_NIGHT = datetime(2026, 7, 17, 23, 30, 0)
EARLY_MORNING = datetime(2026, 7, 17, 1, 0, 0)


class IntegrationTestStoreHours(IntegrationTestCase):
	def _set_hours(self, open_time, close_time):
		"""Set the window, restoring the site's original values afterwards."""
		original = {
			"store_open_time": frappe.db.get_single_value("App Settings", "store_open_time"),
			"store_close_time": frappe.db.get_single_value("App Settings", "store_close_time"),
		}

		def restore():
			for field, value in original.items():
				frappe.db.set_single_value("App Settings", field, value)

		self.addCleanup(restore)
		frappe.db.set_single_value("App Settings", "store_open_time", open_time)
		frappe.db.set_single_value("App Settings", "store_close_time", close_time)

	def _hours_at(self, now):
		with patch("grocery.api.utils.now_datetime", return_value=now):
			return utils.store_hours()

	def test_unconfigured_is_always_open(self):
		self._set_hours(None, None)
		hours = self._hours_at(NOON)
		self.assertTrue(hours["is_open"])
		self.assertIsNone(hours["open_time"])
		self.assertIsNone(hours["close_time"])

	def test_half_configured_is_always_open(self):
		self._set_hours("09:00:00", None)
		self.assertTrue(self._hours_at(LATE_NIGHT)["is_open"])
		self._set_hours(None, "23:00:00")
		self.assertTrue(self._hours_at(LATE_NIGHT)["is_open"])

	def test_equal_times_is_always_open(self):
		self._set_hours("09:00:00", "09:00:00")
		self.assertTrue(self._hours_at(EARLY_MORNING)["is_open"])

	def test_same_day_window(self):
		self._set_hours("09:00:00", "23:00:00")
		self.assertTrue(self._hours_at(NOON)["is_open"])
		self.assertFalse(self._hours_at(LATE_NIGHT)["is_open"])
		self.assertFalse(self._hours_at(EARLY_MORNING)["is_open"])

	def test_same_day_window_boundaries(self):
		self._set_hours("09:00:00", "23:00:00")
		# open <= now (inclusive lower bound)
		self.assertTrue(self._hours_at(datetime(2026, 7, 17, 9, 0, 0))["is_open"])
		# now < close (exclusive upper bound)
		self.assertFalse(self._hours_at(datetime(2026, 7, 17, 23, 0, 0))["is_open"])

	def test_overnight_window(self):
		self._set_hours("18:00:00", "02:00:00")
		self.assertTrue(self._hours_at(LATE_NIGHT)["is_open"])  # after open
		self.assertTrue(self._hours_at(EARLY_MORNING)["is_open"])  # before close
		self.assertFalse(self._hours_at(NOON)["is_open"])  # midday gap

	def test_times_echoed_as_normalized_strings(self):
		self._set_hours("09:00:00", "23:00:00")
		hours = self._hours_at(NOON)
		self.assertEqual(hours["open_time"], "09:00:00")
		self.assertEqual(hours["close_time"], "23:00:00")
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost run-tests --module grocery.tests.test_store_hours
```

Expected: every test ERRORs with `AttributeError: module 'grocery.api.utils' has no attribute 'store_hours'` (or `now_datetime` patch failure — same root cause: not implemented yet).

- [ ] **Step 3: Implement `store_hours()` in `grocery/api/utils.py`**

Change the import line at the top of `utils.py` from:

```python
import frappe
from frappe import _
```

to:

```python
import frappe
from frappe import _
from frappe.utils import get_time, now_datetime
```

Append at the end of the file:

```python
def store_hours() -> dict:
	"""Working-hours window from ``App Settings`` (design doc
	2026-07-17-store-working-hours), evaluated on the server clock in the
	site timezone.

	Semantics: unset / half-set / ``open == close`` → always open (fail
	open — never lock the store by accident); ``open < close`` → open when
	``open <= now < close``; ``open > close`` → overnight window, open when
	``now >= open`` or ``now < close``.
	"""
	raw_open = frappe.db.get_single_value("App Settings", "store_open_time")
	raw_close = frappe.db.get_single_value("App Settings", "store_close_time")
	open_t = get_time(raw_open) if raw_open else None
	close_t = get_time(raw_close) if raw_close else None

	if not open_t or not close_t or open_t == close_t:
		is_open = True
	else:
		now = now_datetime().time()
		if open_t < close_t:
			is_open = open_t <= now < close_t
		else:
			is_open = now >= open_t or now < close_t

	return {
		"is_open": is_open,
		"open_time": open_t.strftime("%H:%M:%S") if open_t else None,
		"close_time": close_t.strftime("%H:%M:%S") if close_t else None,
	}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost run-tests --module grocery.tests.test_store_hours
```

Expected: `OK` — 7 tests pass.

- [ ] **Step 5: Commit (backend repo)**

```bash
cd /home/frappe/Frappe/grocery-bench/apps/grocery && git add grocery/api/utils.py grocery/tests/test_store_hours.py && git commit -m "feat(hours): store_hours() window helper — site-tz clock, overnight windows, fail-open"
```

---

### Task 3: Expose hours in `get_app_config` (backend, TDD)

**Files:**
- Modify: `/home/frappe/Frappe/grocery-bench/apps/grocery/grocery/api/content.py`
- Test: `/home/frappe/Frappe/grocery-bench/apps/grocery/grocery/tests/test_content.py`

**Interfaces:**
- Consumes: `grocery.api.utils.store_hours()` from Task 2.
- Produces: `get_app_config()` response gains `store_open_time` (`"HH:MM:SS"` | null), `store_close_time` (`"HH:MM:SS"` | null), `store_is_open` (bool). The Flutter model (Task 5) parses `store_open_time` / `store_close_time`.

- [ ] **Step 1: Update the exact-shape test and add a values test**

In `grocery/tests/test_content.py`, replace `test_get_app_config_shape` with:

```python
	def test_get_app_config_shape(self):
		config = content.get_app_config()
		expected_keys = {
			"splash_image",
			"splash_bg_color",
			"splash_duration_sec",
			"app_min_version",
			"maintenance_mode",
			"support_phone",
			"today_currency",
			"store_open_time",
			"store_close_time",
			"store_is_open",
		}
		self.assertEqual(set(config.keys()), expected_keys)
		self.assertEqual(config["today_currency"], "IQD")
		self.assertIsInstance(config["maintenance_mode"], bool)
		self.assertIsInstance(config["store_is_open"], bool)
```

And add this test after it (plus the imports it needs — add `from datetime import datetime` and `from unittest.mock import patch` to the module imports):

```python
	def test_get_app_config_echoes_store_hours(self):
		original = {
			"store_open_time": frappe.db.get_single_value("App Settings", "store_open_time"),
			"store_close_time": frappe.db.get_single_value("App Settings", "store_close_time"),
		}

		def restore():
			for field, value in original.items():
				frappe.db.set_single_value("App Settings", field, value)

		self.addCleanup(restore)
		frappe.db.set_single_value("App Settings", "store_open_time", "09:00:00")
		frappe.db.set_single_value("App Settings", "store_close_time", "23:00:00")

		with patch("grocery.api.utils.now_datetime", return_value=datetime(2026, 7, 17, 12, 0, 0)):
			config = content.get_app_config()
		self.assertEqual(config["store_open_time"], "09:00:00")
		self.assertEqual(config["store_close_time"], "23:00:00")
		self.assertTrue(config["store_is_open"])

		with patch("grocery.api.utils.now_datetime", return_value=datetime(2026, 7, 17, 23, 30, 0)):
			config = content.get_app_config()
		self.assertFalse(config["store_is_open"])
```

- [ ] **Step 2: Run the content tests to verify the new ones fail**

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost run-tests --module grocery.tests.test_content
```

Expected: `test_get_app_config_shape` FAILS (missing keys) and `test_get_app_config_echoes_store_hours` FAILS with `KeyError: 'store_open_time'`.

- [ ] **Step 3: Implement the exposure in `content.py`**

Add the import below the existing `from frappe import _` line:

```python
from grocery.api.utils import store_hours
```

In `get_app_config`, change the return to:

```python
	settings = frappe.get_single("App Settings")
	hours = store_hours()
	return {
		"splash_image": settings.splash_image,
		"splash_bg_color": settings.splash_bg_color,
		"splash_duration_sec": settings.splash_duration_sec,
		"app_min_version": settings.app_min_version,
		"maintenance_mode": bool(settings.maintenance_mode),
		"support_phone": settings.support_phone,
		"store_open_time": hours["open_time"],
		"store_close_time": hours["close_time"],
		"store_is_open": hours["is_open"],
		"today_currency": APP_CURRENCY,
	}
```

- [ ] **Step 4: Run the content tests to verify they pass**

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost run-tests --module grocery.tests.test_content
```

Expected: `OK` — all content tests pass.

- [ ] **Step 5: Commit (backend repo)**

```bash
cd /home/frappe/Frappe/grocery-bench/apps/grocery && git add grocery/api/content.py grocery/tests/test_content.py && git commit -m "feat(config): expose store working hours + is_open snapshot in get_app_config"
```

---

### Task 4: `place_order` guard + `StoreClosedError` 425 + Arabic translation (backend, TDD)

**Files:**
- Modify: `/home/frappe/Frappe/grocery-bench/apps/grocery/grocery/api/order.py`
- Create: `/home/frappe/Frappe/grocery-bench/apps/grocery/grocery/translations/ar.csv`
- Test: `/home/frappe/Frappe/grocery-bench/apps/grocery/grocery/tests/test_order.py`

**Interfaces:**
- Consumes: `grocery.api.utils.store_hours()` from Task 2.
- Produces: `grocery.api.order.StoreClosedError` (subclass of `frappe.ValidationError`, `http_status_code = 425`), raised by `place_order` when the store is closed. The Flutter client (Task 6) maps HTTP 425 to `StoreClosedException`.

- [ ] **Step 1: Write the failing tests**

Add to `grocery/tests/test_order.py`, inside class `IntegrationTestPlaceOrder` (after the `test_guest_cannot_place_order` guard test). Also extend the module imports: the file already imports `frappe`, `add_to_date`, `now_datetime`, `order`, `fx`.

```python
	# -- working hours (design doc 2026-07-17-store-working-hours) ------------

	def _set_hours_window(self, open_delta_h, close_delta_h):
		"""Set the App Settings window relative to now, restoring originals.

		Relative windows keep these integration tests wall-clock-proof
		without patching the clock: [now+1h, now+2h] never contains now
		(closed) and [now-1h, now+1h] always does (open), under both the
		same-day and the overnight branch.
		"""
		original = {
			"store_open_time": frappe.db.get_single_value("App Settings", "store_open_time"),
			"store_close_time": frappe.db.get_single_value("App Settings", "store_close_time"),
		}

		def restore():
			for field, value in original.items():
				frappe.db.set_single_value("App Settings", field, value)

		self.addCleanup(restore)
		fmt = "%H:%M:%S"
		frappe.db.set_single_value(
			"App Settings", "store_open_time", add_to_date(now_datetime(), hours=open_delta_h).strftime(fmt)
		)
		frappe.db.set_single_value(
			"App Settings", "store_close_time", add_to_date(now_datetime(), hours=close_delta_h).strftime(fmt)
		)

	def test_place_order_blocked_while_closed(self):
		item = fx.make_stock_item(qty=10, rate=1000, item_name="Task5 Hours Closed")
		self._add(item.item_code, 1)
		self._set_hours_window(1, 2)  # opens in an hour — closed now

		before = frappe.db.count("Sales Order", {"customer": self.customer})
		with self.assertRaises(order.StoreClosedError) as ctx:
			order.place_order(address=self.address, idempotency_key="hours-closed-1")
		self.assertEqual(ctx.exception.http_status_code, 425)
		self.assertEqual(frappe.db.count("Sales Order", {"customer": self.customer}), before)

	def test_place_order_allowed_while_open(self):
		item = fx.make_stock_item(qty=10, rate=1000, item_name="Task5 Hours Open")
		self._add(item.item_code, 1)
		self._set_hours_window(-1, 1)  # opened an hour ago, closes in an hour

		result = order.place_order(address=self.address, idempotency_key="hours-open-1")
		self.assertIn("order", result)

	def test_replay_after_close_returns_prior_order(self):
		item = fx.make_stock_item(qty=10, rate=1000, item_name="Task5 Hours Replay")
		self._add(item.item_code, 1)
		placed = order.place_order(address=self.address, idempotency_key="hours-replay-1")

		self._set_hours_window(1, 2)  # store closes...
		replay = order.place_order(address=self.address, idempotency_key="hours-replay-1")
		self.assertEqual(replay["order"], placed["order"])
```

- [ ] **Step 2: Run the new tests to verify they fail**

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost run-tests --module grocery.tests.test_order
```

Expected: `test_place_order_blocked_while_closed` ERRORs with `AttributeError: module ... has no attribute 'StoreClosedError'`. (`test_place_order_allowed_while_open` and the replay test may pass already — the guard doesn't exist yet; that's fine, they pin behavior.)

- [ ] **Step 3: Implement `StoreClosedError` and the guard in `order.py`**

Add the import (after the existing `from grocery.api.address import _get_owned_address` line):

```python
from grocery.api.utils import store_hours
```

Add `"StoreClosedError"` to `__all__`:

```python
__all__ = [
	"OutOfStockError",
	"OutsideCoverageError",
	"StoreClosedError",
	"place_order",
	"my_orders",
	"detail",
	"changes",
]
```

Add the exception class directly below the `OutsideCoverageError` class:

```python
class StoreClosedError(frappe.ValidationError):
	"""``425 store_closed``: checkout attempted outside the working hours
	configured in App Settings (design doc 2026-07-17-store-working-hours).
	Server-authoritative — the app's own clock check is advisory only."""

	http_status_code = 425
```

In `place_order`, insert the guard between the idempotency-replay short-circuit and the zone resolution — i.e. change:

```python
	prior = _prior_result(user, customer, idempotency_key)
	if prior:
		return prior

	zone = _resolve_zone_for_address(address, customer)
```

to:

```python
	prior = _prior_result(user, customer, idempotency_key)
	if prior:
		return prior

	# Working-hours gate (server clock, site timezone). AFTER the replay
	# check: a retry of an order placed while open must still return its
	# result; only NEW orders are blocked outside the window.
	hours = store_hours()
	if not hours["is_open"]:
		frappe.throw(
			_("The store is currently closed. Working hours: {0}–{1}.").format(
				hours["open_time"][:5], hours["close_time"][:5]
			),
			exc=StoreClosedError,
			title=_("Store Closed"),
		)

	zone = _resolve_zone_for_address(address, customer)
```

Also update the `place_order` docstring's flow summary line to mention the gate — change `Role guard → required-key validation → idempotent-replay short-circuit →` to `Role guard → required-key validation → idempotent-replay short-circuit → working-hours gate (425 store closed) →`.

- [ ] **Step 4: Create the Arabic translation CSV**

Create `grocery/translations/ar.csv` (the `translations` directory does not exist yet — create it; Frappe picks up `<app>/translations/<lang>.csv` automatically):

```csv
"The store is currently closed. Working hours: {0}–{1}.","المتجر مغلق حالياً. ساعات العمل: {0}–{1}."
"Store Closed","المتجر مغلق"
```

Then clear caches so translations load:

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost clear-cache
```

- [ ] **Step 5: Run the order tests to verify they pass**

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost run-tests --module grocery.tests.test_order
```

Expected: `OK` — all order tests pass, including the three new ones.

- [ ] **Step 6: Commit (backend repo)**

```bash
cd /home/frappe/Frappe/grocery-bench/apps/grocery && git add grocery/api/order.py grocery/translations/ar.csv grocery/tests/test_order.py && git commit -m "feat(checkout): 425 StoreClosedError working-hours gate in place_order (+ar translation)"
```

---

### Task 5: `AppConfig` model — times + `isStoreOpenAt` (Flutter, TDD)

**Files:**
- Modify: `/home/frappe/Flutter/zad/lib/models/app_config.dart`
- Test: `/home/frappe/Flutter/zad/test/models/app_config_test.dart`

**Interfaces:**
- Consumes: `store_open_time` / `store_close_time` JSON keys from Task 3.
- Produces: `AppConfig.storeOpenTime` / `AppConfig.storeCloseTime` (`String?`, `"HH:MM:SS"`), `bool AppConfig.isStoreOpenAt(DateTime now)`. Used by Task 7's checkout page.

- [ ] **Step 1: Write the failing tests**

Append to the `main()` in `test/models/app_config_test.dart`, and add `'store_open_time': '09:00:00', 'store_close_time': '23:00:00'` to the existing full-payload map with `expect(config.storeOpenTime, '09:00:00'); expect(config.storeCloseTime, '23:00:00');` assertions, plus `storeOpenTime: '09:00:00', storeCloseTime: '23:00:00'` on the round-trip `const AppConfig(...)` with matching `expect(restored.storeOpenTime, original.storeOpenTime); expect(restored.storeCloseTime, original.storeCloseTime);`. Then add these new tests:

```dart
  group('isStoreOpenAt', () {
    final noon = DateTime(2026, 7, 17, 12);
    final lateNight = DateTime(2026, 7, 17, 23, 30);
    final earlyMorning = DateTime(2026, 7, 17, 1);

    test('unconfigured or half-configured is always open', () {
      expect(const AppConfig().isStoreOpenAt(noon), isTrue);
      expect(
        const AppConfig(storeOpenTime: '09:00:00').isStoreOpenAt(lateNight),
        isTrue,
      );
      expect(
        const AppConfig(storeCloseTime: '23:00:00').isStoreOpenAt(lateNight),
        isTrue,
      );
    });

    test('equal open and close is always open', () {
      const config = AppConfig(storeOpenTime: '09:00:00', storeCloseTime: '09:00:00');
      expect(config.isStoreOpenAt(earlyMorning), isTrue);
    });

    test('same-day window: open inside, closed outside', () {
      const config = AppConfig(storeOpenTime: '09:00:00', storeCloseTime: '23:00:00');
      expect(config.isStoreOpenAt(noon), isTrue);
      expect(config.isStoreOpenAt(lateNight), isFalse);
      expect(config.isStoreOpenAt(earlyMorning), isFalse);
      // Boundaries: inclusive open, exclusive close.
      expect(config.isStoreOpenAt(DateTime(2026, 7, 17, 9)), isTrue);
      expect(config.isStoreOpenAt(DateTime(2026, 7, 17, 23)), isFalse);
    });

    test('overnight window spans midnight', () {
      const config = AppConfig(storeOpenTime: '18:00:00', storeCloseTime: '02:00:00');
      expect(config.isStoreOpenAt(lateNight), isTrue);
      expect(config.isStoreOpenAt(earlyMorning), isTrue);
      expect(config.isStoreOpenAt(noon), isFalse);
    });

    test('malformed time strings read as always open', () {
      const config = AppConfig(storeOpenTime: 'bogus', storeCloseTime: '23:00:00');
      expect(config.isStoreOpenAt(noon), isTrue);
    });
  });
```

- [ ] **Step 2: Run the model tests to verify they fail**

```bash
cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/models/app_config_test.dart
```

Expected: compilation errors — `storeOpenTime` / `isStoreOpenAt` not defined.

- [ ] **Step 3: Implement the model changes**

In `lib/models/app_config.dart`: add the two constructor params, fields, JSON keys, and the helper. Complete diff of what changes:

```dart
  const AppConfig({
    this.splashImage,
    this.splashBgColor,
    this.splashDurationSec,
    this.appMinVersion,
    this.maintenanceMode = false,
    this.supportPhone,
    this.storeOpenTime,
    this.storeCloseTime,
  });
```

```dart
  final String? supportPhone;

  /// Daily working-hours window as the backend's `"HH:MM:SS"` strings
  /// (`content.get_app_config`); null = not configured = always open.
  final String? storeOpenTime;
  final String? storeCloseTime;
```

In `fromJson`, add:

```dart
      storeOpenTime: json['store_open_time'] as String?,
      storeCloseTime: json['store_close_time'] as String?,
```

In `toJson`, add:

```dart
        'store_open_time': storeOpenTime,
        'store_close_time': storeCloseTime,
```

Add at the end of the class:

```dart
  /// Whether the store is open at [now] — same window semantics as the
  /// backend's `store_hours()`: unset/half-set/equal → always open;
  /// `open < close` → open when `open <= now < close`; `open > close` →
  /// overnight window (open when `now >= open` OR `now < close`). The
  /// caller supplies [now] (device clock in the app, fixed instants in
  /// tests); the server clock stays authoritative at `place_order`.
  bool isStoreOpenAt(DateTime now) {
    final open = _secondsOfDay(storeOpenTime);
    final close = _secondsOfDay(storeCloseTime);
    if (open == null || close == null || open == close) return true;
    final t = now.hour * 3600 + now.minute * 60 + now.second;
    if (open < close) return open <= t && t < close;
    return t >= open || t < close;
  }

  /// `"HH:MM[:SS]"` → seconds since midnight, or null when absent or
  /// malformed (malformed reads as "not configured", never as closed).
  static int? _secondsOfDay(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return h * 3600 + m * 60 + s;
  }
```

- [ ] **Step 4: Run the model tests to verify they pass**

```bash
cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/models/app_config_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit (Flutter repo)**

```bash
cd /home/frappe/Flutter/zad && git add lib/models/app_config.dart test/models/app_config_test.dart && git commit -m "feat(config): store working-hours fields + isStoreOpenAt window logic on AppConfig"
```

---

### Task 6: `StoreClosedException` — ApiClient 425 mapping (Flutter, TDD)

**Files:**
- Modify: `/home/frappe/Flutter/zad/lib/core/api/api_exceptions.dart`
- Modify: `/home/frappe/Flutter/zad/lib/core/api/api_client.dart`
- Test: `/home/frappe/Flutter/zad/test/core/api/api_client_test.dart`

**Interfaces:**
- Consumes: HTTP 425 responses produced by Task 4's `StoreClosedError`.
- Produces: `StoreClosedException` (extends `ApiException`), thrown by `ApiClient` on any 425. Caught by Task 7's checkout page.

- [ ] **Step 1: Write the failing test**

In `test/core/api/api_client_test.dart`, add inside the `group('error mapping', ...)` after the 417 test (the file's `_errorResponse` and `_guestTokenStore` helpers already exist):

```dart
    test('425 maps to StoreClosedException', () async {
      final dio = buildFakeDio(
        (options) => _errorResponse(options, 425, {'message': 'store_closed'}),
      );
      final client = ApiClient(dio: dio, tokenStore: _guestTokenStore(), baseUrl: 'http://test.local');

      await expectLater(
        client.post('grocery.api.order.place_order'),
        throwsA(isA<StoreClosedException>()),
      );
    });
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/core/api/api_client_test.dart
```

Expected: compilation error — `StoreClosedException` undefined.

- [ ] **Step 3: Implement**

In `lib/core/api/api_exceptions.dart`, add after `OutsideCoverageException`:

```dart
/// HTTP 425 — checkout attempted outside the store's working hours
/// (backend `StoreClosedError`).
class StoreClosedException extends ApiException {
  const StoreClosedException(super.message);
}
```

In `lib/core/api/api_client.dart` `_mapError`, add a case after `case 417`:

```dart
      case 425:
        return StoreClosedException(message);
```

- [ ] **Step 4: Run to verify it passes**

```bash
cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/core/api/api_client_test.dart
```

Expected: All tests pass.

- [ ] **Step 5: Commit (Flutter repo)**

```bash
cd /home/frappe/Flutter/zad && git add lib/core/api/api_exceptions.dart lib/core/api/api_client.dart test/core/api/api_client_test.dart && git commit -m "feat(api): map HTTP 425 to StoreClosedException"
```

---

### Task 7: Checkout closed-state UI + l10n (Flutter, TDD)

**Files:**
- Modify: `/home/frappe/Flutter/zad/lib/l10n/app_en.arb`
- Modify: `/home/frappe/Flutter/zad/lib/l10n/app_ar.arb`
- Modify (regenerated): `lib/l10n/app_localizations.dart`, `lib/l10n/app_localizations_en.dart`, `lib/l10n/app_localizations_ar.dart`
- Modify: `/home/frappe/Flutter/zad/lib/features/checkout/checkout_page.dart`
- Modify: `/home/frappe/Flutter/zad/test/features/checkout/checkout_page_test.dart`

**Interfaces:**
- Consumes: `AppConfig.isStoreOpenAt` / `storeOpenTime` / `storeCloseTime` (Task 5), `StoreClosedException` (Task 6), existing `AppConfigStore` provider (already in `app.dart` and in `homeTestProviders`).
- Produces: `CheckoutPage({Key? key, DateTime Function() clock = DateTime.now})`; notice widget under `Key('storeClosedNotice')`; l10n getters `checkoutStoreClosed` and `checkoutStoreClosedHours(String open, String close)`.

- [ ] **Step 1: Add the l10n strings**

In `lib/l10n/app_en.arb`, after the `"checkoutPlaceOrder"` entry, add:

```json
  "checkoutStoreClosed": "The store is currently closed. Please try again during working hours.",
  "checkoutStoreClosedHours": "The store is currently closed. Working hours: {open}–{close}",
  "@checkoutStoreClosedHours": {
    "placeholders": {
      "open": {
        "type": "String"
      },
      "close": {
        "type": "String"
      }
    }
  },
```

In `lib/l10n/app_ar.arb`, in the matching position, add:

```json
  "checkoutStoreClosed": "المتجر مغلق حالياً. يرجى المحاولة خلال ساعات العمل.",
  "checkoutStoreClosedHours": "المتجر مغلق حالياً. ساعات العمل: {open}–{close}",
```

Regenerate (generated files are committed in this repo):

```bash
cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter gen-l10n
```

Expected: exits 0; `git status` shows the three `app_localizations*.dart` files modified.

- [ ] **Step 2: Write the failing widget tests**

In `test/features/checkout/checkout_page_test.dart`:

Add imports at the top:

```dart
import 'package:zad/core/stores/app_config_store.dart';
import 'package:zad/features/auth/widgets/zad_primary_button.dart';
```

Extend the `buildCheckout` helper with two parameters and pass them through — change the signature to add:

```dart
    AppConfigStore? appConfigStore,
    DateTime Function()? clock,
```

change the `wrapPage(const CheckoutPage(), ...)` call to:

```dart
    return wrapPage(
      CheckoutPage(clock: clock ?? DateTime.now),
      routes: routes,
      providers: homeTestProviders(
        sessionStore: session,
        cartStore: cart,
        addressStore: addressStore,
        appConfigStore: appConfigStore,
        orderRepository: buildFakeOrderRepository(
          overrides: orderOverrides,
          capturedRequests: orderRequests,
        ),
      ),
    );
```

Add a config-store builder helper next to `_cartRepository`:

```dart
/// An [AppConfigStore] hydrated with [appConfig] via a fake network fetch.
Future<AppConfigStore> _loadedConfigStore(
  WidgetTester tester,
  Map<String, dynamic> appConfig,
) async {
  final store = AppConfigStore(
    repository: buildFakeContentRepository(appConfig: appConfig),
  );
  await tester.runAsync(store.load);
  return store;
}
```

(`buildFakeContentRepository` comes from `../../helpers.dart`, already imported.)

Add a new test group at the end of `main()`:

```dart
  group('store working hours', () {
    const hoursConfig = {
      'store_open_time': '09:00:00',
      'store_close_time': '23:00:00',
    };

    testWidgets('closed window shows notice and disables Place Order',
        (tester) async {
      final orderRequests = <RequestOptions>[];
      final page = await buildCheckout(
        tester,
        appConfigStore: await _loadedConfigStore(tester, hoursConfig),
        clock: () => DateTime(2026, 7, 17, 23, 30),
        orderRequests: orderRequests,
      );
      await tester.pumpWidget(page);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('storeClosedNotice')), findsOneWidget);
      final button = tester.widget<ZadPrimaryButton>(
        find.byKey(const Key('placeOrderButton')),
      );
      expect(button.onPressed, isNull);
      expect(orderRequests, isEmpty);
    });

    testWidgets('open window keeps checkout unchanged', (tester) async {
      final page = await buildCheckout(
        tester,
        appConfigStore: await _loadedConfigStore(tester, hoursConfig),
        clock: () => DateTime(2026, 7, 17, 12),
      );
      await tester.pumpWidget(page);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('storeClosedNotice')), findsNothing);
      final button = tester.widget<ZadPrimaryButton>(
        find.byKey(const Key('placeOrderButton')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('server 425 flips checkout to the closed state',
        (tester) async {
      // App thinks the store is open (no hours in config) — the server
      // disagrees (clock skew / stale config): 425 must surface the same
      // closed UI instead of a raw error.
      final page = await buildCheckout(
        tester,
        orderOverrides: (options) =>
            options.path.endsWith('order.place_order')
                ? Response(
                    requestOptions: options,
                    statusCode: 425,
                    data: {'message': 'store_closed'},
                  )
                : null,
      );
      await tester.pumpWidget(page);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('placeOrderButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('storeClosedNotice')), findsOneWidget);
      final button = tester.widget<ZadPrimaryButton>(
        find.byKey(const Key('placeOrderButton')),
      );
      expect(button.onPressed, isNull);
    });
  });
```

- [ ] **Step 3: Run the checkout tests to verify the new ones fail**

```bash
cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/features/checkout/checkout_page_test.dart
```

Expected: compilation error — `CheckoutPage` has no `clock` parameter.

- [ ] **Step 4: Implement the checkout page changes**

In `lib/features/checkout/checkout_page.dart`:

Add imports:

```dart
import '../../core/stores/app_config_store.dart';
import '../../models/app_config.dart';
```

Change the widget class to accept the clock:

```dart
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, this.clock = DateTime.now});

  /// "Now" source for the working-hours check — injectable so widget
  /// tests pin the instant; production uses the device clock. The server
  /// re-checks with its own clock at `place_order` either way.
  final DateTime Function() clock;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}
```

In `_CheckoutPageState`, add a field below `bool _placing = false;`:

```dart
  /// Set when `place_order` came back 425 — the server's clock says
  /// closed even if the device clock disagrees; server wins.
  bool _serverSaysClosed = false;
```

In `_placeOrder`, add a catch clause between the `OutsideCoverageException` and `ApiException` clauses:

```dart
    } on StoreClosedException catch (_) {
      if (!mounted) return;
      setState(() {
        _placing = false;
        _serverSaysClosed = true;
      });
    } on ApiException catch (e) {
```

(`StoreClosedException` resolves via the existing `api_exceptions.dart` import.)

In `_buildBody`, compute the closed state after `final selected = _effectiveAddress(addressStore);`:

```dart
    final config = context.watch<AppConfigStore>().config;
    final storeClosed =
        _serverSaysClosed || !config.isStoreOpenAt(widget.clock());
```

Replace the bottom CTA `Padding` block:

```dart
        Padding(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: ZadPrimaryButton(
            key: const Key('placeOrderButton'),
            label: l10n.checkoutPlaceOrder,
            loading: _placing,
            onPressed: selected == null ? null : () => _placeOrder(selected),
          ),
        ),
```

with:

```dart
        Padding(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (storeClosed) ...[
                Container(
                  key: const Key('storeClosedNotice'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF3E1),
                    borderRadius: BorderRadius.circular(ZadRadii.tile),
                  ),
                  child: Row(
                    children: [
                      const Icon(Iconsax.clock, size: 20, color: Color(0xFFB7791F)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _closedMessage(l10n, config),
                          style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              ZadPrimaryButton(
                key: const Key('placeOrderButton'),
                label: l10n.checkoutPlaceOrder,
                loading: _placing,
                onPressed: (selected == null || storeClosed)
                    ? null
                    : () => _placeOrder(selected),
              ),
            ],
          ),
        ),
```

Add the message helpers to `_CheckoutPageState` (after `_effectiveAddress`):

```dart
  /// Closed-notice copy: with the window when the config carries it,
  /// generic otherwise (e.g. a 425 against a stale cached config).
  String _closedMessage(AppLocalizations l10n, AppConfig config) {
    final open = config.storeOpenTime;
    final close = config.storeCloseTime;
    if (open == null || close == null) return l10n.checkoutStoreClosed;
    return l10n.checkoutStoreClosedHours(_hhmm(open), _hhmm(close));
  }

  /// `"HH:MM:SS"` → `"HH:MM"` for display.
  String _hhmm(String raw) => raw.length >= 5 ? raw.substring(0, 5) : raw;
```

Also extend the class doc comment's error-contract sentence: change `anything else → SnackBar, the button stays armed with the same key.` to `425 (store closed) → the working-hours notice replaces the armed CTA; anything else → SnackBar, the button stays armed with the same key.`

- [ ] **Step 5: Run the checkout tests to verify they pass**

```bash
cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/features/checkout/
```

Expected: All checkout tests pass (new group + all pre-existing ones).

- [ ] **Step 6: Commit (Flutter repo)**

```bash
cd /home/frappe/Flutter/zad && git add lib/l10n/ lib/features/checkout/checkout_page.dart test/features/checkout/checkout_page_test.dart && git commit -m "feat(checkout): working-hours closed notice + disabled CTA, 425 server override"
```

---

### Task 8: Full verification + dev-site cleanup

**Files:** none new — verification only.

- [ ] **Step 1: Run the full Flutter suite and analyzer**

```bash
cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter analyze && ~/.flutter-sdk/bin/flutter test
```

Expected: `No issues found!` and all tests pass (471 pre-existing + the new ones).

- [ ] **Step 2: Run the touched backend modules once more**

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost run-tests --module grocery.tests.test_store_hours && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost run-tests --module grocery.tests.test_content && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost run-tests --module grocery.tests.test_order
```

Expected: `OK` three times.

- [ ] **Step 3: Restore the dev site after test pollution**

Backend test runs commit a test WASender token into live settings and unhide test data (known site quirk). Restore:

```bash
cd /home/frappe/Frappe/grocery-bench && env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost execute grocery.seed.run
cd /home/frappe/Frappe/grocery-bench && echo 'doc = frappe.get_doc("WASender Settings"); doc.api_token = ""; doc.validate_before_send = 0; doc.save(); frappe.db.commit()' | env PATH="$HOME/.local/bin:$PATH" bench --site grocery.localhost console
```

Expected: seed completes; console exits without traceback.

- [ ] **Step 4: End-to-end smoke over HTTP (server enforcement + config exposure)**

With the bench serving (`env PATH="$HOME/.local/bin:$PATH" bench serve --port 8000` if not already running):

```bash
curl -s http://grocery.localhost:8000/api/method/grocery.api.content.get_app_config | python3 -m json.tool
```

Expected: JSON containing `store_open_time`, `store_close_time`, `store_is_open` (null/null/true on the unconfigured dev site). Then set a closed window in the desk (or via console: `frappe.db.set_single_value("App Settings", "store_open_time", ...)` + commit), re-curl to see `store_is_open: false`, and **restore both fields to empty afterwards** the same way.

- [ ] **Step 5: Verify clean working trees**

```bash
cd /home/frappe/Frappe/grocery-bench/apps/grocery && git status --short; cd /home/frappe/Flutter/zad && git status --short
```

Expected: no unstaged changes from this feature remaining in either repo (the zad repo's pre-existing unrelated modifications — launcher icons, locale store, etc. — stay as they were).
