# "Order placed" confirmation sound + haptic — design

## Problem

When a customer taps **Place order** and the order is created, the app
silently replaces the screen with `OrderSuccessPage`. There is no audible or
tactile confirmation, so a user who isn't looking closely (or on a slow
network) has no immediate signal that the order actually went through. The app
currently has **zero** audio or haptic feedback anywhere.

## Goal

Play a short, distinctive confirmation **sound** ("pip") plus a subtle
**haptic** the moment an order is successfully created, so the user *hears/feels*
that it worked — gated by a user setting and the device's silent mode.

## Non-goals

- No sound anywhere else (add-to-cart, navigation, errors, etc.).
- No staff/store "new order arrived" alert — this is the **customer**
  confirming their own checkout.
- No per-sound volume control, no sound picker, no notification-channel sound.
- No new sound on retries: the checkout idempotency guard already makes
  `_placeOrder` fire once per real order, so the feedback fires once too.

## Design decisions (from brainstorming)

- **Method:** bundled asset played via `audioplayers` (a real, consistent pip),
  not Flutter's limited built-in `SystemSound`. This adds a package under a
  freeze exception — wrapped in an injectable service, mirroring the
  `geolocator` / `LocationService` precedent so only one file touches the plugin.
- **Extras (all requested):** subtle haptic vibration; a mute toggle in
  settings; respect the phone's silent mode.
- **One toggle gates both** sound and haptic. Silent mode gates only the sound
  (haptic still fires in vibrate mode). Default **ON**.
- **Best-effort:** a failed sound/haptic must never affect the order
  confirmation or navigation — fire-and-forget, all errors swallowed (same rule
  as `resolveZone`).

## Architecture

### 1. `audioplayers` dependency — edit `pubspec.yaml`
Add `audioplayers` with a freeze-exception comment identical in spirit to the
`geolocator` note (names the single owner file). Declare the audio asset dir
under `flutter: assets:`.

### 2. Sound asset — new `assets/audio/order_placed.wav`
A short (~150–250 ms), soft two-tone pip, mono, small (~15–25 KB). Generated as
a plain PCM WAV (widely supported by `audioplayers`). Swappable later — nothing
depends on its internals.

### 3. `OrderFeedbackService` — new `lib/core/audio/order_feedback_service.dart`
Injectable abstraction (like `LocationService`):

```dart
abstract class OrderFeedbackService {
  Future<void> playOrderPlaced();
}
```

- **`AudioOrderFeedbackService`** (real, the only file importing `audioplayers`):
  holds one reusable `AudioPlayer`; configures an `AudioContext` that **respects
  the device silent switch** — iOS `AVAudioSessionCategory.ambient`, Android
  `AndroidUsageType.notification` (so the OS silences it under silent/DND).
  `playOrderPlaced()` plays `AssetSource('audio/order_placed.wav')` and calls
  `HapticFeedback.mediumImpact()`. Wrapped in try/catch → never throws.
- **`NoopOrderFeedbackService`** for tests/fakes: a `FakeOrderFeedbackService`
  in tests records `playOrderPlaced` call count.
- Real impl is thin and NOT unit-tested (same as `GeolocatorLocationService`);
  behavior is verified through the abstraction.

### 4. `SettingsStore` — new `lib/core/stores/settings_store.dart`
`shared_preferences`-backed `ChangeNotifier`, modeled on `LocaleStore`:

- key `zad.orderSoundEnabled`; `bool get orderSoundEnabled` (default `true`).
- `Future<void> load()` — best-effort restore at boot, never throws.
- `Future<void> setOrderSoundEnabled(bool)` — updates, `notifyListeners()`,
  best-effort persist.

`shared_preferences` is already a dependency — no new package for the toggle.

### 5. Checkout wiring — edit `lib/features/checkout/checkout_page.dart`
In `_placeOrder`, capture from `context.read` **before** the await (alongside
`repository`/`cart`): `settings = context.read<SettingsStore>()`,
`feedback = context.read<OrderFeedbackService>()`. On success, after the
cart-refresh line and before `Navigator.pushReplacement`:

```dart
if (settings.orderSoundEnabled) {
  feedback.playOrderPlaced(); // fire-and-forget; never awaited
}
```

### 6. Profile toggle — edit `lib/features/profile/profile_tab.dart`
A `SwitchListTile` row ("Order confirmation sound") in the authed profile
settings section, `value: context.watch<SettingsStore>().orderSoundEnabled`,
`onChanged: (v) => context.read<SettingsStore>().setOrderSoundEnabled(v)`. Keyed
`Key('profileOrderSoundToggle')`.

### 7. DI — edit `lib/app.dart` / `lib/main.dart`
Provide `SettingsStore` (call `load()` at boot like `LocaleStore`) and
`OrderFeedbackService` (real impl in the app, fake substituted in tests) above
`MaterialApp`, following the existing provider wiring.

### 8. Localization — edit `lib/l10n/app_ar.arb`, `lib/l10n/app_en.arb`
One new string, e.g. `profileOrderSoundLabel` ("Order confirmation sound" /
"صوت تأكيد الطلب"). Regenerate `app_localizations*`.

## Data flow

```
Place order tap → _placeOrder → repository.placeOrder() succeeds
  → cart.refresh() (best-effort)
  → if settings.orderSoundEnabled: feedback.playOrderPlaced()  ── fire-and-forget
        AudioOrderFeedbackService: AudioPlayer.play(pip) [silent-mode aware]
                                 + HapticFeedback.mediumImpact()
        (any error → swallowed)
  → Navigator.pushReplacement(OrderSuccessPage)   ← never blocked by the above
```

## Behavior rules

- Fires exactly once per created order (rides the existing `_placing`
  idempotency guard). Never on OutOfStock / OutsideCoverage / StoreClosed /
  network-error branches.
- Toggle OFF → neither sound nor haptic.
- Toggle ON + device silenced → haptic only (OS mutes the sound).
- Sound/haptic failure → order confirmation + navigation proceed unaffected.

## Files touched

- **New:** `lib/core/audio/order_feedback_service.dart`,
  `lib/core/stores/settings_store.dart`, `assets/audio/order_placed.wav`,
  `test/core/stores/settings_store_test.dart`,
  `test/core/audio/order_feedback_service_test.dart` (fake/no-op contract),
  profile-toggle + checkout tests (extend existing suites).
- **Edited:** `pubspec.yaml`, `lib/features/checkout/checkout_page.dart`,
  `lib/features/profile/profile_tab.dart`, `lib/app.dart` / `lib/main.dart`,
  `lib/l10n/app_ar.arb`, `lib/l10n/app_en.arb` (+ generated localizations).

## Testing

- `SettingsStore`: default `true`; `setOrderSoundEnabled(false)` persists and
  notifies; `load()` restores a saved value and tolerates corrupt/missing prefs.
- Checkout (fake `OrderFeedbackService`): on successful place-order,
  `playOrderPlaced` called **once** when enabled, **not called** when disabled;
  order still confirms/navigates when the fake `playOrderPlaced` throws.
- Profile: toggling the switch flips `SettingsStore` and persists.
- Real `AudioOrderFeedbackService` not unit-tested (thin plugin wrapper, per the
  `GeolocatorLocationService` precedent).

## Rollout

App-only change; no backend work. Ships with the next app build. If the pip is
unwanted by a user, the settings toggle turns it off; a boot with corrupt prefs
falls back to the default (ON).
