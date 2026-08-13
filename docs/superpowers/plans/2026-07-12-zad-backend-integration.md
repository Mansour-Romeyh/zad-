# Zad Customer App — Backend Integration & Feature Build-out Plan

**Spec:** `/home/frappe/Frappe/grocery-prd-v2.md` (PRD v2.0 FINAL). Backend is ERPNext v16 + custom `grocery` app; all endpoints under `/api/method/grocery.api.{module}.{fn}` per PRD Part F. The current zad app (branch `feature/zad-mvp`) is a UI-only MVP: splash, onboarding, home with static mock data — see `docs/superpowers/specs/2026-07-11-zad-grocery-app-design.md` for the existing design language. This plan wires it to the real backend and builds the remaining customer features per PRD A3.

## Global Constraints

- Repo `/home/frappe/Flutter/zad`, branch `feature/zad-mvp`. Flutter SDK binary: `~/.flutter-sdk/bin/flutter` (NOT on PATH). Run `~/.flutter-sdk/bin/flutter test` and `~/.flutter-sdk/bin/flutter analyze` — both must be clean before every commit. NEVER run Gradle/APK builds in a task (machine RAM constraint).
- Keep the existing design language: `ZadColors`/`zadTheme()` (lib/core/theme.dart), `ZadSpacing`/`ZadRadii` (lib/core/constants.dart), Poppins/Cairo fonts, Material 3. New screens must look like siblings of the existing home screen.
- Localization: EVERY user-visible string goes in `lib/l10n/app_en.arb` + `app_ar.arb` (then `~/.flutter-sdk/bin/flutter gen-l10n`). All new screens must be RTL-safe (use EdgeInsetsDirectional / Alignment*Directional; no hardcoded left/right).
- Packages fixed by this plan (add in Task 1, do not add others without escalating): `dio ^5`, `provider ^6`, `flutter_secure_storage ^9`, `uuid ^4`. Existing: `shared_preferences`, `iconsax`, `intl`.
- Networking: single `ApiClient` wrapper around dio. Base URL from `String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000')` (Android-emulator loopback to host). Frappe success envelope `{"message": ...}` is unwrapped by the client. Error mapping to typed exceptions: 401 `UnauthenticatedException`, 403 `ForbiddenException`, 409 `OutOfStockException(items)`, 417 `OutsideCoverageException`, 423 `OtpCooldownException(cooldownSec)`, 410 `OtpExpiredException`, network/timeout `ApiNetworkException`, else `ApiException(message)`. Server messages may arrive in `_server_messages` (JSON-encoded list) or `message`/`exception` — parse defensively.
- Auth: `Authorization: token {api_key}:{api_secret}` header when logged in; keys in `flutter_secure_storage`. Guest mode = no header; guests can browse catalog/search/content; cart, favourites, checkout, addresses, orders, profile require login → show the shared LoginRequiredSheet that routes to /auth/login.
- State management: `provider` with ChangeNotifier stores (`SessionStore`, `CartStore`, `FavouritesStore`) provided above `MaterialApp` in app.dart; repositories are plain classes injected via `Provider`/constructor. No other state framework.
- Currency: IQD. Replace `formatPrice()` `$`-prefix with IQD formatting: EN `IQD 1,500` / AR `1,500 د.ع` via `intl` NumberFormat with 0 decimals, locale-aware. All price displays go through it.
- Tests: TDD per task. Mock dio (interceptor/adapter stub or a `FakeApiClient`) — NO real network in tests. Reuse/extend `test/helpers.dart` `wrapPage()`; new stores need store-level unit tests plus widget tests per screen (loading/error/success states).
- Weight items (PRD E1): items with `sold_by_weight=true` use gram-step selector: start `weight_step_g` (e.g. 500g), each + adds one step, clamp [min_g, max_g]; cart qty sent in Kg (grams/1000.0); price shown = price_per_uom × kg. Unit items step by 1.
- API field names in requests/responses follow PRD Part F verbatim (e.g. `item_code`, `qty_kg`, `idempotency_key`). Read the PRD file for exact contracts — every task below names its PRD sections.
- Commit at least once per task in this repo with a conventional message (`feat:`, `test:` …). Do not commit generated l10n if repo already gitignores it (check `.gitignore`; app_localizations*.dart are currently committed — keep whichever convention exists).

## Task 1 — Networking foundation: ApiClient, errors, token store, core models & repositories

Read PRD Part F (all), F3 ItemCard shape, F2.

1. Add deps: `dio ^5`, `provider ^6`, `flutter_secure_storage ^9`, `uuid ^4` (pubspec; `~/.flutter-sdk/bin/flutter pub get`).
2. `lib/core/api/api_client.dart`: dio wrapper per Global Constraints — `get(method, {params})`, `post(method, {data})` calling `/api/method/{method}`; unwraps `message`; attaches token header from `TokenStore` when present; typed exceptions in `lib/core/api/api_exceptions.dart` (mapping table in Global Constraints, incl. parsing `_server_messages`).
3. `lib/core/api/token_store.dart`: save/read/clear `{api_key, api_secret, user, full_name, phone}` via flutter_secure_storage (constructor-injectable storage for tests).
4. Models (`lib/models/`), all with `fromJson` factories tolerant of nulls:
   - Extend `Product` to carry ItemCard: `itemCode, name, imageUrl, pricePerUom (double), uom, soldByWeight (bool), weightStepG, minG, maxG, availableQty (double), inStock (bool), isFavourite (bool?)`. Keep `nameEn/nameAr` display compatibility by mapping single `item_name` into both (backend returns localized name; keep `nameFor()` working). Old mock fields that no longer apply (oldPrice) stay nullable.
   - Extend `GroceryCategory`: `name (Item Group id), label, imageUrl, itemCount`.
   - New: `AppBannerModel {imageUrl, title, linkType, linkValue}`, `AppConfig {splashImage, splashBgColor, splashDurationSec, appMinVersion, maintenanceMode}`, `OnboardingSlide {title, subtitle, imageUrl, sequence}`.
5. Repositories (`lib/data/`): `CatalogRepository` (get_categories, items_by_category(item_group, page), get_best_items, get_item), `ContentRepository` (get_onboarding, get_app_config, get_page, home.get_banners) — thin, typed, over ApiClient. Keep `mock_data.dart` (still used by home until Task 3; do NOT delete).
6. Image URLs: backend returns paths like `/files/x.png` — add `resolveFileUrl(String?)` in ApiClient exposing absolute URL (base + path); models store the resolved absolute URL or null.
7. Tests: exception mapping per status code (mock dio adapter); envelope unwrap; token header attach/absent; each model fromJson (full + minimal payloads); repository method → correct endpoint path & params.

## Task 2 — Session & auth: SessionStore, AuthRepository, login/register/OTP/reset screens, guest gating

Read PRD F1, A3.

1. `lib/data/auth_repository.dart`: request_signup_otp(phone), verify_and_register(fullName, phone, password, otp), login(phone, password), request_reset_otp(phone), reset_password(phone, otp, newPassword), change_password(old, new), logout — per F1 shapes.
2. `lib/core/session/session_store.dart` (ChangeNotifier): `status` (guest/authed + loading), profile fields, `login()/register()/logout()/restore()` using TokenStore; on 401 from any API call → auto-logout to guest (dio interceptor hook).
3. Screens under `lib/features/auth/`: LoginPage (phone+password, links to register & forgot), RegisterPage (full name, phone, password → request OTP → OtpPage 6-digit code entry with resend + cooldown countdown honoring 423 `cooldown_sec`), ResetPasswordPage (phone → OTP → new password). Zad design language; Iraqi phone hint (+964). Error banners for wrong OTP / expired (410) / cooldown (423).
4. `LoginRequiredSheet` (shared bottom sheet, ZadRadii.sheet): "سجّل الدخول للمتابعة" + login/register buttons; helper `Future<bool> ensureLoggedIn(BuildContext)` used by cart/fav/checkout taps.
5. Wire providers in `app.dart` (MultiProvider above MaterialApp); routes `/auth/login`, `/auth/register`, `/auth/reset`. Splash: also `SessionStore.restore()` before routing.
6. Home: profile nav icon → ProfileTab placeholder that shows login prompt when guest (full profile in Task 10).
7. Tests: SessionStore login/logout/restore with fake repo+storage; OTP screen resend cooldown behavior; LoginRequiredSheet gating (guest tap → sheet; authed tap → action proceeds); RTL smoke for auth screens.

## Task 3 — Home wired to backend: categories, banners, best items, address header

Read PRD F2, F3.

1. Home consumes real data: categories via CatalogRepository.getCategories, banner(s) via ContentRepository.getBanners (PageView if >1), best items via getBestItems — each section with loading (skeleton/shimmer via simple containers), error (retry button), empty states. Location header shows default address label when authed with address (from Task 8's repo — until then show generic "بغداد" placeholder string from l10n, NOT mock_data).
2. Product card updates: price via IQD formatPrice; `in_stock=false` → grayscale/disabled card with "غير متوفر" badge; unit label from `uom`; heart icon now calls FavouritesStore (Task 7) — until then keep local toggle but route through a `FavouritesStore` interface stub created here (ChangeNotifier with in-memory set) so Task 7 only swaps internals.
3. "Add" button on card: unit item → CartStore.add (Task 6 — create `CartStore` interface stub here, in-memory, with the real API sync arriving in Task 6); weight item → opens product detail (Task 4 covers detail; until then weight items' Add also goes to detail route placeholder). Guest tap → ensureLoggedIn.
4. Remove home's imports of `mock_data.dart`; delete file if nothing else references it (update model/mock tests accordingly — replace with fromJson fixture tests if any gap).
5. Pull-to-refresh on home re-fetches all three sections.
6. Tests: home renders all sections from fake repositories (success), shows retry on failure, zero-stock card disabled; refresh triggers refetch; existing home tests updated to inject fakes via provider overrides in wrapPage.

## Task 4 — Category listing + product detail + weight selector

Read PRD F3, E1.

1. `/category` route → CategoryPage(item_group): paged grid/list of ItemCards (infinite scroll, page_size 20), app bar with category label, empty state.
2. `/product` route → ProductDetailPage(itemCode): hero image, name, price per uom, short desc, availability badge; weight selector for sold_by_weight (E1: start at weight_step_g, +/- one step, clamp min/max, show computed total price live); qty stepper for unit items; Add-to-basket button (CartStore, login-gated) disabled when out of stock; favourite heart in app bar.
3. Category grid tiles on home now navigate to CategoryPage; product cards navigate to detail on body tap.
4. Tests: weight selector math (500g start, steps, clamps, kg conversion, price = kg × price_per_uom — PRD J4), pagination loads next page on scroll, out-of-stock add disabled, guest add → login sheet.

## Task 5 — Search: query, recent, trending

Read PRD F3 (search.*).

1. `SearchRepository`: query(q, page), recent(), clearRecent(), trending().
2. `/search` route → SearchPage: search field autofocused; before typing shows Recent (authed only, with clear-all) + Trending chips; debounced (350ms) query → ItemCard results list (paged); tapping chip runs that query; empty-results state.
3. Home search field (currently `enabled: false`) becomes a tap-through to SearchPage (keep it non-editable on home; it's an entry point).
4. Tests: debounce (single call for rapid typing), recent hidden for guests, trending chips render + tap searches, results render ItemCards.

## Task 6 — Cart: CartStore with guest cart, server sync, merge on login; basket screen

Read PRD F5 (cart.*), E1, J2.

1. `CartRepository`: get(), addItem(itemCode, {qtyKg or qty, uom}), updateItem(row, qty), removeItem(row), clear(), merge(lines).
2. `CartStore` (replace Task 3 stub internals): guest → local cart persisted in shared_preferences (lines: itemCode, qty, uom, price snapshot, name, image); authed → server cart via repository (rows keyed by server row name); on login → `merge()` local lines to server then clear local (PRD J2); exposes items, totals (subtotal via price snapshots server-side authoritative totals when authed), count badge; add-to-cart soft-warning surface (backend warns when stock low — show snackbar, don't block); zero-stock add error surfaced.
3. `/basket` route + bottom-nav Basket tab → BasketPage: line items (image, name, qty stepper honoring weight steps, line total), swipe/trash to remove, clear-all, totals footer, "إتمام الطلب" checkout CTA (→ Task 9 route; until then button present, navigates to placeholder route registered now), guest with local cart sees items + login prompt at checkout.
4. Bottom nav: wire real navigation for Home and Basket (IndexedStack or routes — pick IndexedStack shell page hosting 4 tabs; Favourites/Profile tabs land in Tasks 7/10 with placeholders now); cart count badge on basket icon from CartStore.
5. Tests: guest add/persist/restore, merge-on-login calls repository with local lines then empties local, steppers respect weight steps, totals math, badge count updates, remove/clear.

## Task 7 — Favourites: store, screen, heart sync

Read PRD F8.

1. `WishlistRepository`: list(), add(itemCode), remove(itemCode).
2. `FavouritesStore` (replace Task 3 stub internals): authed → hydrate from list(), optimistic add/remove with rollback on API error; guest → hearts tap → login sheet (no local favourites per PRD — favourite requires login).
3. Favourites tab → FavouritesPage: grid of favourite ItemCards (reuses product card), empty state ("لا توجد مفضلات"), unfavourite from card, add-to-cart from card.
4. Heart state everywhere (home cards, detail, search results, category lists) reads FavouritesStore; `is_favourite` from API payloads seeds the store.
5. Tests: optimistic toggle + rollback, guest gating, page renders/empties, seed-from-ItemCard.

## Task 8 — Addresses: CRUD screens, current location, default address, zone awareness

Read PRD F4, A3, D2 (Address custom fields).

1. Add dep `geolocator ^13` (plan-sanctioned exception to Task 1 package freeze; Android permissions already needed — add to AndroidManifest + iOS Info.plist keys).
2. `AddressRepository`: create/list/update/delete/setDefault + `zone.resolve(lat,lng)` per F4. `AddressModel {name, label (Home/Work/Other), addressLine, city, lat, lng, isDefault}`.
3. `/addresses` route → AddressListPage (cards, default badge, set-default, delete confirm, edit) + AddressFormPage: label chips (منزل/عمل/أخرى), address line + city fields, "استخدام موقعي الحالي" (geolocator with permission flow, graceful denial → manual entry), on save show zone result: in coverage (zone name) or outside-coverage warning banner (address still saved — PRD allows, checkout blocks later).
4. First-login nudge (A3): after register/login, if no addresses → prompt sheet to add address (skippable) — trigger from home once per session.
5. Location header on home: shows default address label/line (tap → AddressListPage); guest → generic city text (tap → login sheet).
6. Tests: repository param mapping, form validation, set-default exclusivity in UI list refresh, outside-coverage banner, guest gating, permission-denied path falls back to manual (mock geolocator via injectable locator function).

## Task 9 — Checkout + orders: place order, confirmation, my orders, order detail + changes feed

Read PRD F5 (order.*), E3 error contract, A2 statuses, J3/J5 client behavior.

1. `OrderRepository`: placeOrder(addressName, idempotencyKey), myOrders({status, page}), detail(name), changes(name).
2. `/checkout` route → CheckoutPage: delivery address selector (default preselected; add-new inline), order summary lines + totals, payment method fixed COD ("الدفع عند الاستلام"), Place Order button → generates uuid idempotency key (held constant across retries of the same attempt), loading state; error handling: 409 OutOfStock → dialog listing unavailable item names + "تحديث السلة" action (refresh cart, remove/flag shorts); 417 OutsideCoverage → dialog directing to change address; network error → retry with SAME key.
3. OrderSuccessPage: order number, status chip "بانتظار التجهيز" (Pending Assignment), CTA to orders list / home. Cart empties (server closed the Quotation; refresh CartStore).
4. `/orders` route (entry from profile tab and success page) → OrdersPage: paged list of order cards (number, date, total, localized fulfilment-status chip with A2 status → AR label map + color coding); OrderDetailPage: lines with est/actual qty (show "تم التعديل" badge when actual≠est), totals, status timeline (placed → assigned → picking → picked → ready → out-for-delivery → delivered; Expired/Cancelled terminal states), changes feed section from order.changes (weight adjustments/substitutions/removals, newest first, Arabic descriptions).
5. Status labels/colors in one map `lib/core/order_status.dart` (reused later by picker/driver apps' conventions).
6. Tests: idempotency key stable across retry, 409 dialog lists items, 417 dialog, success clears cart, status chip mapping for every A2 status, detail renders est/actual + changes feed.

## Task 10 — Profile, notifications, content pages, config polish

Read PRD F2 (notifications, content), F1 change_password, A3.

1. `ProfileRepository` (get/update profile, device_token registration no-op safe if backend lacks push config) + `NotificationsRepository` (list(page), unreadCount(), markRead(name)).
2. Profile tab → ProfilePage (authed): name/phone card, menu: العناوين (→ addresses), طلباتي (→ orders), تغيير كلمة المرور (ChangePasswordPage), الشروط والأحكام + سياسة الخصوصية (ContentPage rendering body_html via simple HTML-lite rendering — use `Html`-free approach: strip tags to text OR render in a WebView-free scrollable with basic tag handling; keep dependency-free: parse <p>/<br>/<li> minimally), الدعم (support_phone from app_config, tel: launch via url intent — skip adding url_launcher; display number copyable instead), تسجيل الخروج (confirm dialog → SessionStore.logout). Guest → login CTA layout.
3. Notifications: bell icon on home app bar with unread badge; NotificationsPage list (paged, mark-read on tap, mark-all optional skip); guest → login sheet.
4. Splash/app boot: fetch get_app_config with 2s timeout — maintenance_mode=true → maintenance screen (blocking, retry); splash colors/duration from config when available (fallback to bundled constants); onboarding slides from get_onboarding when available (fallback to bundled 3 pages) — cache last-good config in shared_preferences.
5. Tests: profile menu navigation, change password flow (wrong old → error surface), notifications badge + mark-read, maintenance mode screen, onboarding fallback when API fails (PRD onboarding resilience precedent exists in splash tests).

## Task 11 — Full-suite pass, analyze, l10n audit, README

1. Run `~/.flutter-sdk/bin/flutter analyze` (zero issues) and full `~/.flutter-sdk/bin/flutter test` (all green). Fix fallout.
2. l10n audit: no hardcoded user-visible strings (grep for Arabic literals & quoted UI strings outside l10n; fix).
3. RTL smoke tests extended to: auth, search, basket, checkout, orders, profile pages.
4. README: dev-run instructions (API_BASE_URL dart-define, backend at grocery.localhost:8000, mock WasenderAPI log for OTP), feature map, architecture sketch (stores/repos/ApiClient).
5. Deferred-minors sweep from `.superpowers/sdd/progress.md` final-review list: fix the cheap ones (Colors.white/redAccent literals → tokens; PageDots count; route constants file) — do not exceed 1 hour scope; list anything skipped.
