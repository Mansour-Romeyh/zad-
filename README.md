# Zad — grocery customer app

Flutter customer app for the Zad grocery platform (Iraqi market: Arabic-first,
RTL, IQD, cash on delivery). Talks to a Frappe backend (the `grocery` app)
via its whitelisted `api.*` endpoints.

Covers the Customer-app PRD features:

| Feature | Where |
| --- | --- |
| F1 Onboarding & auth (OTP via WhatsApp, login, reset password) | `lib/features/onboarding`, `lib/features/auth` |
| F2 Home (categories, best deals, banners, app config, maintenance mode) | `lib/features/home`, `lib/features/splash` |
| F3 Catalog & search (category grid, product detail, weight items, debounced search) | `lib/features/category`, `lib/features/product`, `lib/features/search` |
| F4 Cart & addresses (guest cart + server sync, address book, delivery zones) | `lib/features/basket`, `lib/features/addresses` |
| F5 Checkout & orders (COD, idempotent place_order, order timeline, change feed) | `lib/features/checkout`, `lib/features/orders` |
| F8 Favourites | `lib/features/favourites` |
| Notifications (feed + unread badge) | `lib/features/notifications` |
| Profile (account menu, change password, content pages, support) | `lib/features/profile` |

## Running against a dev backend

The backend is a Frappe v16 bench (locally at `~/Frappe/grocery-bench`)
serving the site `grocery.localhost:8000`.

```sh
# Android emulator (10.0.2.2 = host loopback). The flag is required for
# local dev: with no --dart-define the default is production
# (https://zad.micronext.net), so release builds are safe if the flag is
# forgotten — but a flag-less `flutter run` would hit prod.
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# Physical device on the same network:
flutter run --dart-define=API_BASE_URL=http://<your-host-ip>:8000
```

The app sends `Host`-independent requests, so point `API_BASE_URL` at
whatever serves the grocery site. Frappe multitenancy note: if the bench
serves by site name, run it with `bench --site grocery.localhost serve` or
set the default site.

**OTP sandbox:** when the WASender `api_token` is unset in the backend's
Grocery Settings, WhatsApp OTPs are not sent — they are logged instead.
Watch `logs/wasender.log` in the bench to read the code while testing
registration/reset flows.

## Architecture

```
ApiClient (dio)  ──►  repositories (plain classes)  ──►  ChangeNotifier stores  ──►  screens
lib/core/api          lib/data/*_repository.dart         lib/core/stores, core/session   lib/features/*
```

- **`ApiClient`** (`lib/core/api/api_client.dart`) wraps dio: base URL from
  `String.fromEnvironment('API_BASE_URL')`, unwraps the Frappe `{"message": …}`
  envelope, attaches `Authorization: token key:secret` when logged in
  (credentials in `flutter_secure_storage` via `TokenStore`), and maps HTTP
  errors to typed exceptions (`401 Unauthenticated`, `409 OutOfStock(items)`,
  `417 OutsideCoverage`, `423 OtpCooldown(sec)`, `410 OtpExpired`, network →
  `ApiNetworkException`). Server messages are parsed defensively from
  `_server_messages` / `message` / `exception`.
- **Repositories** (`lib/data/`) are stateless request/parse classes, one per
  backend module (auth, catalog, content, search, cart, wishlist, address,
  order, notifications, profile).
- **Stores** are `provider` `ChangeNotifier`s registered above `MaterialApp`
  in `lib/app.dart`: `SessionStore` (auth state), `CartStore` (guest cart in
  shared_preferences, merged into the server cart on login), `FavouritesStore`,
  `AddressStore`, `NotificationsStore`, `AppConfigStore` (config fetch with
  cached-then-bundled fallback, maintenance mode).
  - **Session-epoch pattern:** every session-scoped store bumps an internal
    epoch on each login/logout transition; in-flight fetches capture the epoch
    at start and adopt results only if it is unchanged. This is deliberate —
    an `isAuthed`-only guard cannot tell user B's session from user A's, so a
    straggling response could leak one account's data into the next.
- **Guest mode:** browsing (catalog/search/content) needs no login; cart,
  favourites, checkout, addresses, orders and profile gate through the shared
  `LoginRequiredSheet`.
- **Localization:** every user-visible string lives in `lib/l10n/app_en.arb` +
  `app_ar.arb` (`flutter gen-l10n`, generated files committed). All screens
  are RTL-safe (directional edge insets/alignment). Prices go through
  `formatPrice()` (`IQD 1,500` / `1,500 د.ع`), dates through
  `formatDisplayDate()`.
- **Weight items (PRD E1):** `sold_by_weight` products use a gram-step
  selector (`weight_step_g`, clamped to `[min_g, max_g]`); cart quantities are
  sent in kg.
- **Design language:** `ZadColors`/`zadTheme()` (`lib/core/theme.dart`),
  `ZadSpacing`/`ZadRadii` (`lib/core/constants.dart`), Poppins with Cairo
  fallback, Material 3.

## Tests

```sh
flutter analyze          # must be clean
flutter test             # full suite — no real network: fakes stub dio
flutter test test/features/checkout   # one area
```

Widget tests wrap screens with `test/helpers.dart` `wrapPage()` (theme + l10n
+ routes + providers) and fake the backend at the dio layer
(`test/support/fake_dio.dart`), so store/repository/error-mapping logic runs
for real. `test/rtl_smoke_test.dart` renders every major screen in Arabic and
asserts RTL directionality without overflows.
