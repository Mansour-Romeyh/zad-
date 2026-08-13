# 4-digit WhatsApp OTP + segmented (per-digit) input

**Date:** 2026-07-23
**Status:** Approved (design), pending implementation plan
**Repos:** frontend = this repo (`feature/zad-mvp`); backend = `grocery` (`~/Frappe/grocery-bench/apps/grocery`, branch `version-16`)

## Problem

1. WhatsApp OTP codes are 6 digits; the product now wants **4-digit** codes.
2. The OTP entry UI is a single text field. The product wants a **segmented
   input** — one box per digit.

## Current state

**Backend** — OTP length is already setting-driven:
- `grocery/services/wasender.py:_generate_otp(length)` builds an OTP of the given
  length; `send_otp(...)` calls `_generate_otp(cint(settings.otp_length))`.
- Verification (`api/auth.py`) compares the entered code to the stored **hash**,
  so it is length-agnostic — no hardcoded `6` on the verify path.
- Default is seeded: `grocery/seed.py:306` → `settings.otp_length = 6`.

**Frontend** — a single `ZadTextField` with `maxLength: 6` and a
`length != 6` validator, on two screens sharing the same l10n strings:
- `lib/features/auth/otp_page.dart` (registration OTP; `_otpController`, in a `Form`).
- `lib/features/auth/reset_password_page.dart` (password-reset OTP + new password).
- Copy: `authOtpInstructions` ("Enter the 6-digit code sent to {phone}"),
  `authOtpHint` ("6-digit code") — en + ar.
- No pin/OTP package installed.

## Decision

- Make codes 4 digits by setting `otp_length = 4` (no generator rewrite).
- Replace the single OTP field with a **custom** 4-box segmented widget (no new
  dependency), used on **both** screens.
- **Auto-verify** on the 4th digit for registration; on reset, auto-complete
  advances focus to the new-password field (reset still needs a password).

## Approach

### 1. Backend — `otp_length` → 4

- `grocery/seed.py:306`: `settings.otp_length = 6` → `4` (dev-site default).
- **Production**: an admin sets **WASender Settings → OTP Length = 4** (the
  `otp_length` field on the `WASender Settings` single). This is an ops/config
  step, not code.
- No change to `_generate_otp`, `send_otp`, or the verify path.
- Test: add/confirm an assertion that `_generate_otp(4)` returns a 4-character
  numeric string (existing `test_auth.py` sets `otp_length` explicitly, so it
  stays green regardless of the seed default).

⚠️ **Lockstep release constraint:** the 4-box app only accepts 4-digit codes.
Until the prod backend `otp_length` is set to 4, prod still sends 6-digit codes
and users of the new app cannot log in. The app release and the prod setting
change must go together. `otp_length = 4` on the backend with the *old* app is
harmless (old app's `maxLength: 6` still accepts a 4-digit entry), so the
backend setting can safely lead; the **app** must not lead the backend.

### 2. Frontend — shared segmented widget `ZadOtpField`

New file: `lib/features/auth/widgets/zad_otp_field.dart`.

- Renders `kOtpLength` (= 4) single-digit boxes, styled to match `ZadTextField`
  (same border radius, border/fill, and focus color from the theme).
- Wrapped in a forced-**LTR** `Directionality` so Arabic keeps digit order
  left-to-right (consistent with the app's Western-digit convention for numbers,
  see `constants.dart:formatPrice`).
- Each box: `TextInputType.number`, `FilteringTextInputFormatter.digitsOnly`,
  one character.
- Behaviour:
  - Typing a digit fills the current box and **auto-advances** to the next.
  - **Backspace** on an empty box moves to the previous box and clears it.
  - **Entering/pasting a full code** into the first box **distributes** the
    digits across all boxes (this doubles as the test entry path).
  - The combined value is written into the parent's existing
    `TextEditingController` on every change.
  - When all `kOtpLength` boxes are filled, fire `onCompleted`.
- Implemented as a `FormField<String>` (value = combined code) so each screen's
  existing `Form` + `_formKey.currentState!.validate()` + inline error text keep
  working. Validator: non-null, `length == kOtpLength`, else `authFieldRequired`.
- Single source of truth for length: `const kOtpLength = 4` (in
  `lib/core/constants.dart`).

**Widget API (interface later tasks depend on):**
```dart
ZadOtpField({
  required TextEditingController controller, // parent's OTP controller (source of combined value)
  VoidCallback? onCompleted,                 // fired once all kOtpLength boxes are filled
  int length = kOtpLength,
  Key? key,
})
```

### 3. Wire into both screens

- `otp_page.dart`: replace the `ZadTextField` block with
  `ZadOtpField(controller: _otpController, onCompleted: _submit)`. The existing
  `_submit`, `Form`, error banner, resend cooldown button, and **Verify button**
  are unchanged. Auto-verify = `onCompleted` calls `_submit`.
- `reset_password_page.dart`: replace its OTP `ZadTextField` (which already uses
  `_otpController`) with `ZadOtpField(controller: _otpController, onCompleted:
  ...)`. Add a `FocusNode _newPasswordFocus` (disposed with the others) attached
  to the new-password `ZadTextField`; `onCompleted` calls
  `_newPasswordFocus.requestFocus()` so completing the code advances to the
  password field rather than submitting. The new-password field, validators, and
  Reset button are otherwise unchanged.

### 4. Copy (l10n)

- `authOtpInstructions`: "Enter the 6-digit code sent to {phone}" →
  "Enter the 4-digit code sent to {phone}" (en + ar).
- `authOtpHint`: "6-digit code" → "4-digit code" (en + ar). The boxes have no
  visible hint; the string is repurposed as the widget's accessibility/semantics
  label.
- Regenerate `app_localizations*` via the l10n toolchain.

## Data flow

No change to network calls or navigation. `ZadOtpField` writes into the same
`TextEditingController` the screens already read, and the same `otp` string is
posted to the backend. The backend generates/sends a shorter code; verify is
unchanged.

## Error / edge handling

- Non-digit input is filtered per box.
- Incomplete code → `FormField` validator blocks submit with the existing
  inline error.
- Paste of a code longer than `kOtpLength` → take the first `kOtpLength` digits.
- Backspace focus/clear handled explicitly (see behaviour above).

## Testing

**Frontend**
- New `test/features/auth/widgets/zad_otp_field_test.dart`:
  - renders exactly `kOtpLength` boxes;
  - typing a digit advances focus; backspace on empty moves back and clears;
  - entering a full code into the first box distributes across boxes and sets
    the controller to the full code;
  - `onCompleted` fires exactly when the last box is filled;
  - non-digits are rejected;
  - digit order is left-to-right under an `ar` locale (LTR wrap).
- Update `test/features/auth/otp_page_test.dart` and
  `test/features/auth/reset_password_page_test.dart` to enter `'1234'` (via the
  first-box distribute path) and assert verify/reset proceeds; adjust any
  `maxLength`/`length` expectations to 4.
- Data-layer tests (`test/data/auth_repository_test.dart`,
  `test/core/session/session_store_test.dart`) forward the OTP verbatim and are
  length-agnostic; switch their `'123456'` literals to `'1234'` for truthfulness
  (not gating).
- Full `flutter test` stays green; `flutter analyze` clean.

**Backend**
- Existing `test_auth.py` / `test_account_deletion.py` set `otp_length`
  explicitly and extract the OTP by regex → remain green.
- Confirm/add a focused assertion that `_generate_otp(4)` yields a 4-char numeric
  string.

## Out of scope

- OTP length is **not** made dynamic via app config; the app hardcodes
  `kOtpLength = 4` and the backend setting is 4. (YAGNI — the value changes ~never;
  the lockstep note above covers the mismatch window.)
- No change to OTP expiry, cooldown/resend, message template, or the verify
  algorithm.
- No new third-party package.
- Production `WASender Settings.otp_length` change is an ops step performed by
  the user/admin, not automated here.
