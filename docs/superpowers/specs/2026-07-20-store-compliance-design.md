# Design: In-app store compliance (Terms/Privacy links + Delete Account)

Date: 2026-07-20
Branch: feature/zad-mvp
Status: Approved (design)

## Problem

Google Play and the Apple App Store both gate review on compliance items the
Zad customer app is missing:

- **Privacy Policy & Terms** — the Profile tab already has "الشروط والأحكام" and
  "سياسة الخصوصية" tiles, but they open an in-app `ContentPage` that fetches
  `grocery.api.content.get_page {slug}` for slugs `terms` / `privacy-policy`.
  Those pages **do not exist** on production (`get_page` returns
  `DoesNotExistError`), so both tiles currently open an error screen. Stores
  also require a *publicly reachable* Privacy Policy URL for the listing.
- **Account deletion** — Apple Guideline 5.1.1(v) and Google Play both require
  an **in-app** path for a user to delete their account. The app has **no**
  delete-account UI and the backend has **no** endpoint.

This spec covers **Sub-project 1: in-app store compliance**. Release/deployment
setup (Android release signing, versioning, icons/splash, iOS config, and the
store-listing/data-safety checklist) is **Sub-project 2** — its own spec/plan
cycle (see Out of scope).

## Decisions (from brainstorming)

- Terms & Privacy are delivered as **external web links** (open in the browser),
  hosted as **Frappe Web Pages** on `zad.micronext.net`. URLs stored in
  `App Settings` so they are editable server-side without an app release.
- Delete Account is built **end to end** (Frappe backend + app UI).
- Delete behavior is **deactivate-and-schedule**: disable login immediately,
  anonymize personal data after a **30-day** grace period. Orders/financial
  records are retained.
- Delete confirmation is an **explicit in-dialog checkbox** (not a password or
  typed word) — reads cleanly in both Arabic and English. Identity is already
  established by the session token.

---

## Part A — Terms & Privacy as external links

### Backend (Frappe `grocery` app)

1. **Web Pages**: create two published Web Page documents with routes `terms`
   and `privacy-policy`, reachable at `https://zad.micronext.net/terms` and
   `.../privacy-policy`. Content = the real policy text (**content dependency —
   provided by the client**; created with clearly-marked placeholder text until
   then).
2. **`App Settings`** (single doctype behind `get_app_config`): add two fields,
   `terms_url` and `privacy_url` (Data/Small Text), defaulting to the two Web
   Page URLs.
3. **`grocery.api.content.get_app_config`**: include `terms_url` and
   `privacy_url` in the returned dict.

### App

- Add the **`url_launcher`** package (pubspec).
- **`AppConfig`** model (`lib/models/app_config.dart`): add `termsUrl` and
  `privacyUrl` (`String?`), parsed from `terms_url` / `privacy_url`; include
  them in `toJson` for round-trip.
- **Profile tab** (`lib/features/profile/profile_tab.dart`): the Terms and
  Privacy `_MenuTile`s change `onTap` from `_openContentPage(...)` to launching
  the corresponding `AppConfig` URL via `url_launcher`
  (`LaunchMode.externalApplication`). A tile whose URL is null/empty is
  **hidden** (never a dead link). Launch failures show a snackbar
  (`l10n.sectionErrorMessage`).
- **Retire** the now-unused in-app content path: delete
  `lib/features/profile/content_page.dart` and `ContentRepository.getPage`
  (only `ContentPage` called it). Keep `lib/core/html_text.dart` (still used for
  notification bodies) — verify no other `getPage`/`ContentPage` callers before
  deleting (grep confirms only `profile_tab.dart` today).

---

## Part B — Delete Account

### Backend (`grocery.api.auth.delete_account`)

Authenticated endpoint (`@frappe.whitelist()`), **deactivate-and-schedule**:

1. `user = _require_authenticated_user()` (rejects Guest → the existing 401
   path).
2. Set the `User` disabled (`enabled = 0`) — blocks all future login.
3. `_revoke_api_secret(user)` — the current token dies immediately, so the app
   is effectively logged out on its next call.
4. Stamp a marker: **custom field `custom_deletion_requested_on` (Date)** on
   `User`, set to `frappe.utils.today()`. (Added via a fixture/custom-field
   migration in the grocery app.)
5. Return `{"status": "scheduled", "purge_after": <today + 30 days>}`.

**Scheduled purge** — a daily job (registered in `hooks.py`
`scheduler_events["daily"]`): find Users with
`custom_deletion_requested_on <= today - 30 days` and **anonymize** personal
data — blank/placeholder the full name, phone, and email; delete the customer's
saved Addresses; keep the Customer and its linked Sales Orders/Invoices intact
(Frappe cannot hard-delete a Customer with linked docs). Idempotent (skips
already-anonymized rows).

Grace period constant: **30 days** (single named constant, easy to change).

### App

- **`AuthRepository.deleteAccount()`** (`lib/data/auth_repository.dart`): `POST
  grocery.api.auth.delete_account` (no body — the token identifies the user).
  Returns void on success; maps errors via the existing `ApiClient` exceptions.
- **Profile tab**: add a red, destructive **Delete Account** `_MenuTile`
  (`Key('profileMenuDeleteAccount')`) at the **bottom** of the authed menu
  (after Logout).
- **Confirmation** (`AlertDialog`, matching the existing `_confirmLogout` /
  support dialogs; a `StatefulBuilder` holds the checkbox state): a warning that
  the account is disabled immediately, personal data is removed after 30 days,
  orders are retained, and the action is irreversible. A **required checkbox**
  ("I understand…") gates the destructive **Delete account** button (disabled
  until checked). On confirm → `deleteAccount()`:
  - success → `context.read<SessionStore>().forceLogout()` (local clear; the
    server token is already revoked) → drop to guest + success snackbar.
  - failure → snackbar with the error message; stay put.
- **Localization** (`lib/l10n/app_en.arb` + `app_ar.arb`, regenerate): new keys
  — `deleteAccountTitle`, `deleteAccountWarning`, `deleteAccountConfirmCheckbox`,
  `deleteAccountButton`, `deleteAccountSuccess` (+ any error copy).

---

## Error / empty / loading handling

- **Terms/Privacy**: missing URL → tile hidden. `url_launcher` failure →
  snackbar; no crash.
- **Delete Account**: in-flight guard (disable the confirm button while the
  request runs); network/API error → snackbar, sheet stays open so the user can
  retry or cancel; success → forced logout so no authed screen lingers on a
  revoked token.

## Testing

**Backend (`grocery` app tests):**
- `delete_account` disables the User, revokes the api_secret, and stamps
  `custom_deletion_requested_on`.
- Guest call is rejected.
- Purge job anonymizes users past the 30-day grace and leaves fresh
  deletion-requested users untouched; idempotent on re-run.
- `get_app_config` returns `terms_url` / `privacy_url`.

**App (widget/unit tests):**
- `AppConfig.fromJson` parses `terms_url`/`privacy_url` (and round-trips).
- Profile (authed) shows Terms, Privacy, and Delete Account tiles; Terms/Privacy
  tiles hidden when the URL is empty.
- Terms/Privacy tap invokes the launcher with the config URL (inject a mockable
  launcher/`UrlLauncherPlatform` mock).
- Delete Account: confirm button disabled until the checkbox is checked;
  confirming calls `AuthRepository.deleteAccount` and triggers `forceLogout`
  (fake repo + fake secure storage; assert session drops to guest).
- `AuthRepository.deleteAccount` posts to the right method and surfaces errors.

## Dependencies / open items

- **Policy text** for the two Web Pages — client-provided; placeholder until
  then. The app + endpoints ship independently of the final copy.
- Backend custom-field migration for `custom_deletion_requested_on`.
- `url_launcher` added to pubspec (and iOS `LSApplicationQueriesSchemes` /
  Android `<queries>` if required for `https` — usually not for external
  browser launch, confirm during implementation).

## Out of scope (Sub-project 2 — separate cycle)

- Android **release signing** (currently signs with debug keys — a `TODO` in
  `android/app/build.gradle.kts`) + versioning/build numbers.
- App icon / splash finalization.
- iOS release config (bundle id, Info.plist privacy usage strings) — **note:**
  building/archiving an IPA needs macOS/Xcode; not possible on this Linux host.
- Store-listing assets, screenshots, and Google Play **Data safety** / Apple
  **App Privacy** questionnaires (these must declare the account-deletion path
  built here).
- The actual legal content of the policies.
