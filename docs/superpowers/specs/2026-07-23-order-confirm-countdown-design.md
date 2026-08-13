# 30-second cancel window before placing the order — Design

**Date:** 2026-07-23
**Status:** Approved (design), pending spec review
**Repos touched:** `zad` (Flutter app) only — **no backend changes**

## Problem

After a customer taps `تأكيد الطلب` (Place Order) on checkout, the app calls
`order.place_order` immediately: a submitted Sales Order is created, stock is
reserved, and the app jumps straight to the success page. There is no grace
period — the customer cannot pull back a mis-tap, and the backend offers no
customer-facing cancel (cancellation is support-only). We want to give the
customer ~30 seconds to cancel or go edit their basket before the order is
actually sent.

## Decisions (from brainstorming)

- **Mechanism: client-side hold ("undo send").** Tapping Confirm does *not*
  call `place_order`. It opens a countdown; `place_order` fires only when the
  countdown elapses or the user chooses to place now. Cancelling during the
  window means no order was ever created — no stock locked, no cancelled-order
  records, and **zero backend work**.
- **On timeout: auto-place.** When the countdown hits 0 with no action, the
  order is placed automatically (matches "you have 30s to cancel"). A "Place
  now" button lets impatient users skip the wait.
- **Presentation: a dedicated countdown screen** (not an undo banner), with a
  large countdown and Cancel / Edit cart / Place now actions.
- **"Edit cart" returns the user to the basket** to change items.
- **Window: 30 seconds.**

## Flow

```
Checkout ──tap تأكيد الطلب──▶ OrderConfirmCountdownPage (pushed)
                                   │
             ┌─────────────────────┼───────────────────────────┐
             │ Cancel / back       │ Place now / timeout at 0    │ Edit cart
             ▼                     ▼                             ▼
   pop → back to Checkout   pop(place) → Checkout runs        pop(edit) → Checkout
   (nothing placed)         _placeOrder(address) → success/    pops itself → back
                            error dialogs (unchanged)          to basket tab
```

Nav stack today is `HomeShell(basket tab) → Checkout(pushed)`; the countdown is
pushed on top. So popping the countdown returns to Checkout, and popping
Checkout too returns to the basket tab — that is what "Edit cart" does.

## Component — `OrderConfirmCountdownPage`

**File:** `lib/features/checkout/order_confirm_countdown_page.dart`

A self-contained `StatefulWidget` with no repository dependency — it is a pure
timer + intent gate, so it is trivially testable and reusable.

```dart
enum ConfirmCountdownResult { place, cancel, edit }

class OrderConfirmCountdownPage extends StatefulWidget {
  const OrderConfirmCountdownPage({this.seconds = 30, super.key});
  final int seconds;
}
```

- A `Timer.periodic(1s)` decrements `_remaining` from `widget.seconds` to 0.
  At 0 it pops with `ConfirmCountdownResult.place`.
- UI: a large remaining-seconds number centred in a `CircularProgressIndicator`
  driven by `_remaining / widget.seconds`, a "seconds to cancel" caption, and a
  title "Placing your order…". Colours from `ZadColors`, radii from `ZadRadii`.
- Actions:
  - **Cancel** → `Navigator.pop(context, ConfirmCountdownResult.cancel)`
  - **Edit cart** → `Navigator.pop(context, ConfirmCountdownResult.edit)`
  - **Place now** → `Navigator.pop(context, ConfirmCountdownResult.place)`
- **System back = cancel:** a hardware/gesture back pops the route with a `null`
  result, which Checkout's `switch` treats as cancel (nothing placed) — no
  special `PopScope` handling needed. The timer never places on its own except
  by explicitly popping `place` at 0.
- **Reduce-motion:** when `MediaQuery.of(context).disableAnimations` is true the
  ring shows static progress (no implicit animation); the number still ticks.
- **Backgrounding safety:** implement `WidgetsBindingObserver`; on
  `AppLifecycleState.paused`/`inactive` **pause** the timer, on `resumed`
  **resume** it — so the app never auto-places an order while it is not in the
  foreground. Timer and observer are removed in `dispose`.

## Checkout wiring

**File:** `lib/features/checkout/checkout_page.dart`

The CTA (`checkout_page.dart:328`) changes its `onPressed` from
`() => _placeOrder(selected)` to `() => _confirmOrder(selected)`:

```dart
Future<void> _confirmOrder(AddressModel address) async {
  if (_placing) return;
  final result = await Navigator.push<ConfirmCountdownResult>(
    context,
    MaterialPageRoute(builder: (_) => const OrderConfirmCountdownPage(seconds: 30)),
  );
  if (!mounted) return;
  switch (result) {
    case ConfirmCountdownResult.place:
      await _placeOrder(address); // existing logic, untouched
    case ConfirmCountdownResult.edit:
      Navigator.pop(context); // leave checkout → back to the basket tab
    case ConfirmCountdownResult.cancel:
    case null: // system back / dismissed
      break; // stay on checkout, nothing placed
  }
}
```

`_placeOrder` and every outcome it already handles — success → `OrderSuccessPage`,
`OutOfStockException` / `OutsideCoverageException` / `StoreClosedException`
dialogs, network errors, and the idempotency key — are **reused unchanged**. The
countdown is a gate in front of `_placeOrder`, not a rewrite of it.

## Localization (`lib/l10n/`)

New keys in both `app_en.arb` and `app_ar.arb`, then `flutter gen-l10n`:

| Key | English | Arabic |
|-----|---------|--------|
| `confirmCountdownTitle` | Placing your order… | جارٍ إرسال طلبك… |
| `confirmCountdownCaption` | seconds to cancel | ثانية للإلغاء |
| `confirmCountdownPlaceNow` | Place now | إرسال الآن |
| `confirmCountdownEditCart` | Edit cart | تعديل السلة |

`Cancel` reuses the existing `l10n.cancel`.

## Testing

**`test/features/checkout/order_confirm_countdown_page_test.dart` (new):**
- Renders the initial seconds and caption.
- Tapping Cancel pops with `ConfirmCountdownResult.cancel`.
- Tapping Edit cart pops with `ConfirmCountdownResult.edit`.
- Tapping Place now pops with `ConfirmCountdownResult.place`.
- Letting the clock run out (`tester.pump(Duration(seconds: 30))`) pops with
  `place`.
- A system back (pop) resolves to `cancel`.
- Backgrounding (`AppLifecycleState.paused`) then advancing time does **not**
  place; resuming continues the countdown.

**Extend `test/features/checkout/checkout_page_test.dart`:**
- Tapping `تأكيد الطلب` pushes the countdown and does **not** call `place_order`
  yet (no `order.place_order` request captured).
- A `place` result from the countdown fires `place_order` exactly once.
- A `cancel` result leaves the user on checkout with no `place_order` call.

## Out of scope

- Any server-side order cancellation / customer-cancel endpoint (explicitly the
  path we avoided by holding client-side).
- Changing the reservation TTL / expiry cron (`grocery.tasks.expiry`).
- Editing an order after it is actually placed (still support-only).
