# Modern Popup Design System — Design

**Date:** 2026-07-23
**Status:** Approved (design), pending spec review
**Repo:** `zad` (Flutter app)

## Problem

Every popup in the app — confirmation dialogs, bottom sheets, and snackbars —
is a raw Material primitive with default styling. `AlertDialog`/`SimpleDialog`
and `SnackBar` ignore the app's design tokens (`ZadColors`, `ZadRadii`,
`ZadSpacing`), so they look generic and inconsistent with the branded home,
checkout, and auth surfaces. Destructive actions (Clear basket, Delete address,
Delete account, Logout) render as plain `TextButton`s identical to Cancel, so
nothing signals danger. The same confirm-dialog boilerplate is copy-pasted
across five call sites. There is no `dialogTheme`/`snackBarTheme` in
`zadTheme()`, and no written standard for which popup to use when.

The user wants: (1) all popups modernized to an elegant, on-brand look;
(2) a design bug/issue audit; (3) documented **System Design standards and
roles** applied across the app.

## Decisions (from brainstorming)

- **Scope:** all three popup surfaces — confirmation dialogs, bottom sheets,
  and snackbars/toasts.
- **Dialog direction:** **icon-led with action hierarchy** — a circular tinted
  icon badge, bold centered title, muted centered body, a full-width filled
  primary action (**red when destructive**), and a text secondary. 28px radius,
  soft shadow, scale+fade entrance.
- **Delivery:** **shared components built on the design tokens**, migrate all
  call sites, **plus** `dialogTheme`/`snackBarTheme` as a safety net for
  anything not migrated.
- **Deliverables also include** a written design-system standards doc and a
  design bug-audit report (issues fixed in the same pass).

## Design tokens (additions)

`lib/core/theme.dart` — `ZadColors`:
- `danger` = `Color(0xFFB3261E)` (reuse `errorText`) — destructive action fill.
- `success` = `Color(0xFF2E7D32)`, `info` = `Color(0xFF1565C0)`,
  `warning` = `Color(0xFFB26A00)` — snackbar variants (icon + accent).
- `scrim` = `Colors.black.withValues(alpha: 0.45)` — dialog/sheet barrier.

`lib/core/constants.dart`:
- `ZadRadii.dialog = 28`.
- New `abstract final class ZadElevation { static const dialog = 24.0; static const sheet = 16.0; static const snack = 6.0; }`
  (used as shadow blur, not Material elevation).
- New `abstract final class ZadDurations { static const popupIn = Duration(milliseconds: 220); static const snack = Duration(seconds: 3); }`
  and `ZadCurves { static const popupIn = Curves.easeOutCubic; }`.

All new tokens are additive; nothing existing changes value.

## Component APIs (`lib/core/widgets/`)

Core widgets must not import from `lib/features/**` (layering rule — see
Standards). The dialog builds its own action buttons from tokens so it can take
a destructive color; it does **not** depend on the auth `ZadPrimaryButton`.

### `zad_dialog.dart`

```dart
/// The icon-led dialog scaffold: [icon] badge → [title] → [message]/[content]
/// → primary action (filled, [destructive] ⇒ danger red) → optional secondary
/// (text). 28px radius, ZadColors.white surface, soft shadow, scale+fade in.
class ZadDialog extends StatelessWidget { /* internal, used by the helpers */ }

/// Confirm/cancel dialog. Resolves true on confirm, false on cancel/dismiss.
Future<bool> showZadConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  IconData? icon,
  bool destructive = false,
});
// Barrier dismissal is enabled only when NOT destructive: a destructive
// confirm forces an explicit Cancel/confirm choice; a non-destructive one
// treats a barrier tap as cancel (resolves false).

/// Lower-level dialog for custom body/actions (lists, checkboxes, option rows).
/// [contentBuilder] renders below the title; [actions] are the button column.
Future<T?> showZadDialog<T>(
  BuildContext context, {
  IconData? icon,
  String? title,
  required WidgetBuilder contentBuilder,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
});
```

- Entrance: `showGeneralDialog` with a `ScaleTransition`(0.96→1.0)+`FadeTransition`
  over `ZadDurations.popupIn`/`ZadCurves.popupIn`; barrier `ZadColors.scrim`.
- Primary button: full-width, height 52, radius `ZadRadii.button`, fill
  `destructive ? ZadColors.danger : ZadColors.primary`, white text.
- Secondary: centered `TextButton`, `ZadColors.muted` label.
- Icon badge: 56px circle, fill = action color at 12% alpha, icon in action
  color.
- Title centered `w700`/18, message centered 14 `ZadColors.ink`/muted mix.
- RTL-safe (no hardcoded left/right; uses logical padding).

### `zad_bottom_sheet.dart`

```dart
/// Branded modal sheet: 4px grabber handle, ZadRadii.sheet top corners,
/// ZadColors.white surface, safe-area + keyboard-inset aware padding, optional
/// [title] header row. isScrollControlled so tall/form sheets size correctly.
Future<T?> showZadSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = true,
});
```

### `zad_snack.dart`

```dart
enum ZadSnackVariant { success, error, info, warning }

/// Floating, rounded (ZadRadii.button), leading-icon snackbar coloured by
/// [variant]. Uses ScaffoldMessenger.of(context) (caller guards mounted).
/// Clears any in-flight snackbar first so they don't stack.
void showZadSnack(
  BuildContext context,
  String message, {
  ZadSnackVariant variant = ZadSnackVariant.info,
});
```

- `SnackBarBehavior.floating`, margin insets so it clears bottom bars/CTAs,
  leading icon per variant (check-circle / error / info / warning), left accent
  stripe or tinted background in the variant colour, `ZadColors.ink` text.

## Theme defaults (safety net)

In `zadTheme()` add:
- `dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius:
  BorderRadius.circular(ZadRadii.dialog)), backgroundColor: ZadColors.white,
  ...)`.
- `snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(
  ZadRadii.button)), ...)`.

So any popup not yet migrated (or added later) is still on-brand.

## Migration map (every current call site)

**Confirmation dialogs → `showZadConfirm` (destructive where noted):**
- `basket_page.dart` — clear basket **(destructive, 🗑)**.
- `address_list_page.dart` — delete address **(destructive, 🗑)**.
- `profile_tab.dart` — logout **(destructive)**; delete account **(destructive,
  keeps the checkbox gate → `showZadDialog` with a `StatefulBuilder` content)**.
- `checkout_page.dart` — outside-coverage info (non-destructive, primary =
  "Manage Addresses"); out-of-stock (custom item list → `showZadDialog`).

**Custom-content dialogs → `showZadDialog`:**
- `profile_tab.dart` — support (phone + copy), language picker (replaces the
  inconsistent `SimpleDialog` with option rows).
- `checkout_page.dart` — out-of-stock list.

**Bottom sheets → `showZadSheet`:**
- `login_required_sheet.dart`, `add_address_nudge_sheet.dart`,
  `home/widgets/sort_sheet.dart`, and the `home_page.dart` sheet.

**Snackbars → `showZadSnack`:**
- `user_error.dart` `showErrorSnackBar` routes through `showZadSnack(...,
  variant: error)` — this upgrades every error site at once.
- Success/info sites (address saved, password changed, copied, added-to-basket,
  cart sync, delete-account success, etc.) pick the matching variant.

## Design bug / issue audit (confirm + fix in this pass)

1. **Destructive actions look like Cancel** — no colour/weight distinction on
   Clear/Delete/Logout. → red filled primary via `destructive: true`.
2. **Popups ignore brand tokens** — default Material radius/colour/elevation. →
   shared components + theme defaults.
3. **Error snackbars look like normal info** — no colour/icon. → error variant.
4. **Language picker uses `SimpleDialog`** — inconsistent with the rest. →
   `showZadDialog` option rows.
5. **Duplicated confirm boilerplate ×5** — → one `showZadConfirm`.
6. **Snackbars may be occluded** by the checkout CTA bar / bottom nav. →
   floating with margin that clears them.
7. **Sheets lack a grabber handle** and use ad-hoc radius/padding. → unified in
   `showZadSheet`.
8. **RTL** — verify every migrated popup mirrors correctly in Arabic
   (logical padding, no `Left/Right` literals).
Each item is verified against the running app (light + Arabic) before closing.

## Standards & roles doc (`docs/design-system/README.md`)

- **Tokens** — colour (incl. semantic), radii, spacing, elevation, motion,
  typography — the single source; no raw hex/`Colors.*`/magic numbers in
  feature code.
- **When to use which popup** — dialog = blocking decision/confirmation;
  bottom sheet = choice or short form; snackbar = transient, non-blocking
  feedback (never for errors that must block).
- **Action hierarchy** — exactly one primary per popup; destructive = red
  filled; cancel/dismiss = text; primary sits last (bottom) in the column.
- **Accessibility** — tap targets ≥48px; `Semantics`/tooltip labels on icon
  buttons; text contrast ≥ 4.5:1; `barrierDismissible` reserved for
  non-destructive dialogs.
- **RTL & localization** — all copy via `AppLocalizations`; logical
  (`start`/`end`) insets only; verified in `ar`.
- **Motion** — popups use `ZadDurations`/`ZadCurves`; no bespoke durations.
- **Layering** — `lib/core/widgets` may not import `lib/features/**`; app-wide
  primitives live in core. (Notes `ZadPrimaryButton` as a candidate to
  relocate from `features/auth/widgets` to `core/widgets` later — out of scope
  here, flagged not moved.)
- **Consistency rule** — no raw `AlertDialog`/`SimpleDialog`/`showModalBottomSheet`
  /`SnackBar` in feature code; use the Zad helpers.

## Testing

- **Widget tests per component** (`test/core/widgets/`):
  - `showZadConfirm` resolves true on primary tap, false on secondary; a
    non-destructive one also resolves false on barrier tap, a destructive one
    is not barrier-dismissible; `destructive` renders the danger-coloured
    primary; icon badge shown when given.
  - `showZadDialog` renders custom content + actions; returns the action's
    value; the delete-account checkbox gates its primary.
  - `showZadSheet` shows the grabber + title; returns the builder's result;
    dismisses on drag/barrier.
  - `showZadSnack` shows the message with the variant icon; error variant
    distinct from info; only one snackbar at a time.
- **Migrated call-site tests** keep passing with updated finders (e.g. tests
  that tapped `TextButton`/looked for dialog text now target the Zad helpers'
  buttons/keys). Add stable `Key`s (`zadDialogPrimary`, `zadDialogSecondary`,
  `zadSnack`) for robust finds.
- **Full suite green** and `flutter analyze` clean. Manual pass in the running
  app, English + Arabic, for each surface.

## Rollout (phased — nothing lands half-migrated)

1. Tokens + theme defaults.
2. `zad_dialog.dart` (+ tests) and migrate the dialog call sites.
3. `zad_bottom_sheet.dart` (+ tests) and migrate the sheets.
4. `zad_snack.dart` (+ tests); route `showErrorSnackBar` through it; migrate
   the snackbar sites.
5. `docs/design-system/README.md` standards doc + the audit report.
6. Full-suite verification (analyze + tests + manual light/Arabic pass).

## Out of scope

- Dark mode (app is light-only today; standards doc notes it as future work).
- Relocating `ZadPrimaryButton` into `core/widgets` (flagged, not done).
- Redesigning non-popup surfaces (pages, cards, nav) beyond token consistency.
- A CI lint that forbids raw Material popups (documented as a rule; automation
  is future work).
