# Modern Popup Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace every raw Material popup (dialogs, bottom sheets, snackbars) with a shared, on-brand, icon-led popup system built on the design tokens, and document the design-system standards.

**Architecture:** Three token-driven helpers in `lib/core/widgets/` — `showZadConfirm`/`showZadDialog` (icon-led dialog), `showZadSheet` (grabber sheet), `showZadSnack` (floating variant snackbar) — plus `dialogTheme`/`snackBarTheme` defaults as a safety net. All current call sites migrate to them. `core/widgets` never imports `features/**`.

**Tech Stack:** Flutter 3.41 / Dart 3.11; `flutter_test`; `flutter_gen_l10n`; existing tokens `ZadColors`/`ZadRadii`/`ZadSpacing` in `lib/core/theme.dart` + `lib/core/constants.dart`.

## Global Constraints

- **Flutter SDK not on PATH** — invoke as `~/.flutter-sdk/bin/flutter`.
- **Tokens only** — no raw hex / `Colors.*` / magic radii in feature code; use `ZadColors`/`ZadRadii`/`ZadElevation`/`ZadDurations`/`ZadCurves`.
- **Layering** — files in `lib/core/widgets/` must NOT import from `lib/features/**`.
- **Localization** — all user-facing copy via `AppLocalizations`; add strings to BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_ar.arb`, then `~/.flutter-sdk/bin/flutter gen-l10n`.
- **RTL-safe** — logical insets (`EdgeInsetsDirectional`, `start`/`end`) only; no `left`/`right` literals.
- **Action hierarchy** — exactly one primary per popup; destructive ⇒ `ZadColors.danger` filled; secondary ⇒ text.
- **Stable keys** for tests: `zadDialogPrimary`, `zadDialogSecondary`, `zadSnack`.
- **TDD** — failing test first, then minimal implementation, then commit.

---

## Task 1: Design tokens + theme defaults

**Files:**
- Modify: `lib/core/theme.dart`
- Modify: `lib/core/constants.dart`
- Test: `test/core/theme_test.dart` (create)

**Interfaces:**
- Produces: `ZadColors.danger/success/info/warning/scrim`; `ZadRadii.dialog`; `ZadElevation.{dialog,sheet,snack}`; `ZadDurations.{popupIn,snack}`; `ZadCurves.popupIn`; `zadTheme()` gains `dialogTheme` + `snackBarTheme`.

- [ ] **Step 1: Write the failing test**

Create `test/core/theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/core/constants.dart';

void main() {
  test('semantic + popup tokens exist and are distinct', () {
    expect(ZadColors.danger, isNot(ZadColors.primary));
    expect(ZadColors.success, isNot(ZadColors.info));
    expect(ZadRadii.dialog, 28);
    expect(ZadElevation.dialog, greaterThan(0));
    expect(ZadDurations.popupIn.inMilliseconds, greaterThan(0));
  });

  test('theme defines dialog + snackbar themes on brand', () {
    final t = zadTheme();
    expect(t.dialogTheme.backgroundColor, ZadColors.white);
    expect(t.snackBarTheme.behavior, SnackBarBehavior.floating);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter test test/core/theme_test.dart`
Expected: FAIL — `danger`/`success`/`ZadRadii.dialog`/`ZadElevation` undefined.

- [ ] **Step 3: Add the tokens**

In `lib/core/theme.dart`, add to `ZadColors` (after `errorText`):

```dart
  /// Destructive-action fill (Clear/Delete/Logout) — the app's error red.
  static const danger = Color(0xFFB3261E);

  /// Snackbar variant accents.
  static const success = Color(0xFF2E7D32);
  static const info = Color(0xFF1565C0);
  static const warning = Color(0xFFB26A00);

  /// Dialog/sheet barrier scrim.
  static final scrim = Colors.black.withValues(alpha: 0.45);
```

In `lib/core/constants.dart`, add `dialog` to `ZadRadii` and new token classes:

```dart
abstract final class ZadRadii {
  static const double tile = 14;
  static const double banner = 16;
  static const double sheet = 30;
  static const double button = 12;
  static const double dialog = 28;
}

/// Shadow blur radii for popups (not Material elevation).
abstract final class ZadElevation {
  static const double dialog = 24;
  static const double sheet = 16;
  static const double snack = 6;
}

abstract final class ZadDurations {
  static const popupIn = Duration(milliseconds: 220);
  static const snack = Duration(seconds: 3);
}

abstract final class ZadCurves {
  static const popupIn = Curves.easeOutCubic;
}
```

- [ ] **Step 4: Add theme defaults**

In `lib/core/theme.dart`, import constants and extend `zadTheme()`'s `copyWith`:

Add at top: `import 'constants.dart';`

Change the `return base.copyWith(` block to also set:

```dart
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Poppins',
      fontFamilyFallback: const ['Cairo'],
      bodyColor: ZadColors.ink,
      displayColor: ZadColors.ink,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ZadColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZadRadii.dialog),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZadRadii.button),
      ),
    ),
  );
```

- [ ] **Step 5: Run test to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/core/theme_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/Flutter/zad
git add lib/core/theme.dart lib/core/constants.dart test/core/theme_test.dart
git commit -m "feat(ui): popup design tokens + dialog/snackbar theme defaults"
```

---

## Task 2: Dialog system — `ZadDialog`, `showZadConfirm`, `showZadDialog`

**Files:**
- Create: `lib/core/widgets/zad_dialog.dart`
- Test: `test/core/widgets/zad_dialog_test.dart`

**Interfaces:**
- Consumes: tokens (Task 1).
- Produces:
  - `Future<bool> showZadConfirm(BuildContext, {required String title, required String message, required String confirmLabel, required String cancelLabel, IconData? icon, bool destructive = false})` — barrier-dismissible only when `!destructive` (dismiss ⇒ false).
  - `Future<T?> showZadDialog<T>(BuildContext, {IconData? icon, String? title, required WidgetBuilder contentBuilder, List<Widget> actions = const [], bool barrierDismissible = true})`.
  - Primary button `Key('zadDialogPrimary')`, secondary `Key('zadDialogSecondary')`.

- [ ] **Step 1: Write the failing test**

Create `test/core/widgets/zad_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/core/widgets/zad_dialog.dart';

void main() {
  Future<void> pumpHost(WidgetTester tester, void Function(BuildContext) onTap) async {
    await tester.pumpWidget(MaterialApp(
      theme: zadTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => onTap(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('confirm resolves true on primary, false on secondary', (tester) async {
    bool? result;
    await pumpHost(tester, (context) async {
      result = await showZadConfirm(context,
          title: 'Clear basket?', message: 'Removes all items.',
          confirmLabel: 'Clear', cancelLabel: 'Cancel',
          icon: Icons.delete_outline, destructive: true);
    });

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Clear basket?'), findsOneWidget);

    // Destructive primary is danger-coloured.
    final btn = tester.widget<ElevatedButton>(find.byKey(const Key('zadDialogPrimary')));
    final bg = btn.style!.backgroundColor!.resolve({});
    expect(bg, ZadColors.danger);

    await tester.tap(find.byKey(const Key('zadDialogPrimary')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('confirm resolves false on secondary tap', (tester) async {
    bool? result;
    await pumpHost(tester, (context) async {
      result = await showZadConfirm(context,
          title: 'T', message: 'M', confirmLabel: 'Yes', cancelLabel: 'No');
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zadDialogSecondary')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('showZadDialog returns the tapped action value', (tester) async {
    String? picked;
    await pumpHost(tester, (context) async {
      picked = await showZadDialog<String>(context,
          title: 'Pick',
          contentBuilder: (_) => const Text('body'),
          actions: [
            TextButton(
              key: const Key('optA'),
              onPressed: () => Navigator.pop(context, 'A'),
              child: const Text('A'),
            ),
          ]);
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);
    await tester.tap(find.byKey(const Key('optA')));
    await tester.pumpAndSettle();
    expect(picked, 'A');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/core/widgets/zad_dialog_test.dart`
Expected: FAIL — `zad_dialog.dart` / `showZadConfirm` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/core/widgets/zad_dialog.dart`:

```dart
import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme.dart';

/// The icon-led dialog scaffold shared by [showZadConfirm] and [showZadDialog]:
/// a circular tinted icon badge, bold centred title, muted body/content, and a
/// bottom action column (one full-width filled primary, optional text
/// secondary). 28px radius, white surface, soft shadow, scale+fade entrance.
///
/// Lives in core/widgets and imports only core tokens — no feature deps.
class ZadDialog extends StatelessWidget {
  const ZadDialog({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: ZadColors.white,
          elevation: ZadElevation.dialog,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(ZadRadii.dialog),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _iconBadge(IconData icon, Color color) => Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 28),
    );

Widget _primaryButton({
  required Key key,
  required String label,
  required Color color,
  required VoidCallback onPressed,
}) =>
    SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        key: key,
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: ZadColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZadRadii.button),
          ),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );

Future<T?> _showBrandedDialog<T>(
  BuildContext context, {
  required bool barrierDismissible,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: ZadColors.scrim,
    transitionDuration: ZadDurations.popupIn,
    pageBuilder: (context, _, __) => builder(context),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: ZadCurves.popupIn);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Confirm/cancel dialog. Resolves true on confirm, false on cancel. When
/// [destructive] the primary is [ZadColors.danger] and the barrier is NOT
/// dismissible (forces an explicit choice); otherwise a barrier tap ⇒ false.
Future<bool> showZadConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  IconData? icon,
  bool destructive = false,
}) async {
  final color = destructive ? ZadColors.danger : ZadColors.primary;
  final result = await _showBrandedDialog<bool>(
    context,
    barrierDismissible: !destructive,
    builder: (dialogContext) => ZadDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            _iconBadge(icon, color),
            const SizedBox(height: 18),
          ],
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: ZadColors.ink)),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: ZadColors.muted, height: 1.4)),
          const SizedBox(height: 24),
          _primaryButton(
            key: const Key('zadDialogPrimary'),
            label: confirmLabel,
            color: color,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('zadDialogSecondary'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(cancelLabel,
                style: const TextStyle(fontSize: 14, color: ZadColors.muted)),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Lower-level dialog for custom body/actions (lists, checkboxes, option rows).
/// [contentBuilder] renders below the title; [actions] are laid out in a
/// bottom column. Callers pop [Navigator] with their own result value.
Future<T?> showZadDialog<T>(
  BuildContext context, {
  IconData? icon,
  String? title,
  required WidgetBuilder contentBuilder,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
}) {
  return _showBrandedDialog<T>(
    context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => ZadDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (icon != null) ...[
            Center(child: _iconBadge(icon, ZadColors.primary)),
            const SizedBox(height: 18),
          ],
          if (title != null) ...[
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: ZadColors.ink)),
            const SizedBox(height: 12),
          ],
          contentBuilder(dialogContext),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            ...actions,
          ],
        ],
      ),
    ),
  );
}

/// A full-width filled primary action for use inside [showZadDialog.actions].
Widget zadDialogPrimaryAction({
  required String label,
  required VoidCallback? onPressed,
  bool destructive = false,
}) =>
    _primaryButton(
      key: const Key('zadDialogPrimary'),
      label: label,
      color: destructive ? ZadColors.danger : ZadColors.primary,
      onPressed: onPressed ?? () {},
    );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/core/widgets/zad_dialog_test.dart`
Expected: PASS (all 3).

- [ ] **Step 5: Commit**

```bash
cd ~/Flutter/zad
git add lib/core/widgets/zad_dialog.dart test/core/widgets/zad_dialog_test.dart
git commit -m "feat(ui): ZadDialog + showZadConfirm/showZadDialog icon-led dialogs"
```

---

## Task 3: Migrate basket + address confirm dialogs

**Files:**
- Modify: `lib/features/basket/basket_page.dart` (the `showDialog<bool>` at ~line 54)
- Modify: `lib/features/addresses/address_list_page.dart` (the `showDialog<bool>` at ~line 58)
- Test: `test/features/basket/basket_page_test.dart`, `test/features/addresses/address_list_page_test.dart` (update finders)

**Interfaces:**
- Consumes: `showZadConfirm` (Task 2).

- [ ] **Step 1: Update the failing tests**

In `test/features/basket/basket_page_test.dart`, find the clear-basket test that taps the confirm action. Replace the tap-target `find.widgetWithText(TextButton, l10n.basketClearAll)` (or the dialog confirm text finder) with `find.byKey(const Key('zadDialogPrimary'))`, and the cancel finder with `find.byKey(const Key('zadDialogSecondary'))`. Keep the assertions (basket cleared / kept).

In `test/features/addresses/address_list_page_test.dart`, do the same for the delete-address confirm/cancel taps.

(Run the two files first to see the exact current finders:
`~/.flutter-sdk/bin/flutter test test/features/basket/basket_page_test.dart test/features/addresses/address_list_page_test.dart` — note which lines tap the dialog buttons, and update only those to the keys above.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.flutter-sdk/bin/flutter test test/features/basket/basket_page_test.dart test/features/addresses/address_list_page_test.dart`
Expected: FAIL — no widget with key `zadDialogPrimary` (dialogs not migrated yet).

- [ ] **Step 3: Migrate basket clear-basket dialog**

In `lib/features/basket/basket_page.dart`, add `import '../../core/widgets/zad_dialog.dart';` and replace the `showDialog<bool>(...AlertDialog...)` block (the clear-basket confirm) with:

```dart
    final confirmed = await showZadConfirm(
      context,
      title: l10n.basketClearTitle,
      message: l10n.basketClearMessage,
      confirmLabel: l10n.basketClearAll,
      cancelLabel: l10n.cancel,
      icon: Icons.delete_outline,
      destructive: true,
    );
```

(Delete the old `showDialog`/`AlertDialog` code and its now-unused local `dialogContext`.)

- [ ] **Step 4: Migrate address delete dialog**

In `lib/features/addresses/address_list_page.dart`, add `import '../../core/widgets/zad_dialog.dart';` and replace the delete `showDialog<bool>(...AlertDialog...)` with:

```dart
    final confirmed = await showZadConfirm(
      context,
      title: l10n.addressDeleteTitle,
      message: l10n.addressDeleteMessage,
      confirmLabel: l10n.addressDelete,
      cancelLabel: l10n.cancel,
      icon: Icons.delete_outline,
      destructive: true,
    );
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/features/basket/basket_page_test.dart test/features/addresses/address_list_page_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/Flutter/zad
git add lib/features/basket/basket_page.dart lib/features/addresses/address_list_page.dart test/features/basket/ test/features/addresses/address_list_page_test.dart
git commit -m "refactor(ui): basket + address confirm dialogs use showZadConfirm"
```

---

## Task 4: Migrate profile dialogs (logout, delete-account, support, language)

**Files:**
- Modify: `lib/features/profile/profile_tab.dart` (dialogs at ~lines 40, 173, 221, 248)
- Test: `test/features/profile_tab_test.dart` (+ any delete-account test) — update finders

**Interfaces:**
- Consumes: `showZadConfirm`, `showZadDialog`, `zadDialogPrimaryAction` (Task 2).

- [ ] **Step 1: Update the failing tests**

In `test/features/profile_tab_test.dart` (and the delete-account test if separate), update the dialog button finders to the shared keys: logout confirm/cancel → `zadDialogPrimary`/`zadDialogSecondary`; delete-account confirm → `zadDialogPrimary`, its checkbox tap unchanged; language option taps target the option row by its text (unchanged); support "copy"/close taps target their existing text/keys. Keep all behavioural assertions.

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.flutter-sdk/bin/flutter test test/features/profile_tab_test.dart`
Expected: FAIL — shared keys absent (not migrated).

- [ ] **Step 3: Migrate logout confirm**

In `lib/features/profile/profile_tab.dart` add `import '../../core/widgets/zad_dialog.dart';`. Replace the logout `showDialog<bool>(...AlertDialog...)` with:

```dart
    final confirmed = await showZadConfirm(
      context,
      title: l10n.profileLogoutConfirmTitle,
      message: l10n.profileLogoutConfirmMessage,
      confirmLabel: l10n.profileLogoutButton,
      cancelLabel: l10n.cancel,
      icon: Icons.logout,
      destructive: true,
    );
```

- [ ] **Step 4: Migrate delete-account (keeps checkbox gate)**

Replace the delete-account `showDialog<bool>(...StatefulBuilder...AlertDialog...)` with a `showZadDialog<bool>` whose content is the `StatefulBuilder` checkbox and whose primary is gated:

```dart
    final confirmed = await showZadDialog<bool>(
      context,
      icon: Icons.warning_amber_rounded,
      title: l10n.deleteAccountTitle,
      contentBuilder: (dialogContext) {
        var checked = false;
        return StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.deleteAccountMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: ZadColors.muted, height: 1.4)),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: checked,
                onChanged: (v) => setState(() => checked = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.deleteAccountConfirmCheckbox),
              ),
              const SizedBox(height: 12),
              zadDialogPrimaryAction(
                label: l10n.deleteAccountConfirmButton,
                destructive: true,
                onPressed: checked ? () => Navigator.pop(dialogContext, true) : null,
              ),
              TextButton(
                key: const Key('zadDialogSecondary'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.cancel,
                    style: const TextStyle(fontSize: 14, color: ZadColors.muted)),
              ),
            ],
          ),
        );
      },
    );
```

Ensure `import '../../core/theme.dart';` is present (for `ZadColors`). Replace `l10n.deleteAccountMessage`/`deleteAccountConfirmButton` with the actual existing keys used in the current dialog (check the current code; if the message key differs, use that key verbatim).

- [ ] **Step 5: Migrate support + language dialogs**

Support dialog → `showZadDialog<void>` with `icon: Icons.headset_mic_outlined`, `title: l10n.supportTitle`, `contentBuilder` returning the existing phone/copy `Column`, and `actions: [ TextButton(...close...) ]`.

Language picker `SimpleDialog` → `showZadDialog<Locale>` with `title: l10n.languageTitle` and `contentBuilder` returning a `Column` of `ListTile`s (one per locale) that `Navigator.pop(context, locale)`; remove the `SimpleDialog`/`SimpleDialogOption` code. Keep the existing option labels/keys so the test finders still match.

- [ ] **Step 6: Run tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/features/profile_tab_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
cd ~/Flutter/zad
git add lib/features/profile/profile_tab.dart test/features/profile_tab_test.dart
git commit -m "refactor(ui): profile logout/delete/support/language use Zad dialogs"
```

---

## Task 5: Migrate checkout dialogs (out-of-stock, outside-coverage)

**Files:**
- Modify: `lib/features/checkout/checkout_page.dart` (dialogs at ~lines 166, 211)
- Test: `test/features/checkout/checkout_page_test.dart` — update finders

**Interfaces:**
- Consumes: `showZadConfirm`, `showZadDialog` (Task 2).

- [ ] **Step 1: Update the failing tests**

In `test/features/checkout/checkout_page_test.dart`, the 409 out-of-stock test taps the "refresh basket" action and the 417 outside-coverage test taps "manage addresses"/deep-link. Update those action finders to the migrated buttons: out-of-stock actions keep their existing labels (target by text) or the `zadDialogPrimary` key; outside-coverage primary → `zadDialogPrimary`, secondary → `zadDialogSecondary`. Keep the dialog-content assertions (item names listed; deep-link to `/addresses`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.flutter-sdk/bin/flutter test test/features/checkout/checkout_page_test.dart --plain-name "out-of-stock"`
Expected: FAIL — migrated buttons/keys absent.

- [ ] **Step 3: Migrate outside-coverage dialog**

In `checkout_page.dart` add `import '../../core/widgets/zad_dialog.dart';`. Replace the outside-coverage `showDialog<void>(...AlertDialog...)` with a `showZadDialog<void>` (icon `Icons.location_off_outlined`, title `l10n.checkoutOutsideCoverageTitle`, body `l10n.checkoutOutsideCoverageMessage`, actions: primary `zadDialogPrimaryAction(label: l10n.checkoutGoToAddresses, onPressed: () { Navigator.pop(dialogContext); Navigator.pushNamed(context, '/addresses'); })` and a `TextButton` cancel with key `zadDialogSecondary`).

- [ ] **Step 4: Migrate out-of-stock dialog**

Replace the out-of-stock `showDialog<void>(...AlertDialog with the item Column...)` with `showZadDialog<void>` (icon `Icons.remove_shopping_cart_outlined`, title `l10n.checkoutOutOfStockTitle`, `contentBuilder` returning the existing message + item-list `Column`, actions: primary `zadDialogPrimaryAction(label: l10n.checkoutRefreshBasket, onPressed: ...existing refresh+pop...)`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/features/checkout/checkout_page_test.dart`
Expected: PASS (the pre-existing unrelated idempotency failure — see repo notes — may remain; all dialog tests pass).

- [ ] **Step 6: Commit**

```bash
cd ~/Flutter/zad
git add lib/features/checkout/checkout_page.dart test/features/checkout/checkout_page_test.dart
git commit -m "refactor(ui): checkout out-of-stock + outside-coverage use Zad dialogs"
```

---

## Task 6: Bottom sheet system — `showZadSheet`

**Files:**
- Create: `lib/core/widgets/zad_bottom_sheet.dart`
- Test: `test/core/widgets/zad_bottom_sheet_test.dart`

**Interfaces:**
- Consumes: tokens (Task 1).
- Produces: `Future<T?> showZadSheet<T>(BuildContext, {required WidgetBuilder builder, String? title, bool isScrollControlled = true})`. Renders a 4px grabber handle (`Key('zadSheetHandle')`), `ZadRadii.sheet` top corners, optional title header, safe-area + keyboard-inset aware padding.

- [ ] **Step 1: Write the failing test**

Create `test/core/widgets/zad_bottom_sheet_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/core/widgets/zad_bottom_sheet.dart';

void main() {
  testWidgets('shows grabber + title and returns the builder result', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      theme: zadTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showZadSheet<String>(
                  context,
                  title: 'Sort by',
                  builder: (sheetContext) => ElevatedButton(
                    key: const Key('pick'),
                    onPressed: () => Navigator.pop(sheetContext, 'price'),
                    child: const Text('Price'),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zadSheetHandle')), findsOneWidget);
    expect(find.text('Sort by'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pick')));
    await tester.pumpAndSettle();
    expect(result, 'price');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/core/widgets/zad_bottom_sheet_test.dart`
Expected: FAIL — `showZadSheet` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/core/widgets/zad_bottom_sheet.dart`:

```dart
import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme.dart';

/// Branded modal bottom sheet: a grabber handle, [ZadRadii.sheet] top corners,
/// white surface, safe-area + keyboard-inset aware padding, and an optional
/// [title] header. Core-only imports.
Future<T?> showZadSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: ZadColors.white,
    barrierColor: ZadColors.scrim,
    elevation: ZadElevation.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZadRadii.sheet)),
    ),
    builder: (sheetContext) {
      final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ZadSpacing.screenPadding,
            10,
            ZadSpacing.screenPadding,
            ZadSpacing.screenPadding + bottomInset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  key: const Key('zadSheetHandle'),
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: ZadColors.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null) ...[
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: ZadColors.ink)),
                const SizedBox(height: 12),
              ],
              builder(sheetContext),
            ],
          ),
        ),
      );
    },
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/core/widgets/zad_bottom_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Flutter/zad
git add lib/core/widgets/zad_bottom_sheet.dart test/core/widgets/zad_bottom_sheet_test.dart
git commit -m "feat(ui): showZadSheet branded bottom sheet with grabber handle"
```

---

## Task 7: Migrate bottom sheets

**Files:**
- Modify: `lib/features/auth/login_required_sheet.dart`, `lib/features/addresses/add_address_nudge_sheet.dart`, `lib/features/home/widgets/sort_sheet.dart`, `lib/features/home/home_page.dart` (its `showModalBottomSheet`)
- Test: their existing tests (e.g. `test/features/*`) — update finders only where a raw sheet finder breaks

**Interfaces:**
- Consumes: `showZadSheet` (Task 6).

- [ ] **Step 1: Update the failing tests**

Run each sheet's test file to see current finders, then update any that asserted the old sheet shape/handle. Behavioural finders (button text, option taps, returned value) stay. Files: `test/features/auth/login_required_sheet_test.dart`, plus any add-address-nudge / sort-sheet tests.

- [ ] **Step 2: Run tests to verify they fail (where finders changed)**

Run: `~/.flutter-sdk/bin/flutter test test/features/auth/login_required_sheet_test.dart`
Expected: FAIL only if a finder was tightened to the new handle; otherwise proceed.

- [ ] **Step 3: Migrate each `showModalBottomSheet` to `showZadSheet`**

For each file, replace the `showModalBottomSheet<...>(context: ..., backgroundColor: ..., shape: ..., isScrollControlled: ..., builder: (ctx) => <content>)` with:

```dart
  await showZadSheet<...>(
    context,
    title: <existing header text or null>,
    builder: (sheetContext) => <the existing content column, minus its own
        handle/padding/rounded-shape which showZadSheet now provides>,
  );
```

Remove each sheet's now-duplicated top padding, manual grabber, and `RoundedRectangleBorder`. Add `import '../../core/widgets/zad_bottom_sheet.dart';` (adjust depth per file). If a sheet had its own title text at the top, pass it as `title:` and delete the inline title widget.

- [ ] **Step 4: Run tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/features/auth/login_required_sheet_test.dart`
Then the home/addresses tests that open sheets.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd ~/Flutter/zad
git add lib/features/auth/login_required_sheet.dart lib/features/addresses/add_address_nudge_sheet.dart lib/features/home/widgets/sort_sheet.dart lib/features/home/home_page.dart test/features/
git commit -m "refactor(ui): bottom sheets use showZadSheet"
```

---

## Task 8: Snackbar system — `showZadSnack` + route `showErrorSnackBar`

**Files:**
- Create: `lib/core/widgets/zad_snack.dart`
- Modify: `lib/core/errors/user_error.dart` (route `showErrorSnackBar` through it)
- Test: `test/core/widgets/zad_snack_test.dart`, `test/core/errors/user_error_test.dart` (unchanged — still maps types)

**Interfaces:**
- Consumes: tokens (Task 1).
- Produces: `enum ZadSnackVariant { success, error, info, warning }`; `void showZadSnack(BuildContext, String message, {ZadSnackVariant variant = ZadSnackVariant.info})`. Root content keyed `Key('zadSnack')`; clears any in-flight snackbar first.

- [ ] **Step 1: Write the failing test**

Create `test/core/widgets/zad_snack_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/core/widgets/zad_snack.dart';

void main() {
  testWidgets('shows the message with a variant icon', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: zadTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showZadSnack(context, 'Saved', variant: ZadSnackVariant.success),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump(); // start the snackbar animation
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byKey(const Key('zadSnack')), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/core/widgets/zad_snack_test.dart`
Expected: FAIL — `showZadSnack` not found.

- [ ] **Step 3: Write the implementation**

Create `lib/core/widgets/zad_snack.dart`:

```dart
import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme.dart';

enum ZadSnackVariant { success, error, info, warning }

({IconData icon, Color color}) _style(ZadSnackVariant v) => switch (v) {
      ZadSnackVariant.success => (icon: Icons.check_circle_outline, color: ZadColors.success),
      ZadSnackVariant.error => (icon: Icons.error_outline, color: ZadColors.danger),
      ZadSnackVariant.info => (icon: Icons.info_outline, color: ZadColors.info),
      ZadSnackVariant.warning => (icon: Icons.warning_amber_rounded, color: ZadColors.warning),
    };

/// Floating, rounded, leading-icon snackbar coloured by [variant]. Uses
/// ScaffoldMessenger.of(context) (caller guards `context.mounted`). Clears any
/// in-flight snackbar first so they never stack.
void showZadSnack(
  BuildContext context,
  String message, {
  ZadSnackVariant variant = ZadSnackVariant.info,
}) {
  final s = _style(variant);
  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ZadColors.white,
      elevation: ZadElevation.snack,
      duration: ZadDurations.snack,
      margin: const EdgeInsets.all(ZadSpacing.screenPadding),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZadRadii.button),
        side: BorderSide(color: s.color.withValues(alpha: 0.35)),
      ),
      content: Row(
        key: const Key('zadSnack'),
        children: [
          Icon(s.icon, color: s.color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 14, color: ZadColors.ink)),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 4: Route `showErrorSnackBar` through it**

In `lib/core/errors/user_error.dart`, replace the body of `showErrorSnackBar`:

```dart
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_exceptions.dart';
import '../widgets/zad_snack.dart';

// ... userErrorMessage unchanged ...

/// Shows [error] as a friendly error SnackBar. Callers must guard
/// `context.mounted`.
void showErrorSnackBar(BuildContext context, Object error) {
  showZadSnack(
    context,
    userErrorMessage(AppLocalizations.of(context), error),
    variant: ZadSnackVariant.error,
  );
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/core/widgets/zad_snack_test.dart test/core/errors/user_error_test.dart`
Expected: PASS (user_error_test still validates the type→message mapping; the snackbar now renders via showZadSnack).

- [ ] **Step 6: Commit**

```bash
cd ~/Flutter/zad
git add lib/core/widgets/zad_snack.dart lib/core/errors/user_error.dart test/core/widgets/zad_snack_test.dart
git commit -m "feat(ui): showZadSnack floating variant snackbars; route showErrorSnackBar"
```

---

## Task 9: Migrate success/info snackbar call sites

**Files:**
- Modify: `lib/features/addresses/address_form_page.dart`, `lib/features/addresses/address_list_page.dart`, `lib/features/basket/basket_page.dart`, `lib/features/checkout/checkout_page.dart`, `lib/features/profile/profile_tab.dart`, `lib/features/profile/change_password_page.dart`, `lib/features/auth/reset_password_page.dart`, `lib/features/product/product_detail_page.dart`, `lib/features/home/widgets/product_card.dart`, `lib/features/home/widgets/cart_fly.dart`, `lib/core/stores/cart_store.dart`, `lib/core/widgets/cart_warnings_listener.dart`, `lib/app.dart`
- Test: affected feature tests — update snackbar text finders if a test asserted a raw `SnackBar`

**Interfaces:**
- Consumes: `showZadSnack` (Task 8).

- [ ] **Step 1: Update failing tests (only where a test targets a snackbar)**

Run the full suite once and note tests that find snackbar text; those still pass (text unchanged) unless they asserted `find.byType(SnackBar)` structure. For structure-based finders, target `find.byKey(const Key('zadSnack'))` or the message text. List them from:
`~/.flutter-sdk/bin/flutter test 2>&1 | grep -i snack` (inspect matches).

- [ ] **Step 2: Replace each plain snackbar**

For every `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(<msg>)))` that is NOT an error path, replace with `showZadSnack(context, <msg>, variant: <success|info|warning>)`. Guidance:
- Saved / success / copied / password-changed / added-to-basket / delete-account-success ⇒ `ZadSnackVariant.success`.
- Cart-sync-failed / soft warnings ⇒ `ZadSnackVariant.warning`.
- Neutral notices ⇒ `ZadSnackVariant.info`.
Add `import '../../core/widgets/zad_snack.dart';` (adjust depth) per file. Leave already-error paths that call `showErrorSnackBar` untouched (Task 8 handles them).

- [ ] **Step 3: Run the full suite**

Run: `~/.flutter-sdk/bin/flutter test`
Expected: PASS except the known pre-existing unrelated failures (basket/checkout error-snackbar assertions from the friendly-errors refactor; document, don't fix here).

- [ ] **Step 4: Commit**

```bash
cd ~/Flutter/zad
git add lib/ test/
git commit -m "refactor(ui): success/info/warning snackbars use showZadSnack"
```

---

## Task 10: Design-system standards doc + audit report

**Files:**
- Create: `docs/design-system/README.md`
- Create: `docs/design-system/2026-07-23-popup-audit.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Write the standards doc**

Create `docs/design-system/README.md` covering, verbatim from the spec's "Standards & roles" section: tokens (the single source; no raw hex/`Colors.*`/magic numbers), when-to-use (dialog = blocking decision; sheet = choice/short form; snackbar = transient feedback, never a blocking error), action hierarchy (one primary; destructive = red filled; cancel = text; primary last), accessibility (≥48px targets, semantics/tooltip labels, contrast ≥4.5:1, `barrierDismissible` only for non-destructive), RTL & localization (l10n copy, logical insets, verify `ar`), motion (`ZadDurations`/`ZadCurves`), layering (`core/widgets` ⊅ `features/**`), and the consistency rule (no raw `AlertDialog`/`SimpleDialog`/`showModalBottomSheet`/`SnackBar`). Include a short "Components" table pointing to `showZadConfirm`/`showZadDialog`/`showZadSheet`/`showZadSnack` with one-line usage each. Note dark mode + `ZadPrimaryButton` relocation + a CI lint as future work.

- [ ] **Step 2: Write the audit report**

Create `docs/design-system/2026-07-23-popup-audit.md` listing the 8 audit items from the spec, each with: the issue, where it occurred (files), the fix applied (which task/component), and status (Fixed). Add any additional issues found during migration (e.g. mounted-guard gaps, occluded snackbars) with the same fields.

- [ ] **Step 3: Commit**

```bash
cd ~/Flutter/zad
git add docs/design-system/
git commit -m "docs(design): popup design-system standards + audit report"
```

---

## Task 11: Full-suite verification (analyze + tests + manual)

**Files:** none (verification only).

- [ ] **Step 1: Analyze**

Run: `cd ~/Flutter/zad && ~/.flutter-sdk/bin/flutter analyze`
Expected: no NEW issues (pre-existing `cart_fly_wiring_test` unused-import warning, if still present, is unrelated). Fix any new warning introduced by this work.

- [ ] **Step 2: Full test suite**

Run: `~/.flutter-sdk/bin/flutter test`
Expected: all pass EXCEPT the documented pre-existing unrelated failures (basket ×4 + checkout ×1 friendly-errors message assertions; `cart_fly_wiring`/`home_async` order-pollution flakes that pass in isolation). Confirm every migrated popup's tests are green and no NEW failures were introduced (compare against the baseline set).

- [ ] **Step 3: Manual pass in the running app (light + Arabic)**

Use the `run` skill (or `~/.flutter-sdk/bin/flutter run`) and exercise, in both `en` and `ar`: clear basket, delete address, logout, delete account (checkbox gate), language picker, checkout out-of-stock + outside-coverage, login-required sheet, sort sheet, add-address nudge, and a success + an error snackbar. Verify: 28px dialogs with icon badge, red destructive primary, scale+fade entrance; sheets show the grabber; snackbars float above the CTA bar with the right variant icon; everything mirrors correctly in Arabic. Screenshot one dialog + one snackbar for the record.

- [ ] **Step 4: Final commit (if manual pass required tweaks)**

```bash
cd ~/Flutter/zad
git add lib/ docs/
git commit -m "fix(ui): popup polish from manual light/Arabic pass"
```

---

## Self-review notes

- **Spec coverage:** tokens+theme → Task 1; dialog components → Task 2; dialog migrations → Tasks 3–5 (basket/address, profile, checkout); sheet component → Task 6; sheet migrations → Task 7; snackbar component + error routing → Task 8; snackbar migrations → Task 9; standards doc + audit → Task 10; verification (analyze/tests/manual light+ar) → Task 11. Every spec section maps to a task.
- **Type consistency:** `showZadConfirm`/`showZadDialog`/`zadDialogPrimaryAction` (Task 2) reused verbatim in Tasks 3–5; `showZadSheet` (Task 6) in Task 7; `showZadSnack`/`ZadSnackVariant` (Task 8) in Tasks 8–9. Keys `zadDialogPrimary`/`zadDialogSecondary`/`zadSheetHandle`/`zadSnack` consistent across component + migration + test tasks.
- **No placeholders:** component and test steps carry complete code; migration steps show the exact replacement call and the imports to add. Where a migration depends on an existing l10n key whose exact name must be read from current code (e.g. delete-account message/button), the step says to use the existing key verbatim rather than inventing one.
