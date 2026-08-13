# Store Compliance (Terms/Privacy links + Delete Account) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Zad customer app pass Google Play / App Store review by delivering Terms & Privacy as external web links (server-configurable) and adding in-app Delete Account (deactivate-now, anonymize-after-grace), backend + app.

**Architecture:** Backend (Frappe `grocery` app) exposes `terms_url`/`privacy_url` from `App Settings` via `get_app_config`, serves two public Web Pages, and adds an authenticated `delete_account` endpoint that disables the User + revokes the token + stamps a deletion marker, plus a daily job that anonymizes marked users after 30 days. The app reads the two URLs into `AppConfig`, opens them via a thin injectable `UrlOpener` (url_launcher), retires the now-dead in-app `ContentPage`, and adds a red Delete Account tile whose checkbox-gated confirm dialog calls the endpoint then force-logs-out.

**Tech Stack:** Flutter, Provider, Dio, `url_launcher`, `flutter_test`; Frappe v16 (Python), `IntegrationTestCase`.

## Global Constraints

- Flutter SDK is off-PATH: run `~/.flutter-sdk/bin/flutter ...` / `~/.flutter-sdk/bin/dart ...`. Keep `~/.flutter-sdk/bin/flutter test` green after every task; regenerate l10n with `~/.flutter-sdk/bin/flutter gen-l10n` after editing any `.arb`.
- Backend lives at `~/Frappe/grocery-bench/apps/grocery`; run backend tests with `cd ~/Frappe/grocery-bench && bench --site <dev-site> run-tests --module grocery.tests.<module>` (tests write to the dev site — expected). Apply schema/patch changes with `bench --site <dev-site> migrate`.
- Grace period before personal-data purge = **30 days** (single constant `DELETION_GRACE_DAYS = 30`).
- App themed values come from `ZadColors` (`lib/core/theme.dart`) / `ZadSpacing`/`ZadRadii` (`lib/core/constants.dart`) — no raw literals for themed values. Destructive UI uses `Colors.redAccent` (matches existing logout tile).
- Localized copy only via `AppLocalizations.of(context)`; add every new string to BOTH `lib/l10n/app_en.arb` and `lib/l10n/app_ar.arb`.
- Delete confirmation is a checkbox in an `AlertDialog` (no password/OTP). Deletion is deactivate-and-schedule; orders/financial records are retained.

---

### Task 1: Backend — `terms_url`/`privacy_url` config + Web Pages

Expose two server-editable policy URLs and serve the pages they point to.

**Files:**
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/grocery/doctype/app_settings/app_settings.json`
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/api/content.py:27-49` (`get_app_config`)
- Create: `~/Frappe/grocery-bench/apps/grocery/grocery/patches/v1_0/create_policy_web_pages.py`
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/patches.txt`
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_content.py`

**Interfaces:**
- Produces: `get_app_config()` return dict gains string keys `"terms_url"`, `"privacy_url"` (may be empty string / None when unset).

- [ ] **Step 1: Add the failing backend test**

Append to `grocery/tests/test_content.py` (inside the existing test class; follow the file's existing import of `from grocery.api import content`):

```python
	def test_get_app_config_exposes_policy_urls(self):
		settings = frappe.get_single("App Settings")
		settings.terms_url = "https://zad.micronext.net/terms"
		settings.privacy_url = "https://zad.micronext.net/privacy-policy"
		settings.save(ignore_permissions=True)

		config = content.get_app_config()

		self.assertEqual(config["terms_url"], "https://zad.micronext.net/terms")
		self.assertEqual(config["privacy_url"], "https://zad.micronext.net/privacy-policy")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ~/Frappe/grocery-bench && bench --site <dev-site> run-tests --module grocery.tests.test_content`
Expected: FAIL — `AttributeError: 'App Settings' object has no attribute 'terms_url'` (field not defined) and/or `KeyError: 'terms_url'`.

- [ ] **Step 3: Add the two fields to the `App Settings` doctype**

In `app_settings.json`: add `"terms_url"` and `"privacy_url"` to the `"field_order"` array immediately after `"support_phone"`, and add these two objects to the `"fields"` array (after the `support_phone` field object):

```json
  {
   "fieldname": "terms_url",
   "fieldtype": "Small Text",
   "label": "Terms & Conditions URL"
  },
  {
   "fieldname": "privacy_url",
   "fieldtype": "Small Text",
   "label": "Privacy Policy URL"
  }
```

Apply: `cd ~/Frappe/grocery-bench && bench --site <dev-site> migrate`.

- [ ] **Step 4: Return them from `get_app_config`**

In `grocery/api/content.py`, inside the `get_app_config` return dict (after `"support_phone": settings.support_phone,`) add:

```python
		"terms_url": settings.terms_url or "",
		"privacy_url": settings.privacy_url or "",
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd ~/Frappe/grocery-bench && bench --site <dev-site> run-tests --module grocery.tests.test_content`
Expected: PASS.

- [ ] **Step 6: Add the Web Pages + default-URL patch**

Create `grocery/patches/v1_0/create_policy_web_pages.py`:

```python
import frappe
from frappe.utils import get_url

PAGES = [
	("terms", "Terms & Conditions"),
	("privacy-policy", "Privacy Policy"),
]


def execute():
	"""Ensure the two policy Web Pages exist (placeholder content — the real
	legal text is authored later) and default App Settings' policy URLs to them."""
	for route, title in PAGES:
		if not frappe.db.exists("Web Page", {"route": route}):
			frappe.get_doc({
				"doctype": "Web Page",
				"title": title,
				"route": route,
				"published": 1,
				"content_type": "Rich Text",
				"main_section": f"<p>{title} — placeholder. Replace with the final policy text.</p>",
			}).insert(ignore_permissions=True)

	settings = frappe.get_single("App Settings")
	changed = False
	if not settings.terms_url:
		settings.terms_url = get_url("/terms")
		changed = True
	if not settings.privacy_url:
		settings.privacy_url = get_url("/privacy-policy")
		changed = True
	if changed:
		settings.save(ignore_permissions=True)
```

Add this line to the end of `grocery/patches.txt`:

```
grocery.patches.v1_0.create_policy_web_pages
```

Run: `cd ~/Frappe/grocery-bench && bench --site <dev-site> migrate`, then verify:
`curl -sS -X POST -H "Content-Type: application/json" -d '{}' https://zad.micronext.net/api/method/grocery.api.content.get_app_config` (after deploy) or the dev equivalent returns non-empty `terms_url`/`privacy_url`, and `https://<site>/terms` renders.

- [ ] **Step 7: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/grocery/doctype/app_settings/app_settings.json grocery/api/content.py grocery/patches/v1_0/create_policy_web_pages.py grocery/patches.txt grocery/tests/test_content.py
git commit -m "feat(content): expose terms_url/privacy_url + serve policy web pages"
```

---

### Task 2: App — `AppConfig.termsUrl` / `privacyUrl`

Parse the two new config fields so the app can reach them.

**Files:**
- Modify: `lib/models/app_config.dart`
- Test: `test/models/app_config_test.dart` (create if absent; otherwise append)

**Interfaces:**
- Produces: `AppConfig.termsUrl` (`String?`), `AppConfig.privacyUrl` (`String?`), parsed from `terms_url`/`privacy_url` and round-tripped in `toJson`.

- [ ] **Step 1: Write the failing test**

Create/append `test/models/app_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/models/app_config.dart';

void main() {
  test('parses and round-trips terms/privacy URLs', () {
    final config = AppConfig.fromJson(const {
      'terms_url': 'https://zad.micronext.net/terms',
      'privacy_url': 'https://zad.micronext.net/privacy-policy',
    });
    expect(config.termsUrl, 'https://zad.micronext.net/terms');
    expect(config.privacyUrl, 'https://zad.micronext.net/privacy-policy');

    final round = AppConfig.fromJson(config.toJson());
    expect(round.termsUrl, 'https://zad.micronext.net/terms');
    expect(round.privacyUrl, 'https://zad.micronext.net/privacy-policy');
  });

  test('missing URLs are null', () {
    final config = AppConfig.fromJson(const {});
    expect(config.termsUrl, isNull);
    expect(config.privacyUrl, isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/models/app_config_test.dart`
Expected: FAIL — `termsUrl`/`privacyUrl` are not defined on `AppConfig`.

- [ ] **Step 3: Add the fields**

In `lib/models/app_config.dart`: add constructor params `this.termsUrl,` and `this.privacyUrl,`; add fields `final String? termsUrl;` and `final String? privacyUrl;` (after `supportPhone`); in `fromJson` add `termsUrl: json['terms_url'] as String?,` and `privacyUrl: json['privacy_url'] as String?,`; in `toJson` add `'terms_url': termsUrl,` and `'privacy_url': privacyUrl,`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/models/app_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/app_config.dart test/models/app_config_test.dart
git commit -m "feat(config): parse terms_url/privacy_url into AppConfig"
```

---

### Task 3: App — injectable `UrlOpener` (url_launcher)

A thin seam over `url_launcher` so external-link opening is testable without the platform channel.

**Files:**
- Modify: `pubspec.yaml` (add `url_launcher`)
- Create: `lib/core/services/url_opener.dart`
- Modify: `lib/app.dart` (provide `UrlOpener`)
- Modify: `test/helpers.dart` (`homeTestProviders` gains a `urlOpener` param + a fake)
- Test: `test/core/services/url_opener_test.dart` (create)

**Interfaces:**
- Produces: `abstract class UrlOpener { Future<bool> open(String url); }` and `class DefaultUrlOpener implements UrlOpener`. A `FakeUrlOpener` in `test/helpers.dart` records `opened` URLs and returns a settable `result`.

- [ ] **Step 1: Add the dependency**

Run: `cd /home/frappe/Flutter/zad && ~/.flutter-sdk/bin/flutter pub add url_launcher`
Expected: `pubspec.yaml` gains `url_launcher:` under dependencies; `pub get` succeeds.

- [ ] **Step 2: Write the failing test (the seam contract)**

Create `test/core/services/url_opener.dart` consumer test `test/core/services/url_opener_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/services/url_opener.dart';

void main() {
  test('DefaultUrlOpener returns false for an unparseable url', () async {
    // A malformed URL must not throw — the caller shows a snackbar on false.
    const opener = DefaultUrlOpener();
    expect(await opener.open('::::not a url::::'), isFalse);
  });
}
```

- [ ] **Step 3: Run it to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/core/services/url_opener_test.dart`
Expected: FAIL — `url_opener.dart` does not exist (compile error).

- [ ] **Step 4: Implement the seam**

Create `lib/core/services/url_opener.dart`:

```dart
import 'package:url_launcher/url_launcher.dart';

/// A thin, injectable seam over `url_launcher`, so opening external links is
/// testable without the platform channel. [open] returns whether the URL was
/// handed off to the OS; callers show an error affordance on false.
abstract class UrlOpener {
  Future<bool> open(String url);
}

class DefaultUrlOpener implements UrlOpener {
  const DefaultUrlOpener();

  @override
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/core/services/url_opener_test.dart`
Expected: PASS.

- [ ] **Step 6: Provide it app-wide + add the test fake**

In `lib/app.dart`, add to the `MultiProvider` `providers` list (near the other `Provider<...>` service entries):

```dart
        Provider<UrlOpener>(create: (_) => const DefaultUrlOpener()),
```

(add `import 'core/services/url_opener.dart';` at the top, matching the file's relative-import style.)

In `test/helpers.dart`, add a fake and wire it into `homeTestProviders`:

```dart
class FakeUrlOpener implements UrlOpener {
  final List<String> opened = [];
  bool result = true;

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return result;
  }
}
```

Add `import 'package:zad/core/services/url_opener.dart';` to `test/helpers.dart`; add a `UrlOpener? urlOpener,` parameter to `homeTestProviders(...)`; and add to its returned providers list:

```dart
    Provider<UrlOpener>.value(value: urlOpener ?? FakeUrlOpener()),
```

- [ ] **Step 7: Run the full suite (nothing else should break)**

Run: `~/.flutter-sdk/bin/flutter test`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/services/url_opener.dart lib/app.dart test/helpers.dart test/core/services/url_opener_test.dart
git commit -m "feat(core): add injectable UrlOpener over url_launcher"
```

---

### Task 4: App — Terms/Privacy tiles open external links; retire in-app ContentPage

Repoint the two profile tiles at the config URLs and remove the now-dead in-app content page.

**Files:**
- Modify: `lib/features/profile/profile_tab.dart`
- Delete: `lib/features/profile/content_page.dart`
- Modify: `lib/data/content_repository.dart` (remove `getPage`)
- Delete: `test/features/profile/content_page_test.dart`
- Modify: `test/data/content_repository_test.dart` (drop the `getPage` tests)
- Modify: `test/features/profile_tab_test.dart` (terms/privacy now launch a URL)

**Interfaces:**
- Consumes: `AppConfig.termsUrl`/`privacyUrl` (Task 2), `UrlOpener` (Task 3), `AppConfigStore` (existing).

- [ ] **Step 1: Rewrite the profile terms/privacy test to assert URL launch**

In `test/features/profile_tab_test.dart`: replace the test `'terms and privacy open ContentPage with the right slug content'` (around line 101) with the version below, and remove the now-unused `ContentPage` import. Seed the two URLs through the **existing** `homeTestProviders` `appConfig` **Map** param (it feeds the fake `content.get_app_config`, which `AppConfigStore` loads), and inject a `FakeUrlOpener`. `AppConfigStore` populates its `config` from that fake on load — `pumpAndSettle` after mount lets the fetch complete before the tap (mirror how the existing support-phone test seeds `support_phone`; if that test triggers a config refresh, do the same here). Assert the launcher receives the terms URL:

```dart
  testWidgets('terms tile opens the configured terms URL', (tester) async {
    final store = _authedSession();
    final opener = FakeUrlOpener();
    await tester.pumpWidget(
      wrapPage(
        const ProfileTab(),
        providers: homeTestProviders(
          sessionStore: store,
          urlOpener: opener,
          appConfig: const {
            'terms_url': 'https://zad.micronext.net/terms',
            'privacy_url': 'https://zad.micronext.net/privacy-policy',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileMenuTerms')));
    await tester.pumpAndSettle();
    expect(opener.opened, contains('https://zad.micronext.net/terms'));
  });
```

Keep the existing "terms and privacy tiles are present" test (keys `profileMenuTerms`/`profileMenuPrivacy`) — but note those tiles are now URL-gated, so that test must also pass a non-empty `appConfig` with both URLs (else the tiles are hidden).

- [ ] **Step 2: Confirm `AppConfigStore` config reaches `ProfileTab` in tests**

`homeTestProviders` already builds `AppConfigStore(repository: buildFakeContentRepository())` from the `appConfig` Map and provides it. Verify `ProfileTab` reads `context.watch<AppConfigStore>().config` and that the store has loaded the config by the time the tiles build (the store loads on construction/first use; `pumpAndSettle` covers it — the existing support-phone dialog test already depends on this same path). No new `homeTestProviders` param is needed beyond `urlOpener` (Task 3) since `appConfig` already exists.

- [ ] **Step 3: Run the profile test to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/features/profile_tab_test.dart`
Expected: FAIL — the tiles still push `ContentPage`; `opener.opened` is empty.

- [ ] **Step 4: Repoint the tiles + add the launch helper**

In `lib/features/profile/profile_tab.dart`:
- Add imports: `import '../../core/services/url_opener.dart';` and `import '../../core/stores/app_config_store.dart';` (the latter is already imported).
- Remove `import 'content_page.dart';` and the `_openContentPage` method.
- Add a launch helper on `_AuthedProfile`:

```dart
  Future<void> _openUrl(BuildContext context, String? url) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (url == null || url.isEmpty) return;
    final ok = await context.read<UrlOpener>().open(url);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.sectionErrorMessage)));
    }
  }
```

- In `build`, read the config once: `final config = context.watch<AppConfigStore>().config;`. Replace the Terms tile `onTap` with `onTap: () => _openUrl(context, config.termsUrl)` and the Privacy tile `onTap` with `onTap: () => _openUrl(context, config.privacyUrl)`. Wrap each tile so it is only shown when its URL is non-empty:

```dart
        if ((config.termsUrl ?? '').isNotEmpty)
          _MenuTile(
            key: const Key('profileMenuTerms'),
            icon: Iconsax.document_text,
            label: l10n.profileTermsTitle,
            onTap: () => _openUrl(context, config.termsUrl),
          ),
        if ((config.privacyUrl ?? '').isNotEmpty)
          _MenuTile(
            key: const Key('profileMenuPrivacy'),
            icon: Iconsax.shield_tick,
            label: l10n.profilePrivacyTitle,
            onTap: () => _openUrl(context, config.privacyUrl),
          ),
```

- [ ] **Step 5: Retire the dead content page + repository method**

- Delete `lib/features/profile/content_page.dart` and `test/features/profile/content_page_test.dart`.
- In `lib/data/content_repository.dart`, remove the `getPage(...)` method (Task-4 grep confirmed only `ContentPage` used it).
- In `test/data/content_repository_test.dart`, delete the tests that exercise `getPage`.
- In `test/helpers.dart`, the fake dio's `content.get_page` branch and the `pages`/slug plumbing become dead — leave the branch returning a 404 (it is harmless) OR remove it; do NOT remove `htmlToBlocks`/`html_text.dart` (still used by notifications).

- [ ] **Step 6: Run the affected tests, then the full suite**

Run: `~/.flutter-sdk/bin/flutter test test/features/profile_tab_test.dart test/data/content_repository_test.dart && ~/.flutter-sdk/bin/flutter analyze`
Expected: PASS + analyze clean (no dangling `ContentPage`/`getPage` references).
Then: `~/.flutter-sdk/bin/flutter test` → PASS.

- [ ] **Step 7: Commit**

```bash
git add -A lib/features/profile lib/data/content_repository.dart test/features/profile_tab_test.dart test/data/content_repository_test.dart test/helpers.dart
git rm lib/features/profile/content_page.dart test/features/profile/content_page_test.dart 2>/dev/null || true
git commit -m "feat(profile): open Terms/Privacy as external links; retire in-app ContentPage"
```

---

### Task 5: Backend — `delete_account` endpoint + User deletion marker

Authenticated endpoint that disables the user, revokes the token, and stamps the marker.

**Files:**
- Create: `~/Frappe/grocery-bench/apps/grocery/grocery/patches/v1_0/add_user_deletion_marker.py`
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/patches.txt`
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/api/auth.py`
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_auth.py`

**Interfaces:**
- Produces: whitelisted `grocery.api.auth.delete_account()` (authed) returning `{"status": "scheduled", "purge_after": "<YYYY-MM-DD>"}`; sets `User.enabled=0`, revokes `api_secret`, sets custom field `custom_deletion_requested_on = today`.
- Consumes (Task 6): the constant `DELETION_GRACE_DAYS` imported from `grocery.tasks.account_deletion`.

- [ ] **Step 1: Add the deletion-marker custom field patch**

Create `grocery/patches/v1_0/add_user_deletion_marker.py`:

```python
import frappe
from frappe.custom.doctype.custom_field.custom_field import create_custom_field


def execute():
	"""Marker on User for the deactivate-and-schedule account deletion flow."""
	create_custom_field(
		"User",
		{
			"fieldname": "custom_deletion_requested_on",
			"label": "Deletion Requested On",
			"fieldtype": "Date",
			"insert_after": "enabled",
			"read_only": 1,
			"no_copy": 1,
			"module": "Grocery",
		},
	)
```

Add to the end of `grocery/patches.txt`:

```
grocery.patches.v1_0.add_user_deletion_marker
```

Apply: `cd ~/Frappe/grocery-bench && bench --site <dev-site> migrate`.

- [ ] **Step 2: Write the failing endpoint test**

Append to `grocery/tests/test_auth.py` (reuse the file's `_unique_phone()` and registration helpers; register+login a user, then call `delete_account` as that user). Follow the existing pattern for acting as a user (`frappe.set_user(user_name)`), and assert the effects:

```python
	def test_delete_account_disables_user_and_revokes_token(self):
		phone = _unique_phone()
		user_name = self._register_user(phone)  # existing helper in this file
		frappe.set_user(user_name)
		try:
			result = auth.delete_account()
		finally:
			frappe.set_user("Administrator")

		self.assertEqual(result["status"], "scheduled")
		self.assertEqual(frappe.db.get_value("User", user_name, "enabled"), 0)
		self.assertEqual(
			str(frappe.db.get_value("User", user_name, "custom_deletion_requested_on")),
			frappe.utils.today(),
		)
		# token is dead: no decryptable api_secret remains
		from frappe.utils.password import get_decrypted_password
		self.assertIsNone(
			get_decrypted_password("User", user_name, "api_secret", raise_exception=False)
		)

	def test_delete_account_rejects_guest(self):
		frappe.set_user("Guest")
		try:
			with self.assertRaises(frappe.AuthenticationError):
				auth.delete_account()
		finally:
			frappe.set_user("Administrator")
```

(If `test_auth.py` has no `_register_user` helper, register inline using the same `verify_and_register` + OTP-mock pattern the other tests in the file use.)

- [ ] **Step 3: Run it to verify it fails**

Run: `cd ~/Frappe/grocery-bench && bench --site <dev-site> run-tests --module grocery.tests.test_auth`
Expected: FAIL — `module 'grocery.api.auth' has no attribute 'delete_account'`.

- [ ] **Step 4: Implement the endpoint**

In `grocery/api/auth.py`, add near the other authed endpoints (after `logout`):

```python
@frappe.whitelist()
def delete_account():
	"""Deactivate-and-schedule account deletion (store-compliance).

	Disables login and revokes the token immediately; a daily job
	(``grocery.tasks.account_deletion.purge_scheduled_deletions``) anonymizes
	personal data after the grace period. Orders/financial records are kept.
	"""
	from grocery.tasks.account_deletion import DELETION_GRACE_DAYS

	user_name = _require_authenticated_user()
	frappe.db.set_value(
		"User",
		user_name,
		{"enabled": 0, "custom_deletion_requested_on": frappe.utils.today()},
	)
	_revoke_api_secret(user_name)
	frappe.db.commit()
	return {
		"status": "scheduled",
		"purge_after": frappe.utils.add_days(frappe.utils.today(), DELETION_GRACE_DAYS),
	}
```

(Task 6 creates `grocery.tasks.account_deletion`; the import is inside the function so this task can be committed and tested after Task 6, or reorder to do Task 6 first. If running Task 5 before Task 6, temporarily inline `DELETION_GRACE_DAYS = 30` and replace with the import in Task 6.)

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd ~/Frappe/grocery-bench && bench --site <dev-site> run-tests --module grocery.tests.test_auth`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/api/auth.py grocery/patches/v1_0/add_user_deletion_marker.py grocery/patches.txt grocery/tests/test_auth.py
git commit -m "feat(auth): delete_account endpoint (deactivate + revoke + stamp marker)"
```

---

### Task 6: Backend — daily purge job

Anonymize personal data of marked users once the grace period elapses.

**Files:**
- Create: `~/Frappe/grocery-bench/apps/grocery/grocery/tasks/account_deletion.py`
- Modify: `~/Frappe/grocery-bench/apps/grocery/grocery/hooks.py:176-181` (`scheduler_events`)
- Test: `~/Frappe/grocery-bench/apps/grocery/grocery/tests/test_account_deletion.py` (create)

**Interfaces:**
- Produces: `DELETION_GRACE_DAYS = 30`; `purge_scheduled_deletions()` (scheduled daily); `_anonymize_user(user_name)`.

- [ ] **Step 1: Write the failing test**

Create `grocery/tests/test_account_deletion.py`:

```python
import frappe
from frappe.tests import IntegrationTestCase
from frappe.utils import add_days, today

from grocery.tasks import account_deletion


class TestAccountDeletion(IntegrationTestCase):
	def _make_marked_user(self, requested_on):
		email = f"del-{frappe.generate_hash(length=8)}@example.com"
		user = frappe.get_doc({
			"doctype": "User",
			"email": email,
			"first_name": "Real",
			"full_name": "Real Name",
			"mobile_no": "0770" + frappe.generate_hash(length=6),
			"enabled": 0,
			"custom_deletion_requested_on": requested_on,
		}).insert(ignore_permissions=True)
		return user.name

	def test_purges_users_past_grace(self):
		old = self._make_marked_user(add_days(today(), -(account_deletion.DELETION_GRACE_DAYS + 1)))
		account_deletion.purge_scheduled_deletions()
		self.assertEqual(frappe.db.get_value("User", old, "full_name"), "Deleted User")
		self.assertFalse(frappe.db.get_value("User", old, "mobile_no"))
		self.assertIsNone(frappe.db.get_value("User", old, "custom_deletion_requested_on"))

	def test_leaves_users_within_grace(self):
		fresh = self._make_marked_user(today())
		account_deletion.purge_scheduled_deletions()
		self.assertEqual(frappe.db.get_value("User", fresh, "full_name"), "Real Name")
		self.assertEqual(
			str(frappe.db.get_value("User", fresh, "custom_deletion_requested_on")), today()
		)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ~/Frappe/grocery-bench && bench --site <dev-site> run-tests --module grocery.tests.test_account_deletion`
Expected: FAIL — `No module named 'grocery.tasks.account_deletion'`.

- [ ] **Step 3: Implement the job**

Create `grocery/tasks/account_deletion.py`:

```python
import frappe
from frappe.utils import add_days, today

DELETION_GRACE_DAYS = 30

ANON_NAME = "Deleted User"


def purge_scheduled_deletions():
	"""Daily: anonymize personal data of users whose deletion was requested
	more than DELETION_GRACE_DAYS ago. Idempotent — clears the marker so a
	row is processed at most once. Keeps the User row and all linked
	orders/financial records intact (Frappe cannot hard-delete a Customer
	with linked documents)."""
	cutoff = add_days(today(), -DELETION_GRACE_DAYS)
	user_names = frappe.get_all(
		"User",
		filters={"custom_deletion_requested_on": ["<=", cutoff]},
		pluck="name",
	)
	for user_name in user_names:
		_anonymize_user(user_name)
	frappe.db.commit()


def _anonymize_user(user_name: str) -> None:
	frappe.db.set_value(
		"User",
		user_name,
		{
			"first_name": ANON_NAME,
			"full_name": ANON_NAME,
			"mobile_no": "",
			"phone": "",
			"enabled": 0,
			"custom_deletion_requested_on": None,
		},
	)
	# Drop the customer's saved delivery addresses (personal data). Orders and
	# invoices are retained; only the address contact details are removed.
	for address in frappe.get_all(
		"Address",
		filters={"custom_app_user": user_name},  # adjust to the real link field
		pluck="name",
	):
		frappe.delete_doc("Address", address, ignore_permissions=True, force=True)
```

> Note: confirm the Address→user link fieldname used elsewhere in the grocery app (grep `Address` in `grocery/api/address.py`) and use that filter; if addresses are linked via `Dynamic Link` to Customer, resolve the customer for `user_name` first. Keep the anonymization of `User` regardless.

- [ ] **Step 4: Register the daily schedule**

In `grocery/hooks.py`, extend `scheduler_events` with a `"daily"` entry (keep the existing `"cron"` block):

```python
scheduler_events = {
	"cron": {
		"*/5 * * * *": ["grocery.tasks.expiry.expire_stale_orders"],
		"* * * * *": ["grocery.tasks.timeouts.requeue_timed_out_assignments"],
	},
	"daily": ["grocery.tasks.account_deletion.purge_scheduled_deletions"],
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd ~/Frappe/grocery-bench && bench --site <dev-site> run-tests --module grocery.tests.test_account_deletion`
Expected: PASS. Also re-run `test_auth` (its `delete_account` import of `DELETION_GRACE_DAYS` now resolves).

- [ ] **Step 6: Commit**

```bash
cd ~/Frappe/grocery-bench/apps/grocery
git add grocery/tasks/account_deletion.py grocery/hooks.py grocery/tests/test_account_deletion.py grocery/api/auth.py
git commit -m "feat(account-deletion): daily purge job anonymizing users past grace"
```

---

### Task 7: App — `AuthRepository.deleteAccount` + `SessionStore.deleteAccount`

Wire the app data layer to the endpoint and the session lifecycle.

**Files:**
- Modify: `lib/data/auth_repository.dart`
- Modify: `lib/core/session/session_store.dart`
- Test: `test/data/auth_repository_test.dart` (append), `test/core/session/session_store_test.dart` (append)

**Interfaces:**
- Produces: `AuthRepository.deleteAccount()` → `Future<void>` (POST `grocery.api.auth.delete_account`); `SessionStore.deleteAccount()` → `Future<void>` (calls repo, then `_clearLocal()` on success only).

- [ ] **Step 1: Write the failing repository test**

Append to `test/data/auth_repository_test.dart` (mirror the file's existing fake-dio pattern used for `logout`/`changePassword`):

```dart
  test('deleteAccount posts to the delete_account endpoint', () async {
    final captured = <RequestOptions>[];
    final repo = AuthRepository(
      ApiClient(
        dio: buildFakeDio(
          (o) => Response(requestOptions: o, statusCode: 200, data: {
            'message': {'status': 'scheduled', 'purge_after': '2026-08-19'},
          }),
          capturedRequests: captured,
        ),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      ),
    );

    await repo.deleteAccount();

    expect(
      captured.single.path,
      endsWith('grocery.api.auth.delete_account'),
    );
  });
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/data/auth_repository_test.dart`
Expected: FAIL — `deleteAccount` not defined on `AuthRepository`.

- [ ] **Step 3: Implement `AuthRepository.deleteAccount`**

In `lib/data/auth_repository.dart`, after `logout()`:

```dart
  Future<void> deleteAccount() async {
    await _client.post('grocery.api.auth.delete_account', data: const {});
  }
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/data/auth_repository_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing SessionStore test**

Append to `test/core/session/session_store_test.dart` (use the file's existing fake `AuthRepository` + `TokenStore(storage: FakeSecureStorage())` setup; start from an authed session):

```dart
  test('deleteAccount clears the session on success', () async {
    // ...arrange an authed store (persist a session) as the file's other tests do...
    await store.deleteAccount();
    expect(store.isAuthed, isFalse);
    expect(store.user, isNull);
  });

  test('deleteAccount keeps the session when the server call fails', () async {
    // ...arrange an authed store whose fake repo.deleteAccount throws...
    await expectLater(store.deleteAccount(), throwsA(isA<Exception>()));
    expect(store.isAuthed, isTrue);
  });
```

(Extend the file's fake `AuthRepository` with a `deleteAccount()` that either returns or throws per a flag, matching how it already fakes `login`/`logout`.)

- [ ] **Step 6: Run it to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/core/session/session_store_test.dart`
Expected: FAIL — `deleteAccount` not defined on `SessionStore` (and the fake repo).

- [ ] **Step 7: Implement `SessionStore.deleteAccount`**

In `lib/core/session/session_store.dart`, after `forceLogout()`:

```dart
  /// Deletes the account server-side, then drops to guest. On failure the
  /// session is kept (the caller surfaces the error) — we only clear locally
  /// once the server has accepted the deletion and revoked the token.
  Future<void> deleteAccount() async {
    _setLoading(true);
    try {
      await _authRepository.deleteAccount();
      await _clearLocal();
    } finally {
      _setLoading(false);
    }
  }
```

- [ ] **Step 8: Run both test files to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/data/auth_repository_test.dart test/core/session/session_store_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/data/auth_repository.dart lib/core/session/session_store.dart test/data/auth_repository_test.dart test/core/session/session_store_test.dart
git commit -m "feat(session): AuthRepository.deleteAccount + SessionStore.deleteAccount"
```

---

### Task 8: App — Delete Account tile + confirm dialog + l10n

The user-facing entry point: a red tile → checkbox-gated warning dialog → delete → logout.

**Files:**
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`
- Modify: `lib/features/profile/profile_tab.dart`
- Test: `test/features/profile_tab_test.dart` (append)

**Interfaces:**
- Consumes: `SessionStore.deleteAccount()` (Task 7); l10n keys below.

- [ ] **Step 1: Add the l10n strings**

In `lib/l10n/app_en.arb` add:

```json
  "deleteAccountTitle": "Delete account",
  "deleteAccountWarning": "Your account will be disabled immediately and your personal data removed after 30 days. Your past orders are kept. This cannot be undone.",
  "deleteAccountConfirmCheckbox": "I understand my account will be permanently deleted",
  "deleteAccountButton": "Delete account",
  "deleteAccountSuccess": "Your account is scheduled for deletion",
```

In `lib/l10n/app_ar.arb` add:

```json
  "deleteAccountTitle": "حذف الحساب",
  "deleteAccountWarning": "سيتم تعطيل حسابك فوراً وحذف بياناتك الشخصية بعد ٣٠ يوماً. تبقى طلباتك السابقة محفوظة. لا يمكن التراجع عن هذا الإجراء.",
  "deleteAccountConfirmCheckbox": "أفهم أنه سيتم حذف حسابي نهائياً",
  "deleteAccountButton": "حذف الحساب",
  "deleteAccountSuccess": "تمت جدولة حذف حسابك",
```

Regenerate: `~/.flutter-sdk/bin/flutter gen-l10n`.

- [ ] **Step 2: Write the failing UI test**

Append to `test/features/profile_tab_test.dart`:

```dart
  testWidgets('delete account: confirm gated by checkbox, then logs out', (
    tester,
  ) async {
    final store = _authedSession(); // fake SessionStore whose deleteAccount succeeds
    await tester.pumpWidget(
      wrapPage(
        const ProfileTab(),
        providers: homeTestProviders(sessionStore: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileMenuDeleteAccount')));
    await tester.pumpAndSettle();

    // Confirm button disabled until the checkbox is ticked.
    final confirm = tester.widget<TextButton>(
      find.byKey(const Key('deleteAccountConfirmButton')),
    );
    expect(confirm.onPressed, isNull);

    await tester.tap(find.byKey(const Key('deleteAccountCheckbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('deleteAccountConfirmButton')));
    await tester.pumpAndSettle();

    expect(store.deleteAccountCalled, isTrue); // fake records the call
  });
```

(Use/extend the test file's existing authed `SessionStore` fake so `deleteAccount()` sets a `deleteAccountCalled` flag and flips the store to guest.)

- [ ] **Step 3: Run it to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/features/profile_tab_test.dart`
Expected: FAIL — no `profileMenuDeleteAccount` tile.

- [ ] **Step 4: Add the tile + confirm dialog**

In `lib/features/profile/profile_tab.dart`, add the tile at the **end** of the authed menu `children` (after the logout tile):

```dart
        _MenuTile(
          key: const Key('profileMenuDeleteAccount'),
          icon: Iconsax.trash,
          label: l10n.deleteAccountTitle,
          destructive: true,
          onTap: () => _confirmDeleteAccount(context),
        ),
```

Add the handler on `_AuthedProfile`:

```dart
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        var checked = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text(l10n.deleteAccountTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.deleteAccountWarning),
                const SizedBox(height: 8),
                CheckboxListTile(
                  key: const Key('deleteAccountCheckbox'),
                  value: checked,
                  onChanged: (v) => setState(() => checked = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.deleteAccountConfirmCheckbox),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                key: const Key('deleteAccountConfirmButton'),
                onPressed: checked
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: Text(
                  l10n.deleteAccountButton,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;
    try {
      await session.deleteAccount();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.deleteAccountSuccess)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : l10n.sectionErrorMessage),
        ),
      );
    }
  }
```

Add `import '../../core/api/api_exceptions.dart';` for `ApiException`.

- [ ] **Step 5: Run the test, then the full suite**

Run: `~/.flutter-sdk/bin/flutter test test/features/profile_tab_test.dart && ~/.flutter-sdk/bin/flutter analyze && ~/.flutter-sdk/bin/flutter test`
Expected: PASS + analyze clean.

- [ ] **Step 6: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_ar.arb lib/features/profile/profile_tab.dart test/features/profile_tab_test.dart
git commit -m "feat(profile): Delete Account tile with checkbox-gated confirm"
```

---

## Verification (after all tasks)

- [ ] Backend: `cd ~/Frappe/grocery-bench && bench --site <dev-site> run-tests --module grocery.tests.test_auth` and `... --module grocery.tests.test_account_deletion` and `... --module grocery.tests.test_content` all green.
- [ ] App: `~/.flutter-sdk/bin/flutter analyze` clean and `~/.flutter-sdk/bin/flutter test` green.
- [ ] Manual (real APK against prod, once backend deployed): Profile → Terms opens the web page in the browser; Privacy likewise; Delete Account → dialog, confirm disabled until the checkbox is ticked → confirm → returns to guest with the success snackbar; re-login is blocked (account disabled). Repeat in Arabic (RTL) to confirm the dialog/tiles render.
- [ ] **Content dependency:** replace the placeholder Web Page text with the real Terms & Privacy copy before store submission; enter the Privacy Policy URL into the Play Console / App Store Connect listings and declare the account-deletion path in the Data safety / App Privacy forms (Sub-project 2).

## Out of scope (Sub-project 2 — deployment setup)

Android release signing (currently debug-signed), versioning/build numbers, icon/splash finalization, iOS release config (needs macOS/Xcode — cannot build on this Linux host), and store-listing/data-safety questionnaires. Separate spec/plan cycle.
