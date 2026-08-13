# Design System Standards

This document establishes the rules and practices for building on-brand popups and dialog surfaces in the Zad app.

## Design Tokens

All visual properties — colors, radii, elevation, timing, spacing — must use shared design tokens from `lib/core/theme.dart` and `lib/core/constants.dart`. **Never use raw hex literals, `Colors.*` constants, or magic numbers in feature code.** Tokens are the single source of truth for the app's visual language.

### Colors (`ZadColors`)

- **`primary`** — `Color(0xFF5AC268)` — primary actions and filled surfaces.
- **`danger`** — `Color(0xFFB3261E)` — destructive-action fill (Clear, Delete, Logout).
- **`success`** — `Color(0xFF2E7D32)` — success-variant snackbars and icons.
- **`info`** — `Color(0xFF1565C0)` — info-variant snackbars and icons (default).
- **`warning`** — `Color(0xFFB26A00)` — warning-variant snackbars and icons.
- **`scrim`** — `Colors.black.withValues(alpha: 0.45)` — dialog and sheet barrier overlay.
- **`ink`** — `Color(0xFF101811)` — primary text.
- **`muted`** — `Color(0xFFA9AFAA)` — secondary/tertiary text and icon tints.
- **`white`** — `Color(0xFFFFFFFF)` — text/icons on primary fills; dialog/sheet backgrounds.

### Radii (`ZadRadii`)

- **`dialog`** — `28` — dialog and icon badges.
- **`sheet`** — `30` — bottom sheet top corners.
- **`banner`** — `16` — inline error banners.
- **`tile`** — `14` — card and tile corners.
- **`button`** — `12` — action buttons and snackbars.

### Elevation (`ZadElevation`)

Shadow blur radii for popup surfaces (not Material elevation):

- **`dialog`** — `24` — confirmation and custom dialogs.
- **`sheet`** — `16` — bottom sheets.
- **`snack`** — `6` — snackbars and floating feedback.

### Motion (`ZadDurations` & `ZadCurves`)

- **`ZadDurations.popupIn`** — `Duration(milliseconds: 220)` — dialog/sheet entrance.
- **`ZadDurations.snack`** — `Duration(seconds: 3)` — snackbar display time.
- **`ZadCurves.popupIn`** — `Curves.easeOutCubic` — dialog/sheet scale+fade curve.

Always use these constants; never hardcode durations in feature code.

### Spacing (`ZadSpacing`)

- **`screenPadding`** — `20` — standard horizontal/bottom inset for dialogs, sheets, and snackbars.
- **`sectionGap`** — `24` — vertical spacing between content sections.

---

## Popup Components

The Zad design system provides three branded popup surfaces, all in `lib/core/widgets/`. Use these instead of raw Material primitives.

| Component | File | Usage | Purpose |
|-----------|------|-------|---------|
| `showZadConfirm()` | `zad_dialog.dart` | `showZadConfirm(context, title: "...", message: "...", confirmLabel: "...", cancelLabel: "...", destructive: true)` | Confirmation dialog; resolves true/false. Primary is red when `destructive: true`. Barrier is not dismissible when destructive. |
| `showZadDialog()` | `zad_dialog.dart` | `showZadDialog(context, contentBuilder: (_) => ..., actions: [...], barrierDismissible: true)` | Custom-content dialog for lists, checkboxes, option rows. Caller pops with result value. |
| `zadDialogPrimaryAction()` | `zad_dialog.dart` | `zadDialogPrimaryAction(label: "...", onPressed: () {...}, destructive: true)` | Full-width filled primary action for use in `showZadDialog.actions`. |
| `showZadSheet()` | `zad_bottom_sheet.dart` | `showZadSheet(context, builder: (_) => ..., title: "...")` | Branded bottom sheet with grabber handle, title header, keyboard-safe padding. |
| `showZadSnack()` | `zad_snack.dart` | `showZadSnack(context, "Message", variant: ZadSnackVariant.success)` | Floating, non-blocking feedback. Never stacks; replaces prior. Variants: `success`, `error`, `info`, `warning`. |

---

## When to Use Which Popup

- **Dialog (`showZadConfirm` / `showZadDialog`)** — Use for blocking, user-initiated decisions: "Are you sure you want to delete?", "Choose your language", "Confirm your address". The user must dismiss the dialog to continue the flow.
- **Bottom Sheet (`showZadSheet`)** — Use when presenting a choice or a short form that needs space: "Which address to ship to?", "Add a new address", "Sort by...". Feels less intrusive than a dialog; may be taller or offer scrolling.
- **Snackbar (`showZadSnack`)** — Use for transient, non-blocking feedback: "Item added to basket", "Address saved", "Error: connection failed". Never block the user; always offer a way to dismiss or retry elsewhere.

**Critical rule:** Never use a snackbar for errors that must block. Use a dialog for destructive or high-stakes errors; snackbars are for information, not enforcement.

---

## Action Hierarchy

Every popup follows the same button layout:

1. **Exactly one primary action per popup** — full-width, filled color, 52px tall, `ZadRadii.button` corners.
2. **Primary is red when destructive** — use `destructive: true` in `showZadConfirm()` or `destructive: true` in `zadDialogPrimaryAction()`. Destructive = destructive color only; the button itself is filled.
3. **Secondary action is optional** — centered, text only (no fill), `ZadColors.muted` label color.
4. **Primary sits last** (bottom of the column) — in the natural reading order after secondary.
5. **A disabled primary greys out** — pass `onPressed: null` to `zadDialogPrimaryAction()` or the confirm builder; the button disables automatically.

Destructive dialogs set `barrierDismissible: false` — the user must choose an action explicitly; tapping outside does not dismiss.

---

## Accessibility

- **Tap targets ≥ 48 pixels** — all buttons meet the 48×48 minimum. Primary buttons are 52px tall; secondary text buttons use default Material tap target padding.
- **Semantics and labels** — icon buttons in popups include `Tooltip` or `Semantics` labels for screen readers.
- **Text contrast ≥ 4.5:1** — all text passes WCAG AA contrast checks. Verify in `ZadColors` and ensure custom content also meets the standard.
- **`barrierDismissible` discipline** — use `barrierDismissible: true` (default) only for non-destructive dialogs. Destructive or high-stakes operations disable barrier dismissal via `showZadConfirm(destructive: true)` (auto-set) or `showZadDialog(barrierDismissible: false)`.

---

## RTL & Localization

- **All copy via `AppLocalizations`** — no hardcoded English strings. Use `AppLocalizations.of(context)!` for all dialog/sheet/snackbar text.
- **Logical insets only** — use `start`/`end` instead of `left`/`right` in custom content. The popup scaffolds use `EdgeInsets.fromLTRB()` and `symmetric()` to preserve RTL flipping at the framework level.
- **Verify in Arabic** — test every migrated popup in `ar` locale on a real device or emulator. The grabber handle, icon badge, text, and button layout must mirror correctly.

---

## Motion

- **Use `ZadDurations` and `ZadCurves`** — all popups entrance via `ZadDurations.popupIn` (220ms) and `ZadCurves.popupIn` (easeOutCubic).
- **No bespoke durations** — if a different timing feels necessary, refactor the design, not the code. Consistent motion is part of the brand.

---

## Layering

**`lib/core/widgets/` must never import `lib/features/**`.** The core widgets layer provides app-wide primitives that features use; features should never dictate core design. This enforces a clean dependency hierarchy:

```
features/* → core/widgets/*, core/theme, core/constants
core/widgets/* → only core/ (theme, constants) and Flutter
```

**Note:** `ZadPrimaryButton` currently lives in `features/auth/widgets/` and would ideally relocate to `core/widgets/` for consistency, but this is deferred — flagged for future work and not moved in this pass.

---

## Consistency Rule

**Do not use raw Material popups in feature code.** The following are forbidden in `lib/features/**`:

- `AlertDialog(...)` — use `showZadConfirm()` or `showZadDialog()`.
- `SimpleDialog(...)` — use `showZadDialog()` with option rows.
- `showModalBottomSheet(...)` — use `showZadSheet()`.
- `SnackBar(...)` directly — use `showZadSnack()` (or route through it, e.g., `showErrorSnackBar`).

The theme's `dialogTheme` and `snackBarTheme` provide a safety net for anything not yet migrated, but the intent is for all popups to use the Zad helpers.

---

## Future Work

The following are documented as future enhancements and out of scope for this release:

1. **Dark mode** — the app is light-only today. Tokens are designed to extend to a dark palette; implementation is pending.
2. **`ZadPrimaryButton` relocation** — move from `features/auth/widgets/` to `core/widgets/` so all primary actions come from one place. Currently deferred.
3. **CI lint enforcement** — a static analysis rule that forbids raw `AlertDialog`/`SimpleDialog`/`showModalBottomSheet`/`SnackBar` in feature code. The consistency rule is documented; automation is future work.
4. **Deferred sheets** — two bottom sheets (add-address nudge + sort sheet) remain to be migrated once their home_page/sort_sheet WIP branches are committed. The `showZadSheet` helper is ready; the call sites will follow.

---

## Resources

- **Theme tokens:** `lib/core/theme.dart` (`ZadColors`, `zadTheme()`)
- **Layout & motion tokens:** `lib/core/constants.dart` (`ZadRadii`, `ZadElevation`, `ZadDurations`, `ZadCurves`, `ZadSpacing`)
- **Popup components:** `lib/core/widgets/` (`zad_dialog.dart`, `zad_bottom_sheet.dart`, `zad_snack.dart`)
- **Test suite:** `test/core/widgets/` (component tests with key finders: `zadDialogPrimary`, `zadDialogSecondary`, `zadSheetHandle`, `zadSnack`)
