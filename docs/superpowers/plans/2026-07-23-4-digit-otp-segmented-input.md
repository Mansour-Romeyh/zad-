# 4-digit OTP + Segmented Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WhatsApp OTP codes become 4 digits, and the OTP entry UI becomes a per-digit segmented input on both the registration and password-reset screens.

**Architecture:** OTP length is already setting-driven on the backend (`WASender Settings.otp_length` → `_generate_otp`), so the backend change is a settings value (+ seed default), no generator rewrite. The frontend gets one new shared `ZadOtpField` widget (a `FormField<String>` rendering N single-digit boxes that mirror their combined value into the screen's existing `TextEditingController`), wired into both auth screens, with copy updated 6→4.

**Tech Stack:** Flutter/Dart (`flutter_test`), Frappe/Python backend (`grocery`, branch `version-16`). Flutter binary: `~/.flutter-sdk/bin/flutter`. Backend repo: `~/Frappe/grocery-bench/apps/grocery`.

## Global Constraints

- Flutter binary is not on PATH — run it as `~/.flutter-sdk/bin/flutter`.
- 15GB-RAM machine: run widget tests only; never trigger an Android/Gradle build during implementation.
- Single source of truth for OTP length on the app side: `const kOtpLength = 4` in `lib/core/constants.dart`. No hardcoded `4`/`6` for OTP length anywhere else in the app.
- Design tokens: `ZadColors` (`lib/core/theme.dart`), `ZadRadii.button` (`lib/core/constants.dart`). OTP boxes must match `ZadTextField`'s look (surface fill + `ZadRadii.button` radius).
- OTP digits render **left-to-right even under `ar`** — the boxes are wrapped in a forced-LTR `Directionality` (the app's Western-digit convention).
- **Lockstep release constraint:** the 4-box app only accepts 4-digit codes. The backend `WASender Settings.otp_length` must be set to 4 (dev + prod) *before or with* the app release. Backend-first is safe (the old app's `maxLength: 6` still accepts a 4-digit entry); the app must not lead the backend.
- Backend tests pollute the dev site — run only the one focused test named in the backend task, not the whole suite.

---

### Task 1: `kOtpLength` + shared `ZadOtpField` widget

**Files:**
- Modify: `lib/core/constants.dart`
- Create: `lib/features/auth/widgets/zad_otp_field.dart`
- Test: `test/features/auth/widgets/zad_otp_field_test.dart`

**Interfaces:**
- Consumes: `ZadColors` (`lib/core/theme.dart`), `ZadRadii.button` + `kOtpLength` (`lib/core/constants.dart`).
- Produces: `const kOtpLength = 4;` and
  `ZadOtpField({required TextEditingController controller, VoidCallback? onCompleted, int length = kOtpLength, String? Function(String?)? validator, String? semanticsLabel, Key? key})`.
  It renders `length` single-digit `TextField` boxes; mirrors the combined code into `controller` on every change; fires `onCompleted` when all boxes are filled; participates in the enclosing `Form` via `FormField<String>` (validation + error text).

- [ ] **Step 1: Add the length constant**

In `lib/core/constants.dart`, inside the existing `ZadSpacing`/`ZadRadii` area (top-level, after the `ZadRadii` class), add:

```dart
/// Number of digits in a WhatsApp OTP — drives both the segmented input's box
/// count and its "complete" validation. Must match the backend
/// `WASender Settings.otp_length`.
const int kOtpLength = 4;
```

- [ ] **Step 2: Write the failing widget test**

Create `test/features/auth/widgets/zad_otp_field_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/features/auth/widgets/zad_otp_field.dart';

import '../../../helpers.dart';

Widget _harness(TextEditingController controller, {VoidCallback? onCompleted}) => wrapPage(
      Scaffold(
        body: Form(
          child: ZadOtpField(controller: controller, onCompleted: onCompleted),
        ),
      ),
    );

void main() {
  testWidgets('renders kOtpLength boxes', (tester) async {
    await tester.pumpWidget(_harness(TextEditingController()));
    expect(find.byType(TextField), findsNWidgets(kOtpLength));
  });

  testWidgets('entering the full code distributes across boxes, syncs the '
      'controller, and fires onCompleted once', (tester) async {
    final controller = TextEditingController();
    var completed = 0;
    await tester.pumpWidget(_harness(controller, onCompleted: () => completed++));

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pump();

    expect(controller.text, '1234');
    for (var i = 0; i < kOtpLength; i++) {
      expect(tester.widget<TextField>(find.byType(TextField).at(i)).controller!.text, '${i + 1}');
    }
    expect(completed, 1);
  });

  testWidgets('non-digits are filtered; a mixed string still yields the code', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_harness(controller));

    await tester.enterText(find.byType(TextField).first, '12ab34');
    await tester.pump();

    expect(controller.text, '1234');
  });

  testWidgets('typing a digit advances focus to the next box', (tester) async {
    await tester.pumpWidget(_harness(TextEditingController()));

    await tester.enterText(find.byType(TextField).at(0), '7');
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField).at(1)).focusNode!.hasFocus, isTrue);
  });

  testWidgets('backspace on an empty box clears and focuses the previous box', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_harness(controller));

    // Fill box 0 -> focus advances to the empty box 1.
    await tester.enterText(find.byType(TextField).at(0), '7');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, '');
    expect(tester.widget<TextField>(find.byType(TextField).at(0)).focusNode!.hasFocus, isTrue);
    expect(controller.text, '');
  });

  testWidgets('digits stay left-to-right under an ar locale (forced LTR)', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(wrapPage(
      Scaffold(body: Form(child: ZadOtpField(controller: controller))),
      locale: const Locale('ar'),
    ));

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pump();

    // Box order maps to code order, and the boxes sit under a forced-LTR wrap.
    expect(controller.text, '1234');
    final dir = tester.widget<Directionality>(
      find.ancestor(of: find.byType(TextField).first, matching: find.byType(Directionality)).first,
    );
    expect(dir.textDirection, TextDirection.ltr);
  });
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/features/auth/widgets/zad_otp_field_test.dart`
Expected: FAIL — `zad_otp_field.dart` / `ZadOtpField` does not exist.

- [ ] **Step 4: Implement the widget**

Create `lib/features/auth/widgets/zad_otp_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';

/// A segmented OTP input: [length] single-digit boxes styled like the app's
/// `ZadTextField` (surface fill, [ZadRadii.button] radius). Typing a digit
/// auto-advances to the next box; backspace on an empty box steps back and
/// clears the previous digit; entering or pasting the full code into any box
/// distributes the digits across every box. The combined code is mirrored into
/// [controller] on every change, and [onCompleted] fires once all [length]
/// boxes hold a digit.
///
/// A [FormField] so an enclosing [Form]'s validate()/error display keeps
/// working; the boxes are plain [TextField]s (validation lives on the
/// FormField), so a test can drive the whole field via
/// `find.byType(TextField).first`.
///
/// Wrapped in a forced-LTR [Directionality] so an Arabic UI keeps the digits in
/// left-to-right order (the app's Western-digit convention for numbers).
class ZadOtpField extends StatefulWidget {
  const ZadOtpField({
    required this.controller,
    this.onCompleted,
    this.length = kOtpLength,
    this.validator,
    this.semanticsLabel,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback? onCompleted;
  final int length;
  final String? Function(String?)? validator;
  final String? semanticsLabel;

  @override
  State<ZadOtpField> createState() => _ZadOtpFieldState();
}

class _ZadOtpFieldState extends State<ZadOtpField> {
  late final List<TextEditingController> _boxes;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _boxes = List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());
    // Seed the boxes from any value already on the shared controller.
    final seed = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < widget.length && i < seed.length; i++) {
      _boxes[i].text = seed[i];
    }
  }

  @override
  void dispose() {
    for (final c in _boxes) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _boxes.map((c) => c.text).join();

  void _sync(FormFieldState<String> field) {
    final code = _code;
    widget.controller.text = code;
    field.didChange(code);
    if (code.length == widget.length) {
      widget.onCompleted?.call();
    }
  }

  /// Spread [digits] across the boxes from box 0 (paste / full-code entry),
  /// then focus the first empty box, or the last box when full.
  void _distribute(String digits) {
    for (var i = 0; i < widget.length; i++) {
      _boxes[i].text = i < digits.length ? digits[i] : '';
    }
    final target = digits.length >= widget.length ? widget.length - 1 : digits.length;
    _nodes[target].requestFocus();
  }

  void _onChanged(int i, String raw, FormFieldState<String> field) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= widget.length) {
      // Paste / full-code entry into a box: distribute across all boxes.
      _distribute(digits.substring(0, widget.length));
    } else if (digits.isEmpty) {
      _boxes[i].text = '';
    } else {
      // Keep just the latest digit in this box, then advance.
      final d = digits[digits.length - 1];
      if (_boxes[i].text != d) {
        _boxes[i].value = TextEditingValue(
          text: d,
          selection: const TextSelection.collapsed(offset: 1),
        );
      }
      if (i < widget.length - 1) {
        _nodes[i + 1].requestFocus();
      }
    }
    _sync(field);
  }

  KeyEventResult _onKey(int i, KeyEvent event, FormFieldState<String> field) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _boxes[i].text.isEmpty &&
        i > 0) {
      _boxes[i - 1].text = '';
      _nodes[i - 1].requestFocus();
      _sync(field);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: _code,
      validator: widget.validator,
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Semantics(
                label: widget.semanticsLabel,
                textField: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      _buildBox(i, field),
                    ],
                  ],
                ),
              ),
            ),
            if (field.errorText != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  field.errorText!,
                  style: const TextStyle(color: ZadColors.errorText, fontSize: 12),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBox(int i, FormFieldState<String> field) {
    return SizedBox(
      width: 56,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) => _onKey(i, event, field),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ZadColors.surface,
            borderRadius: BorderRadius.circular(ZadRadii.button),
          ),
          child: TextField(
            controller: _boxes[i],
            focusNode: _nodes[i],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: ZadColors.ink,
            ),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 16),
            ),
            onChanged: (v) => _onChanged(i, v, field),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/features/auth/widgets/zad_otp_field_test.dart`
Expected: PASS (6 tests). If the backspace test fails because the platform key event is consumed by the field, report it — do not weaken the assertion.

- [ ] **Step 6: Analyze**

Run: `~/.flutter-sdk/bin/flutter analyze lib/core/constants.dart lib/features/auth/widgets/zad_otp_field.dart test/features/auth/widgets/zad_otp_field_test.dart`
Expected: No issues.

---

### Task 2: Wire `ZadOtpField` into registration (`otp_page.dart`)

**Files:**
- Modify: `lib/features/auth/otp_page.dart`
- Modify: `test/features/auth/otp_page_test.dart`
- Modify: `test/data/auth_repository_test.dart`, `test/core/session/session_store_test.dart` (OTP literal truthfulness)

**Interfaces:**
- Consumes: `ZadOtpField`, `kOtpLength` (Task 1).
- Produces: registration screen auto-verifies when 4 digits are entered; `_submit` is guarded against double-submission.

- [ ] **Step 1: Establish the green baseline**

Run: `~/.flutter-sdk/bin/flutter test test/features/auth/otp_page_test.dart`
Expected: PASS (baseline before change).

- [ ] **Step 2: Guard `_submit` against re-entry**

In `lib/features/auth/otp_page.dart`, at the top of `Future<void> _submit() async {`, add a re-entry guard as the first line (before the validate check) so auto-verify + a manual Verify tap can't double-submit:

```dart
  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
```

- [ ] **Step 3: Swap the field for `ZadOtpField`**

In `lib/features/auth/otp_page.dart`, replace the `ZadTextField(...)` block (the OTP input, currently `controller: _otpController … maxLength: 6 … length != 6 …`) with:

```dart
                ZadOtpField(
                  controller: _otpController,
                  onCompleted: _submit,
                  semanticsLabel: l10n.authOtpHint,
                  validator: (value) => (value == null || value.length != kOtpLength)
                      ? l10n.authFieldRequired
                      : null,
                ),
```

- [ ] **Step 4: Fix imports**

In `lib/features/auth/otp_page.dart`, replace the `import 'widgets/zad_text_field.dart';` line with `import 'widgets/zad_otp_field.dart';`. Keep `import '../../core/constants.dart';` (it now also supplies `kOtpLength`; it was already imported for `ZadSpacing`). Confirm `zad_text_field.dart` is no longer referenced in this file.

- [ ] **Step 5: Update the screen test**

In `test/features/auth/otp_page_test.dart`:
- Replace the two occurrences of
  ```dart
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Verify'));
  ```
  with (auto-verify fires on the 4th digit, so no Verify tap is needed):
  ```dart
      await tester.enterText(find.byType(TextField).first, '1234');
  ```
  (Leave the following `await tester.pumpAndSettle();` and the assertions unchanged — the "correct code" test still expects `HOME_MARKER`; the "expired OTP" test still expects the error banner.)

- [ ] **Step 6: Update length-agnostic data tests (truthfulness)**

In `test/data/auth_repository_test.dart` (the `register`/`verify_and_register` cases) and `test/core/session/session_store_test.dart`, change the OTP literals from `'123456'` to `'1234'` where the value is a *registration* OTP (`otp: '123456'`, and the asserted posted `'otp': '123456'`). These are forwarded verbatim to the fake server, so this is a truthfulness update, not a behavior change. (The reset-password OTP literal at `auth_repository_test.dart:164/170` is updated in Task 3.)

- [ ] **Step 7: Run tests + analyze**

Run: `~/.flutter-sdk/bin/flutter test test/features/auth/otp_page_test.dart test/data/auth_repository_test.dart test/core/session/session_store_test.dart`
Expected: PASS.
Run: `~/.flutter-sdk/bin/flutter analyze lib/features/auth/otp_page.dart`
Expected: No issues (no unused `zad_text_field` import).

---

### Task 3: Wire `ZadOtpField` into password reset (`reset_password_page.dart`)

**Files:**
- Modify: `lib/features/auth/reset_password_page.dart`
- Modify: `test/features/auth/reset_password_page_test.dart`
- Modify: `test/data/auth_repository_test.dart` (reset OTP literal)

**Interfaces:**
- Consumes: `ZadOtpField`, `kOtpLength` (Task 1).
- Produces: reset screen's OTP entry is segmented; completing the code focuses the new-password field (reset still needs a password before submit).

- [ ] **Step 1: Establish the green baseline**

Run: `~/.flutter-sdk/bin/flutter test test/features/auth/reset_password_page_test.dart`
Expected: PASS.

- [ ] **Step 2: Add a new-password FocusNode**

In `lib/features/auth/reset_password_page.dart`, add a focus node beside the controllers (after `_newPasswordController`):

```dart
  final _newPasswordFocus = FocusNode();
```

and dispose it in `dispose()` (after `_newPasswordController.dispose();`):

```dart
    _newPasswordFocus.dispose();
```

- [ ] **Step 3: Swap the OTP field and attach the focus node to the password field**

In `_otpAndPasswordStep`, replace the OTP `ZadTextField(...)` block (`controller: _otpController … maxLength: 6 … length != 6 …`) with:

```dart
          ZadOtpField(
            controller: _otpController,
            onCompleted: _newPasswordFocus.requestFocus,
            semanticsLabel: l10n.authOtpHint,
            validator: (value) => (value == null || value.length != kOtpLength)
                ? l10n.authFieldRequired
                : null,
          ),
```

and on the new-password `ZadTextField` (the one with `controller: _newPasswordController`), add the focus node parameter:

```dart
          ZadTextField(
            controller: _newPasswordController,
            focusNode: _newPasswordFocus,
            hintText: l10n.authNewPasswordLabel,
            obscureText: true,
            validator: _requiredValidator,
          ),
```

- [ ] **Step 4: Add a `focusNode` param to `ZadTextField`**

`ZadTextField` (`lib/features/auth/widgets/zad_text_field.dart`) does not currently accept a `focusNode`. Add it:
- In the constructor params: `this.focusNode,` (after `this.autofocus = false,` or anywhere sensible).
- Field declaration: `final FocusNode? focusNode;`
- Pass it to the inner `TextFormField`: add `focusNode: widget.focusNode,` (next to `controller: widget.controller,`).

- [ ] **Step 5: Add the `ZadOtpField` import**

In `lib/features/auth/reset_password_page.dart`, add `import 'widgets/zad_otp_field.dart';` (keep `zad_text_field.dart` — the password/new-password fields still use it). Confirm `../../core/constants.dart` is imported (it is, for `ZadSpacing`) so `kOtpLength` resolves.

- [ ] **Step 6: Update the screen test**

In `test/features/auth/reset_password_page_test.dart`, in the two step-2 cases ("submitting OTP and new password…" and "wrong OTP on the reset step…"), replace:
```dart
    await tester.enterText(find.byType(TextFormField).at(0), '123456');   // or '000000'
    await tester.enterText(find.byType(TextFormField).at(1), 'n3wp@ss');
```
with (OTP boxes are `TextField`s; the only `TextFormField` left in step 2 is the password field):
```dart
    await tester.enterText(find.byType(TextField).first, '1234');   // or '0000'
    await tester.enterText(find.byType(TextFormField), 'n3wp@ss');
```
Leave the phone-step lines (`find.byType(TextFormField).first`, `'7701234567'`) unchanged.

- [ ] **Step 7: Update the reset data-test literal**

In `test/data/auth_repository_test.dart`, the `resetPassword` case (~line 164/170): change `otp: '123456'` and the asserted `'otp': '123456'` to `'1234'` (length-agnostic forward; truthfulness).

- [ ] **Step 8: Run tests + analyze**

Run: `~/.flutter-sdk/bin/flutter test test/features/auth/reset_password_page_test.dart test/features/auth/register_page_test.dart test/data/auth_repository_test.dart`
Expected: PASS.
Run: `~/.flutter-sdk/bin/flutter analyze lib/features/auth/reset_password_page.dart lib/features/auth/widgets/zad_text_field.dart`
Expected: No issues.

---

### Task 4: Copy — "6-digit" → "4-digit" (en + ar)

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`
- Regenerate: `lib/l10n/app_localizations*.dart`

**Interfaces:** no code interface change; only the two OTP strings' text changes. No keys added/removed.

- [ ] **Step 1: Edit the English strings**

In `lib/l10n/app_en.arb`:
- `"authOtpInstructions": "Enter the 6-digit code sent to {phone}"` → `"Enter the 4-digit code sent to {phone}"`
- `"authOtpHint": "6-digit code"` → `"4-digit code"`

- [ ] **Step 2: Edit the Arabic strings**

In `lib/l10n/app_ar.arb`:
- `"authOtpInstructions": "أدخل الرمز المكوّن من 6 أرقام المُرسل إلى {phone}"` → replace `6` with `4`.
- `"authOtpHint": "رمز مكوّن من 6 أرقام"` → replace `6` with `4`.

- [ ] **Step 3: Regenerate localizations**

Run: `~/.flutter-sdk/bin/flutter gen-l10n`
Expected: regenerates `lib/l10n/app_localizations_en.dart` / `_ar.dart` with the new text. Confirm the generated files now say "4-digit" / "4 أرقام" (grep them).

- [ ] **Step 4: Analyze**

Run: `~/.flutter-sdk/bin/flutter analyze lib/l10n/`
Expected: No issues.

---

### Task 5: Backend — `otp_length` → 4 (`grocery`, version-16)

**Files (backend repo `~/Frappe/grocery-bench/apps/grocery`):**
- Modify: `grocery/seed.py`
- Modify/Test: `grocery/tests/test_auth.py` (focused generator assertion)

**Interfaces:** no Python API change; `_generate_otp(length)` already honors its argument.

- [ ] **Step 1: Change the seeded default**

In `grocery/seed.py`, in `_seed_wasender_settings`, change `settings.otp_length = 6` to `settings.otp_length = 4`.

- [ ] **Step 2: Add a focused generator test**

In `grocery/tests/test_auth.py`, add a test method to the existing test class (locate the primary `FrappeTestCase` subclass in the file) that pins the generator's length behavior:

```python
	def test_generate_otp_respects_configured_length(self):
		from grocery.services.wasender import _generate_otp

		otp = _generate_otp(4)
		self.assertEqual(len(otp), 4)
		self.assertTrue(otp.isdigit())
```

- [ ] **Step 3: Run only this focused test**

From the bench directory (`~/Frappe/grocery-bench`), run just the new test (backend tests pollute the dev site — do not run the whole suite):

Run: `cd ~/Frappe/grocery-bench && bench --site grocery.localhost run-tests --module grocery.tests.test_auth --test test_generate_otp_respects_configured_length`
Expected: 1 test, PASS. (If the exact runner invocation differs in this bench, report it rather than running the full suite.)

- [ ] **Step 4: Runtime settings update (ops, not code) — DOCUMENT for the user**

The seed default only affects *fresh* seeds. To make an existing site send 4-digit codes, `WASender Settings.otp_length` must be set to 4 in that site's DB:
- **Dev (`grocery.localhost`):** `cd ~/Frappe/grocery-bench && bench --site grocery.localhost console`, then run `frappe.db.set_single_value("WASender Settings", "otp_length", 4); frappe.db.commit()`.
- **Prod (`zad.micronext.net`):** an admin sets **WASender Settings → OTP Length = 4** (must be done before/with the app release — see the lockstep constraint).

Do not perform the prod change here; surface it to the user as the required deploy step.

---

## Verification (manual, after all tasks)

Per the `verify`/`run` skills, once the suite is green: launch the app, go to Register → request OTP, and confirm the OTP screen shows **4 boxes**, that typing auto-advances, backspace steps back, pasting a code fills all four, and that filling the 4th digit auto-verifies. Repeat on Forgot-Password (4 boxes; completing the code jumps to the New Password field). Check `ar` keeps the digits left-to-right. Confirm the running backend site's `WASender Settings.otp_length` is 4 so the delivered code length matches.

Full app suite green: `~/.flutter-sdk/bin/flutter test`; analyze clean: `~/.flutter-sdk/bin/flutter analyze`.
