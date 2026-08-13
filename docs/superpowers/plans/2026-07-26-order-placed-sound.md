# Order-placed confirmation sound + haptic — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play a short "pip" sound + subtle haptic the moment a customer's order is created, gated by a settings toggle and the phone's silent mode.

**Architecture:** A `shared_preferences`-backed `SettingsStore` (modeled on `LocaleStore`) holds the on/off toggle. An injectable `OrderFeedbackService` (modeled on `LocationService`) wraps `audioplayers` — the only file importing the plugin — and plays a bundled WAV via a silent-mode-aware `AudioContext` plus `HapticFeedback`. Checkout fires it (fire-and-forget) after a successful `place_order`. A profile switch flips the toggle.

**Tech Stack:** Flutter (SDK at `~/.flutter-sdk/bin/flutter`, not on PATH), `provider`, `shared_preferences` (already a dep), `audioplayers ^6.7.1` (new), `flutter/services` `HapticFeedback`.

## Global Constraints

- **Package freeze:** `audioplayers` is the only new dependency; add it with a freeze-exception comment (like the `geolocator` note) and confine every import of it to `AudioOrderFeedbackService`. Everything else depends on the `OrderFeedbackService` abstraction.
- **Best-effort feedback:** a sound/haptic failure must NEVER throw to the caller or block order confirmation/navigation. Fire-and-forget; the call is never `await`ed at the call site.
- **Default ON:** `orderSoundEnabled` defaults to `true`.
- **One toggle gates both** sound and haptic. Silent mode gates only the sound (haptic still fires on vibrate).
- **Arabic-first:** any new user-facing string is added to BOTH `app_ar.arb` and `app_en.arb`; Arabic is the primary market language.
- **Follow existing patterns:** `LocaleStore` (settings store), `LocationService`/`GeolocatorLocationService` (injectable service + fake), `_MenuTile` (profile row), `homeTestProviders`/`wrapPage` (test DI).
- **Flutter commands:** always `~/.flutter-sdk/bin/flutter …`. Do not switch git branches (stay on `feature/zad-mvp`).

---

### Task 1: `SettingsStore` (persisted order-sound toggle)

**Files:**
- Create: `lib/core/stores/settings_store.dart`
- Test: `test/core/stores/settings_store_test.dart`

**Interfaces:**
- Produces: `const kOrderSoundEnabledKey = 'zad.orderSoundEnabled'`; `class SettingsStore extends ChangeNotifier` with `bool get orderSoundEnabled`, `Future<void> load()`, `Future<void> setOrderSoundEnabled(bool value)`.

- [ ] **Step 1: Write the failing test**

Create `test/core/stores/settings_store_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/stores/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SettingsStore', () {
    test('defaults orderSoundEnabled to true, before and after load', () async {
      final store = SettingsStore();
      expect(store.orderSoundEnabled, isTrue);
      await store.load();
      expect(store.orderSoundEnabled, isTrue);
    });

    test('load() restores a saved false', () async {
      SharedPreferences.setMockInitialValues({kOrderSoundEnabledKey: false});
      final store = SettingsStore();
      await store.load();
      expect(store.orderSoundEnabled, isFalse);
    });

    test('load() tolerates corrupt prefs and keeps the default', () async {
      SharedPreferences.setMockInitialValues({kOrderSoundEnabledKey: 'not-a-bool'});
      final store = SettingsStore();
      await store.load(); // must not throw
      expect(store.orderSoundEnabled, isTrue);
    });

    test('setOrderSoundEnabled(false) flips, notifies once, and persists', () async {
      final store = SettingsStore();
      var notified = 0;
      store.addListener(() => notified++);

      await store.setOrderSoundEnabled(false);

      expect(store.orderSoundEnabled, isFalse);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kOrderSoundEnabledKey), isFalse);
    });

    test('setOrderSoundEnabled to the current value does not notify', () async {
      final store = SettingsStore();
      var notified = 0;
      store.addListener(() => notified++);
      await store.setOrderSoundEnabled(true); // already true
      expect(notified, 0);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/core/stores/settings_store_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '.../settings_store.dart'`.

- [ ] **Step 3: Write the implementation**

Create `lib/core/stores/settings_store.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted key for the order-placed confirmation sound toggle.
const kOrderSoundEnabledKey = 'zad.orderSoundEnabled';

/// User-preferences store (persisted via `shared_preferences`, like
/// [LocaleStore]). Currently just the order-placed confirmation sound + haptic
/// toggle. Defaults ON; an explicit choice from profile settings is restored
/// on the next launch.
class SettingsStore extends ChangeNotifier {
  bool _orderSoundEnabled = true;

  /// Whether the order-placed pip + haptic play. Default `true`.
  bool get orderSoundEnabled => _orderSoundEnabled;

  /// Restores a previously saved choice. Keeps the default when nothing (or an
  /// unreadable value) is saved — best-effort, never throws.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(kOrderSoundEnabledKey);
      if (saved != null && saved != _orderSoundEnabled) {
        _orderSoundEnabled = saved;
        notifyListeners();
      }
    } catch (_) {
      // Corrupt/unreadable prefs read as "no saved choice".
    }
  }

  Future<void> setOrderSoundEnabled(bool value) async {
    if (value == _orderSoundEnabled) return;
    _orderSoundEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kOrderSoundEnabledKey, value);
    } catch (_) {
      // Best-effort: a failed write just means the next boot uses the default.
    }
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/core/stores/settings_store_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Flutter/zad
git add lib/core/stores/settings_store.dart test/core/stores/settings_store_test.dart
git commit -m "feat(settings): SettingsStore with persisted order-sound toggle"
```

---

### Task 2: `audioplayers` dependency + the bundled pip asset

**Files:**
- Modify: `pubspec.yaml` (dependencies + assets)
- Create: `assets/audio/order_placed.wav`

**Interfaces:**
- Produces: the asset `assets/audio/order_placed.wav` (played as `AssetSource('audio/order_placed.wav')`); `audioplayers` importable.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml`, under `dependencies:`, add after the `geolocator:` block (mirroring its freeze-exception note):

```yaml
  # Plan-sanctioned exception to the package freeze: order-placed confirmation
  # sound. Only `AudioOrderFeedbackService` imports it — everything else (and
  # every test) goes through the injectable `OrderFeedbackService` abstraction.
  audioplayers: ^6.7.1
```

- [ ] **Step 2: Declare the asset directory**

In `pubspec.yaml`, under `flutter:` → `assets:` (which already lists `- assets/images/`), add:

```yaml
    - assets/audio/
```

- [ ] **Step 3: Generate the pip WAV**

Run (creates a ~210 ms soft two-tone rising pip, mono 44.1 kHz 16-bit, no numpy needed):

```bash
cd ~/Flutter/zad
mkdir -p assets/audio
python3 - <<'PY'
import math, struct, wave
sr = 44100
def tone(freq, ms, vol=0.5):
    n = int(sr*ms/1000); out = []
    for i in range(n):
        env = min(1.0, i/(0.005*sr), (n-i)/(0.012*sr))  # 5ms fade-in / 12ms fade-out
        out.append(int(vol*env*math.sin(2*math.pi*freq*i/sr)*32767))
    return out
samples = tone(880, 90) + tone(1320, 120)  # A5 -> E6 "pip-pip"
with wave.open('assets/audio/order_placed.wav', 'w') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(b''.join(struct.pack('<h', max(-32768, min(32767, s))) for s in samples))
print('wrote assets/audio/order_placed.wav')
PY
ls -l assets/audio/order_placed.wav
```
Expected: prints the path and a ~18 KB file.

- [ ] **Step 4: Fetch packages**

Run: `~/.flutter-sdk/bin/flutter pub get`
Expected: resolves with `audioplayers 6.7.1` (already in pub-cache), no errors.

- [ ] **Step 5: Commit**

```bash
cd ~/Flutter/zad
git add pubspec.yaml pubspec.lock assets/audio/order_placed.wav
git commit -m "chore(deps): add audioplayers + order_placed pip asset (freeze exception)"
```

---

### Task 3: `OrderFeedbackService` (abstraction + audio impl + noop) + fake

**Files:**
- Create: `lib/core/audio/order_feedback_service.dart`
- Create: `test/support/fake_order_feedback_service.dart`
- Test: `test/core/audio/order_feedback_service_test.dart`

**Interfaces:**
- Consumes: `audioplayers` (Task 2), the asset `audio/order_placed.wav` (Task 2).
- Produces: `abstract class OrderFeedbackService { Future<void> playOrderPlaced(); }`; `class AudioOrderFeedbackService implements OrderFeedbackService`; `class NoopOrderFeedbackService implements OrderFeedbackService` (has `const` constructor); test-only `class FakeOrderFeedbackService implements OrderFeedbackService` with `int playOrderPlacedCount` and `bool throwOnPlay`.

- [ ] **Step 1: Write the failing test**

Create `test/core/audio/order_feedback_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/audio/order_feedback_service.dart';

import '../../support/fake_order_feedback_service.dart';

void main() {
  test('NoopOrderFeedbackService.playOrderPlaced completes and never throws',
      () async {
    await const NoopOrderFeedbackService().playOrderPlaced();
  });

  test('FakeOrderFeedbackService records calls and can simulate a failure',
      () async {
    final fake = FakeOrderFeedbackService();
    await fake.playOrderPlaced();
    await fake.playOrderPlaced();
    expect(fake.playOrderPlacedCount, 2);

    final boom = FakeOrderFeedbackService(throwOnPlay: true);
    expect(boom.playOrderPlaced(), throwsA(isA<Exception>()));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/core/audio/order_feedback_service_test.dart`
Expected: FAIL — URIs for `order_feedback_service.dart` / `fake_order_feedback_service.dart` don't exist.

- [ ] **Step 3: Write the service**

Create `lib/core/audio/order_feedback_service.dart`:

```dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Injectable "an order was created" feedback (PRD checkout). Screens depend on
/// this interface only, so tests substitute a fake and never touch the audio
/// platform channel — same seam pattern as `LocationService`.
abstract class OrderFeedbackService {
  /// Plays the confirmation pip + a subtle haptic. Best-effort: never throws.
  Future<void> playOrderPlaced();
}

/// No-op implementation — the default for pushless/test builds and any context
/// where audio isn't wanted.
class NoopOrderFeedbackService implements OrderFeedbackService {
  const NoopOrderFeedbackService();

  @override
  Future<void> playOrderPlaced() async {}
}

/// Real implementation over `audioplayers` — the ONLY file importing the
/// plugin (package-freeze exception). One reusable player, configured to honour
/// the phone's silent switch (Android notification usage; iOS ambient category),
/// so a silenced phone gets the haptic only.
class AudioOrderFeedbackService implements OrderFeedbackService {
  AudioOrderFeedbackService() : _player = AudioPlayer() {
    _player.setReleaseMode(ReleaseMode.stop);
    // Fire-and-forget context config; the service is created at app boot, long
    // before checkout, so it is applied by the time the pip plays.
    _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notification,
          audioFocus: AndroidAudioFocus.none,
        ),
      ),
    );
  }

  final AudioPlayer _player;

  @override
  Future<void> playOrderPlaced() async {
    // Best-effort: a sound/haptic failure must never affect the order
    // confirmation or navigation. Haptic fires even on vibrate/silent.
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/order_placed.wav'));
    } catch (_) {}
  }
}
```

- [ ] **Step 4: Write the fake**

Create `test/support/fake_order_feedback_service.dart`:

```dart
import 'package:zad/core/audio/order_feedback_service.dart';

/// In-memory [OrderFeedbackService] for widget tests — no audioplayers, no
/// platform channel. Records how many times the pip was requested; optionally
/// throws to prove the caller tolerates a feedback failure.
class FakeOrderFeedbackService implements OrderFeedbackService {
  FakeOrderFeedbackService({this.throwOnPlay = false});

  final bool throwOnPlay;
  int playOrderPlacedCount = 0;

  @override
  Future<void> playOrderPlaced() async {
    playOrderPlacedCount++;
    if (throwOnPlay) throw Exception('feedback failure (test)');
  }
}
```

- [ ] **Step 5: Run it to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/core/audio/order_feedback_service_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/Flutter/zad
git add lib/core/audio/order_feedback_service.dart test/support/fake_order_feedback_service.dart test/core/audio/order_feedback_service_test.dart
git commit -m "feat(audio): OrderFeedbackService (audioplayers pip + haptic) with fake"
```

---

### Task 4: Wire `SettingsStore` + `OrderFeedbackService` into app DI

**Files:**
- Modify: `lib/app.dart` (imports + `MultiProvider` list)

**Interfaces:**
- Consumes: `SettingsStore` (Task 1), `OrderFeedbackService`/`AudioOrderFeedbackService` (Task 3).
- Produces: `SettingsStore` and `OrderFeedbackService` available via `context.read`/`context.watch` app-wide.

- [ ] **Step 1: Add imports**

In `lib/app.dart`, add alongside the other `core/…` imports:

```dart
import 'core/audio/order_feedback_service.dart';
import 'core/stores/settings_store.dart';
```

- [ ] **Step 2: Register the providers**

In `lib/app.dart`, inside `MultiProvider(providers: [ … ])`, add right after the `ChangeNotifierProvider<LocaleStore>( … )` entry:

```dart
        // Persisted user preferences (order-placed confirmation sound). Loaded
        // at boot like LocaleStore; default ON.
        ChangeNotifierProvider<SettingsStore>(
          create: (_) => SettingsStore()..load(),
        ),
        // Injectable seam over `audioplayers` (order-placed pip + haptic).
        // Package-freeze exception; only AudioOrderFeedbackService imports the
        // plugin, tests swap in a fake.
        Provider<OrderFeedbackService>(
          create: (_) => AudioOrderFeedbackService(),
        ),
```

- [ ] **Step 3: Verify it compiles**

Run: `~/.flutter-sdk/bin/flutter analyze lib/app.dart`
Expected: "No issues found!" (or only pre-existing unrelated infos).

- [ ] **Step 4: Commit**

```bash
cd ~/Flutter/zad
git add lib/app.dart
git commit -m "feat(app): provide SettingsStore + OrderFeedbackService"
```

---

### Task 5: Play the feedback on a successful order (checkout wiring + tests)

**Files:**
- Modify: `test/helpers.dart` (`homeTestProviders` — add two optional providers)
- Modify: `lib/features/checkout/checkout_page.dart` (`_placeOrder`)
- Modify: `test/features/checkout/checkout_page_test.dart` (`buildCheckout` + 3 tests)

**Interfaces:**
- Consumes: `SettingsStore`, `OrderFeedbackService` (via `context.read`), `FakeOrderFeedbackService` (tests).
- Produces: on a successful `place_order`, `OrderFeedbackService.playOrderPlaced()` is invoked once iff `SettingsStore.orderSoundEnabled`.

- [ ] **Step 1: Extend the test provider harness**

In `test/helpers.dart`: add the imports

```dart
import 'package:zad/core/audio/order_feedback_service.dart';
import 'package:zad/core/stores/settings_store.dart';
```

Add two parameters to `homeTestProviders(...)` (alongside the existing optional params):

```dart
  SettingsStore? settingsStore,
  OrderFeedbackService? orderFeedbackService,
```

And in the list `homeTestProviders` returns, append two entries:

```dart
    ChangeNotifierProvider<SettingsStore>.value(
      value: settingsStore ?? SettingsStore(),
    ),
    Provider<OrderFeedbackService>.value(
      value: orderFeedbackService ?? const NoopOrderFeedbackService(),
    ),
```

- [ ] **Step 2: Write the failing checkout tests**

In `test/features/checkout/checkout_page_test.dart`:

(a) add imports:

```dart
import 'package:zad/core/audio/order_feedback_service.dart';
import 'package:zad/core/stores/settings_store.dart';
import '../../support/fake_order_feedback_service.dart';
```

(b) add two parameters to the `buildCheckout(...)` helper signature and forward them into `homeTestProviders(...)`:

```dart
    OrderFeedbackService? orderFeedbackService,
    SettingsStore? settingsStore,
```
```dart
      providers: homeTestProviders(
        sessionStore: session,
        cartStore: cart,
        addressStore: addressStore,
        appConfigStore: appConfigStore,
        orderFeedbackService: orderFeedbackService,
        settingsStore: settingsStore,
        orderRepository: buildFakeOrderRepository(
          overrides: orderOverrides,
          capturedRequests: orderRequests,
        ),
      ),
```

(c) add three tests inside `main()` (after an existing success test):

```dart
  testWidgets('plays order-placed feedback once on success when enabled',
      (tester) async {
    final feedback = FakeOrderFeedbackService();
    await tester.pumpWidget(
      await buildCheckout(tester, orderFeedbackService: feedback),
    );
    await placeOrderNow(tester);

    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(feedback.playOrderPlacedCount, 1);
  });

  testWidgets('does not play feedback when the setting is disabled',
      (tester) async {
    final feedback = FakeOrderFeedbackService();
    final settings = SettingsStore();
    await tester.runAsync(() => settings.setOrderSoundEnabled(false));
    await tester.pumpWidget(
      await buildCheckout(
        tester,
        orderFeedbackService: feedback,
        settingsStore: settings,
      ),
    );
    await placeOrderNow(tester);

    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(feedback.playOrderPlacedCount, 0);
  });

  testWidgets('order still confirms when feedback throws', (tester) async {
    final feedback = FakeOrderFeedbackService(throwOnPlay: true);
    await tester.pumpWidget(
      await buildCheckout(tester, orderFeedbackService: feedback),
    );
    await placeOrderNow(tester);

    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(feedback.playOrderPlacedCount, 1);
  });
```

- [ ] **Step 3: Run to verify they fail**

Run: `~/.flutter-sdk/bin/flutter test test/features/checkout/checkout_page_test.dart`
Expected: the two "plays…once" / "still confirms" tests FAIL (`playOrderPlacedCount` is 0, feedback never called) — the disabled-case test may pass incidentally. This confirms the wiring is missing.

- [ ] **Step 4: Wire the checkout call**

In `lib/features/checkout/checkout_page.dart`, add imports:

```dart
import '../../core/audio/order_feedback_service.dart';
import '../../core/stores/settings_store.dart';
```

In `_placeOrder`, capture the services before the await, right after `final cart = context.read<CartStore>();`:

```dart
    final settings = context.read<SettingsStore>();
    final feedback = context.read<OrderFeedbackService>();
```

Then, on the success path, right after `cart.refresh().catchError((_) {});` and before `if (!mounted) return;`:

```dart
      // "Order created" cue (fire-and-forget; the service swallows its own
      // errors, so this never blocks or breaks the confirmation/navigation).
      if (settings.orderSoundEnabled) {
        feedback.playOrderPlaced();
      }
```

- [ ] **Step 5: Run to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/features/checkout/checkout_page_test.dart`
Expected: PASS (all checkout tests, including the 3 new ones).

- [ ] **Step 6: Commit**

```bash
cd ~/Flutter/zad
git add test/helpers.dart lib/features/checkout/checkout_page.dart test/features/checkout/checkout_page_test.dart
git commit -m "feat(checkout): play order-placed sound/haptic on success (toggle-gated)"
```

---

### Task 6: Profile mute toggle + localization

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`
- Modify: `lib/features/profile/profile_tab.dart` (import, toggle tile widget, menu row)
- Modify: `test/features/profile_tab_test.dart` (toggle test)

**Interfaces:**
- Consumes: `SettingsStore` (Task 1), `l10n.profileOrderSoundLabel` (this task).
- Produces: a switch keyed `Key('profileOrderSoundToggle')` that reads/writes `SettingsStore.orderSoundEnabled`.

- [ ] **Step 1: Add the localized string**

In `lib/l10n/app_en.arb`, add (near `"languageTitle"`):

```json
  "profileOrderSoundLabel": "Order confirmation sound",
```

In `lib/l10n/app_ar.arb`, add the matching key:

```json
  "profileOrderSoundLabel": "صوت تأكيد الطلب",
```

(Match the surrounding comma/format; both files use plain `"key": "value"` entries.)

- [ ] **Step 2: Regenerate localizations**

Run: `~/.flutter-sdk/bin/flutter gen-l10n`
Expected: no errors; `l10n.profileOrderSoundLabel` now exists on `AppLocalizations`.

- [ ] **Step 3: Write the failing profile test**

In `test/features/profile_tab_test.dart`, add imports if missing:

```dart
import 'package:provider/provider.dart';
import 'package:zad/core/stores/settings_store.dart';
```

Add a test that mounts the authed profile with a `SettingsStore` provided and toggles the switch. Use the file's existing authed-profile pump helper/provider list; provide the store via `ChangeNotifierProvider<SettingsStore>.value(value: settings)` in that test's `providers:` list. Assert:

```dart
  testWidgets('order-sound switch flips SettingsStore', (tester) async {
    final settings = SettingsStore(); // defaults enabled = true
    // ... pump the authed ProfileTab with `settings` provided (see the file's
    // existing authed-profile fixture; add the provider to its `providers:` list).
    await tester.tap(find.byKey(const Key('profileOrderSoundToggle')));
    await tester.pumpAndSettle();
    expect(settings.orderSoundEnabled, isFalse);
  });
```

- [ ] **Step 4: Run to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/features/profile_tab_test.dart`
Expected: FAIL — no widget with `Key('profileOrderSoundToggle')`.

- [ ] **Step 5: Implement the toggle tile + menu row**

In `lib/features/profile/profile_tab.dart`, add the import:

```dart
import '../../core/stores/settings_store.dart';
```

Add a toggle-tile widget (place next to the `_MenuTile` class):

```dart
/// A settings row shaped like [_MenuTile] but with a trailing switch.
class _MenuToggleTile extends StatelessWidget {
  const _MenuToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 6, 2),
        decoration: BoxDecoration(
          color: ZadColors.surface,
          borderRadius: BorderRadius.circular(ZadRadii.tile),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: ZadColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ZadColors.ink,
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              activeColor: ZadColors.primary,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
```

In the authed menu list (in `_AuthedProfile.build`), insert right after the `_MenuTile(key: Key('profileMenuLanguage'), …)` entry:

```dart
        _MenuToggleTile(
          key: const Key('profileOrderSoundToggle'),
          icon: Iconsax.volume_high,
          label: l10n.profileOrderSoundLabel,
          value: context.watch<SettingsStore>().orderSoundEnabled,
          onChanged: (v) =>
              context.read<SettingsStore>().setOrderSoundEnabled(v),
        ),
```

- [ ] **Step 6: Run to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/features/profile_tab_test.dart`
Expected: PASS (including the new toggle test).

- [ ] **Step 7: Commit**

```bash
cd ~/Flutter/zad
git add lib/l10n/app_en.arb lib/l10n/app_ar.arb lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_ar.dart lib/features/profile/profile_tab.dart test/features/profile_tab_test.dart
git commit -m "feat(profile): order-sound mute toggle in settings"
```

---

### Task 7: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Analyze**

Run: `~/.flutter-sdk/bin/flutter analyze`
Expected: no NEW issues in the files touched (`settings_store.dart`, `order_feedback_service.dart`, `app.dart`, `checkout_page.dart`, `profile_tab.dart`, tests).

- [ ] **Step 2: Full test suite**

Run: `~/.flutter-sdk/bin/flutter test`
Expected: all tests pass (existing + the new SettingsStore, OrderFeedbackService, checkout, and profile tests).

- [ ] **Step 3: (Optional) real-device smoke**

Build/install as usual (`~/.flutter-sdk/bin/flutter build apk --release --dart-define=API_BASE_URL=https://zad.micronext.net`), place a test order, and confirm the pip + a short buzz fire; toggle it off in profile and confirm silence; silence the phone and confirm haptic-only.

- [ ] **Step 4: Final commit (if any analyze fixups were needed)**

```bash
cd ~/Flutter/zad
git add -A
git commit -m "chore: order-placed feedback — analyze/test cleanup"
```

---

## Self-Review

**Spec coverage:**
- Trigger at checkout success → Task 5. ✓
- `audioplayers` + bundled pip → Task 2/3. ✓
- Silent-mode-aware `AudioContext` + haptic → Task 3. ✓
- `SettingsStore` toggle (default ON, persisted) → Task 1. ✓
- Profile switch + ar/en string → Task 6. ✓
- DI wiring → Task 4. ✓
- Best-effort/fire-and-forget, one toggle gates both, fires once → Tasks 3 & 5 (idempotency rides existing `_placing` guard). ✓
- Tests: SettingsStore, Noop/fake contract, checkout (enabled/disabled/throws), profile toggle → Tasks 1,3,5,6. ✓

**Placeholder scan:** all code steps carry full code; the only prose-guided integration (Task 6 Step 3 pump) points at the file's existing authed-profile fixture rather than duplicating it — acceptable because that fixture already exists and varies by test; the assertion + provider line are given verbatim.

**Type consistency:** `SettingsStore.orderSoundEnabled` / `setOrderSoundEnabled(bool)` / `load()`, `kOrderSoundEnabledKey`, `OrderFeedbackService.playOrderPlaced()`, `NoopOrderFeedbackService` (const), `FakeOrderFeedbackService.playOrderPlacedCount`/`throwOnPlay`, and `Key('profileOrderSoundToggle')` are used identically across Tasks 1–7. `homeTestProviders`/`buildCheckout` gain the same two param names (`settingsStore`, `orderFeedbackService`). ✓
