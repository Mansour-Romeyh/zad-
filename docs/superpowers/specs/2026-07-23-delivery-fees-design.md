# Delivery Fees setup + checkout display — Design

**Date:** 2026-07-23
**Status:** Approved (design), pending spec review
**Repos touched:** `zad` (Flutter app) and `grocery` app in `~/Frappe/grocery-bench`

## Problem

The app has no delivery fee. At checkout the order summary shows Subtotal and
Total as identical numbers (`net_total == grand_total`), because the cart
Quotation and the resulting Sales Order carry no shipping/delivery charge. The
business needs to charge a delivery fee, collect it as part of the cash-on-
delivery total, and show it to the customer before they place the order.

The user wants: (1) a delivery-fee setup in the backend, and (2) the fee shown
on the checkout page.

## Decisions (from brainstorming)

- **Fee model:** a **global flat fee waived above a threshold** — a single
  `delivery_fee` amount, set to 0 when the subtotal reaches
  `free_delivery_over` ("free over N"). No per-zone fee. Both values live on
  the `App Settings` singleton alongside the other global config (store hours,
  currency, warehouse).
- **Real charge, not cosmetic:** the fee is added to the **Sales Order
  `grand_total`** at `place_order` (a "Delivery Charges" line), so it is the
  amount the driver collects COD and what appears in order history/detail. The
  server computes it authoritatively; the app's checkout display is advisory —
  the same authority split already used for store working-hours.
- **No "free delivery" nudge** ("add N more for free delivery") in this scope.
- **Delivery line shown in both checkout and order detail** (order detail's
  `grand_total` already reflects the charge; the explicit line keeps the
  breakdown legible).

## The fee rule (one definition, applied in two places)

```
fee(net_total):
    if delivery_fee <= 0:                                  return 0   # fee disabled
    if free_delivery_over > 0 and net_total >= free_delivery_over:
                                                           return 0   # waived (free)
    return delivery_fee
```

- `net_total` is the **item subtotal** — the cart/SO `net_total`, before any
  charge. The threshold compares against the subtotal, not the post-fee total.
- `free_delivery_over <= 0` (unset) ⇒ threshold disabled ⇒ the fee is always
  charged.
- `delivery_fee <= 0` (unset) ⇒ delivery is always free.
- `>=` is the free boundary: subtotal *at or above* the threshold ⇒ free.

This rule is implemented once in Python (backend, authoritative) and once in
Dart (app, advisory display). Both must agree; they are covered by matching
unit tests so a change to one without the other is caught.

## Backend design (`grocery` app)

### App Settings — new "Delivery" fields

Add to the `App Settings` singleton (`grocery/grocery/doctype/app_settings/`):

- `delivery_fee` — Currency (IQD), default 0.
- `free_delivery_over` — Currency (IQD), default 0 (disabled).
- `delivery_charge_account` — Link → Account, optional. The charge's account
  head; when blank the code falls back to the company's
  `Freight and Forwarding Charges - {abbr}` account (which ERPNext creates by
  default — confirmed present as `Freight and Forwarding Charges - ZG`).

A "Delivery" `Section Break` groups the two amounts and the account for
admin clarity.

`app_settings.py` `validate()`:

- Reject negative `delivery_fee` / `free_delivery_over`.
- If `delivery_fee > 0`, the resolved charge account (configured, else the
  default Freight account for the settings' company) **must exist** — throw a
  clear `ValidationError` at save otherwise. This front-loads the only
  misconfiguration that could otherwise fail a live checkout, so `place_order`
  can trust the config. The save-time company is resolved best-effort from
  `default_warehouse`'s `company`, else the global default company; this
  single-company deployment (Zad Grocery) makes them the same. `place_order`
  itself resolves the account against the **actual SO company** (the zone
  warehouse's `company`, which `_build_sales_order` already reads) rather than
  re-deriving it — so the account always matches the order's company even if a
  future zone points at a different one.

### `content.get_app_config` — expose the fee to the app

Add two fields to the returned dict:

- `"delivery_fee": flt(settings.delivery_fee)`
- `"free_delivery_over": flt(settings.free_delivery_over)`

Guest-OK like the rest of the config; the app fetches and caches it in
`AppConfigStore` (already the source of store hours, terms URL, etc.).

### `place_order` — add the charge to the Sales Order

In `grocery/api/order.py` `_build_sales_order` (or a small helper it calls):

- Compute `fee = delivery_fee_for(flt(cart.net_total))` using the rule above,
  reading `delivery_fee` / `free_delivery_over` from `App Settings`.
- If `fee > 0`, append one **Sales Taxes and Charges** row to the Sales Order:
  ```python
  {
      "charge_type": "Actual",
      "account_head": <resolved delivery_charge_account or Freight-for-company>,
      "description": _("Delivery Charges"),
      "tax_amount": fee,
  }
  ```
  ERPNext's `calculate_taxes_and_totals` then sets
  `grand_total = net_total + fee`. `total_taxes_and_charges` equals the fee.
- If `fee <= 0`, add no row — `grand_total` stays `== net_total` exactly as
  today.

Notes:
- The threshold is evaluated on `cart.net_total` (the item subtotal captured
  before the SO is built), so a large basket that crosses the threshold gets
  free delivery.
- **Idempotency is unaffected:** the fee is derived deterministically and the
  charge is written as part of the same SO build. A replayed `place_order`
  returns the already-stored order (with its already-included fee) via the
  existing idempotency path; it never re-computes or double-charges.
- Account resolution lives in one helper
  (`_delivery_charge_account(company)`): configured account → else
  `Freight and Forwarding Charges - {abbr}` → else raise (guarded already by
  the save-time validation, so this is defence in depth).

### `order.detail` — surface the fee in the breakdown

Add `"delivery_fee": flt(so.total_taxes_and_charges)` to the `totals` dict in
`order.detail`. `net_total` and `grand_total` are already returned;
`grand_total` now includes the fee automatically. `order.my_orders` is
unchanged — its per-card `grand_total` already reflects the charge.

## App design (Flutter `zad`)

### `AppConfig` (`lib/models/app_config.dart`)

- Add `final double? deliveryFee;` and `final double? freeDeliveryOver;`.
- Parse in `fromJson` (`toDouble(json['delivery_fee'])`,
  `toDouble(json['free_delivery_over'])`) and round-trip in `toJson` so the
  cached config in `shared_preferences` keeps them.
- Add a pure method mirroring the backend rule:
  ```dart
  double deliveryFeeFor(double netTotal) {
    final fee = deliveryFee ?? 0;
    final threshold = freeDeliveryOver ?? 0;
    if (fee <= 0) return 0;
    if (threshold > 0 && netTotal >= threshold) return 0;
    return fee;
  }
  ```
  (Analogous to the existing `isStoreOpenAt` — pure, unit-testable, the app's
  advisory copy of a server-authoritative rule.)

### `CartTotals` (`lib/data/cart_repository.dart`)

- Add `final double deliveryFee;` (default 0), parsed from
  `toDouble(json['delivery_fee']) ?? 0`. Used by `order.detail`; the cart
  endpoints simply omit the field and it defaults to 0.

### Checkout summary (`lib/features/checkout/checkout_page.dart`)

- `_SummaryCard` gains the `AppConfig` (passed from `_buildBody`, which already
  `watch`es `AppConfigStore`).
- Between the Subtotal row and the Total row, insert a **Delivery** row:
  - `fee = config.deliveryFeeFor(totals.netTotal)`.
  - Right value: `formatPrice(fee, lang)` when `fee > 0`, else the localized
    "Free" (`l10n.checkoutDeliveryFree`).
- The **Total** row becomes `formatPrice(totals.netTotal + fee, lang)` instead
  of `totals.grandTotal` (the cart Quotation carries no charge, so its
  `grand_total == net_total`; the app adds the computed fee for display, and
  the server produces the identical figure on the SO).

### Order detail totals (`lib/features/orders/order_detail_page.dart`)

- Insert the same Delivery row using `detail.totals.deliveryFee`, between
  Subtotal and Total. The Total already equals `grand_total` (fee included) —
  no change to the Total line needed there.

### Localization (`lib/l10n/`)

- `checkoutDelivery` — "Delivery" / "التوصيل".
- `checkoutDeliveryFree` — "Free" / "مجاني".

## Testing

**Backend (`grocery`, pytest):**
- `place_order` adds a "Delivery Charges" line and `grand_total == net_total +
  delivery_fee` when the subtotal is below the threshold.
- Subtotal at/above `free_delivery_over` ⇒ no charge, `grand_total ==
  net_total`.
- `delivery_fee == 0` ⇒ no charge.
- `get_app_config` returns `delivery_fee` and `free_delivery_over`.
- `App Settings.validate` rejects a negative fee and (fee > 0 with an
  unresolvable account) — accepts fee > 0 when the Freight account exists.
- `order.detail` totals include `delivery_fee` matching the charge.

**App (`zad`, flutter test):**
- `AppConfig.deliveryFeeFor`: fee charged below threshold; 0 at/above
  threshold; threshold disabled (0) always charges; fee 0 always free.
- Checkout widget: Delivery row renders the fee and the Total equals subtotal +
  fee; shows "Free" and Total == subtotal when the basket is over the
  threshold; no Delivery amount surprise when fee is 0.
- Order detail widget: Delivery row renders from `totals.deliveryFee`.

## Setup / rollout

After deploy, an admin opens **App Settings → Delivery** and sets
`delivery_fee` (e.g. 2000 IQD) and `free_delivery_over` (e.g. 25000 IQD);
`delivery_charge_account` can stay blank to use the default Freight account.
With `delivery_fee` left at 0, behaviour is exactly as today (no fee, Subtotal
== Total), so the change is safe to ship before the amounts are configured.

## Out of scope

- Per-zone delivery fees.
- "Add N more for free delivery" progress nudge.
- Time-/distance-based or dynamic delivery pricing.
- Any change to the payment method (COD stays the only method).
