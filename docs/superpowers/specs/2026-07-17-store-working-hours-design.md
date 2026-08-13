# Store Working Hours — Design

**Date:** 2026-07-17
**Status:** Approved
**Scope:** Frappe backend (`grocery` app at `~/Frappe/grocery-bench/apps/grocery`) + Flutter app (`~/Flutter/zad`)

## Problem

The store has physical working hours, but the app currently accepts basket
submission (checkout) at any time of day. Admins need to set an open time and
a close time from the backend, and customers must not be able to place an
order outside that window.

## Decisions (from brainstorming)

- **Schedule shape:** one daily window — a single open time + close time that
  applies every day. No per-day schedule, no manual "closed now" override
  (YAGNI; `maintenance_mode` already exists for emergencies).
- **UX:** server-side block is authoritative; the checkout page additionally
  shows a "store closed" notice and disables the submit button so users are
  not surprised by an error after tapping.
- **Wiring:** Approach A — fields on `App Settings`, a guard in
  `order.place_order`, exposure via `content.get_app_config`. No new
  endpoint, no Sales Order hook.

## Backend

### Data model

Two new optional fields on the **App Settings** single doctype, placed next
to `maintenance_mode`:

| fieldname          | fieldtype | label            |
|--------------------|-----------|------------------|
| `store_open_time`  | Time      | Store Open Time  |
| `store_close_time` | Time      | Store Close Time |

Semantics:

- **Both blank → always open.** Existing sites behave unchanged after
  `bench migrate`.
- **One blank → always open.** A half-configured window is treated as not
  configured (fail open, never lock the store by accident).
- **`open == close` → always open** (read as a 24-hour window).
- **`open < close`** → same-day window: open when `open ≤ now < close`
  (e.g. 09:00–23:00).
- **`open > close`** → overnight window: open when `now ≥ open` **or**
  `now < close` (e.g. 18:00–02:00).

### Open/closed helper

A shared helper in `grocery/api/utils.py` (next to the other shared guards):

```python
def store_hours() -> dict:
    """{"is_open": bool, "open_time": "HH:MM:SS"|None, "close_time": "HH:MM:SS"|None}"""
```

- Uses the **server clock in the site timezone** via
  `frappe.utils.now_datetime()`.
- Implements the window semantics above.
- Time values are returned as `"HH:MM:SS"` strings (or `None` when unset) so
  they serialize cleanly through JSON.

### Enforcement in `place_order`

In `grocery/api/order.py::place_order`, the guard runs **after** the
idempotency-replay short-circuit and **before** zone resolution / stock
locking:

- A retry of an order placed while the store was open still returns the prior
  result — replays never create orders, so they are never blocked.
- A **new** order outside working hours raises
  `frappe.throw(_("The store is currently closed. Working hours: {0}–{1}."))`
  with the open/close times formatted as `HH:MM`, via a dedicated
  `StoreClosedError(frappe.ValidationError)` with `http_status_code = 425`
  — 417 is already the outside-coverage contract and the app maps errors by
  status code, so store-closed needs its own status. The message goes
  through `_()` so Arabic sessions receive Arabic (add the string to the
  grocery app's Arabic translation CSV, created at
  `grocery/translations/ar.csv`).

### Exposure in `get_app_config`

`grocery/api/content.py::get_app_config` adds three keys:

```json
{
  "store_open_time": "09:00:00" | null,
  "store_close_time": "23:00:00" | null,
  "store_is_open": true
}
```

`store_is_open` is a server-computed snapshot (useful for tests and instant
use); the app recomputes locally from the times so it never goes stale.

### Backend tests

- `tests/test_content.py`: the three new keys appear in `get_app_config`,
  with correct values for configured and unconfigured settings.
- `tests/test_order.py`:
  - closed window → `place_order` throws, no Sales Order created;
  - open window → order proceeds;
  - overnight window (`open > close`) both sides of midnight;
  - blank fields → always open;
  - idempotent replay while closed returns the prior order instead of
    throwing.
- Tests freeze/patch the clock rather than depending on wall time.

## Flutter app

### Model (`lib/models/app_config.dart`)

`AppConfig` gains:

- `storeOpenTime` / `storeCloseTime` (`String?`, `"HH:MM:SS"` as sent by the
  backend), parsed in `fromJson` and included in `toJson` so the existing
  shared-preferences last-good-config cache round-trips them.
- `bool isStoreOpenAt(DateTime now)` — same window semantics as the backend
  helper (blank/half-configured/equal → open; same-day; overnight). Malformed
  time strings read as "not configured" (open) rather than throwing.

`store_is_open` from the payload is **not** stored — the client always
computes from the times + device clock, so the state can't go stale while
the app stays open across the boundary.

### Checkout page (`lib/features/checkout/checkout_page.dart`)

- On build, compute `isStoreOpenAt(DateTime.now())` from the
  `AppConfigStore` config.
- When closed: show a notice card — "Store closed — working hours
  HH:MM–HH:MM" (localized en/ar, RTL-safe) — and disable
  `placeOrderButton`.
- When the server rejects anyway (device clock skew / stale config): the
  `ApiClient` maps HTTP 425 to a new `StoreClosedException`; the checkout
  page catches it and flips into the same closed state (notice shown,
  button disabled). Server is always authoritative.

### Localization

New strings in `lib/l10n/app_en.arb` + `app_ar.arb` for the closed notice
(with open/close time placeholders), regenerated localizations.

### Flutter tests

- `test/` model tests: JSON parse/serialize of the new fields;
  `isStoreOpenAt` covering blank, half-configured, equal, same-day,
  overnight, and boundary instants (`now == open`, `now == close`).
- Checkout widget test: a closed config shows the notice and disables the
  submit button; an open config leaves checkout unchanged. The page reads
  "now" via an injectable clock (constructor parameter defaulting to
  `DateTime.now`) so tests are deterministic.

## Error handling summary

| Case | Behavior |
|------|----------|
| Fields unset / half-set | Store always open (backward compatible) |
| Checkout while closed (app knows) | Button disabled + notice; no request sent |
| Checkout while closed (clock skew) | Server throws translated 425 `StoreClosedError`; app maps it to `StoreClosedException` and shows the closed notice |
| Idempotent replay after close | Prior order returned, not blocked |
| Config fetch fails at boot | Cached last-good times used; else bundled default (always open) — server still enforces |

## Out of scope

- Per-weekday schedules, holiday calendars.
- Blocking browsing/cart edits while closed (only submission is blocked).
- App-wide closed banners outside the checkout page.
- Push notifications when the store reopens.
