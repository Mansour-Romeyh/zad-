# Zad Grocery App — MVP Design (Splash, Onboarding, Home)

**Date:** 2026-07-11
**Status:** Approved by user (verbal "approved" in brainstorming session)

## Overview

Zad is a grocery-shopping Flutter app. This MVP delivers three pixel-faithful screens
based on the Figma design export in `/home/frappe/Downloads/figma-assets-1783722749278.zip`:

1. **Splash screen** — branded launch screen
2. **Onboarding** — 3 swipeable intro pages
3. **Home page** — category grid, promo banner, best-deal product list

The mockups (375×812 iPhone frames) live in the zip as `1_01_splash_screen.png`,
`28_02_onboarding.png`, and `69_10_home_page.png`. They are the visual source of truth.

## Decisions made with the user

| Topic | Decision |
|---|---|
| Splash logo | The mockup's green "R" logo is replaced by a **"Zad" wordmark** in the same green, same layout |
| Onboarding pages | **3 swipeable pages**, same layout; pages 2–3 get new grocery-themed copy written for this app |
| Home data | **Hardcoded mock data** — no backend, no repository layer |
| Localization | **English + Arabic (RTL)**, locale follows the device |
| Architecture | **Feature-first lightweight** (mirrors the user's `voice_guard` project layout) |

## Non-goals (explicitly out of scope)

- Search, filters, cart, product detail, checkout, See-All pages, profile/wishlist tabs
- Any networking or backend integration
- In-app language switcher (device locale only)
- Replicating iOS status-bar/home-indicator chrome from the mockups
- Golden/screenshot tests

Non-home bottom-nav tabs only switch the visual active state; the Add / Shop Now /
See All / search controls render but perform no action.

## Environment

- Flutter 3.41.5 stable, Dart 3.11.3 (SDK at `/home/frappe/.flutter-sdk`)
- Project path: `/home/frappe/Flutter/zad`, platforms: **android, ios**
- Dependencies: `shared_preferences`, `iconsax`, `flutter_localizations` (SDK), `intl`
- Dev: `flutter_lints`

## Architecture & file structure

```
lib/
  main.dart               # entry, runs ZadApp
  app.dart                # MaterialApp: theme, locales, routes
  core/
    theme.dart            # ZadColors, ZadTextStyles, ThemeData
    constants.dart        # spacing, radii, durations, prefs keys
  l10n/
    app_en.arb            # English strings (template)
    app_ar.arb            # Arabic strings
  models/
    category.dart         # Category: id, nameEn, nameAr, imagePath
    product.dart          # Product: id, nameEn, nameAr, unitEn, unitAr,
                          #   price, oldPrice?, imagePath
  data/
    mock_data.dart        # 8 categories, 3 best-deal products, banner content
  features/
    splash/
      splash_page.dart
    onboarding/
      onboarding_page.dart
      widgets/
        onboarding_card.dart      # white rounded sheet: dots, title, body
        page_dots.dart
    home/
      home_page.dart
      widgets/
        location_header.dart
        search_field.dart         # grey pill + green filter button
        section_header.dart       # title + "See All"
        category_grid.dart
        promo_banner.dart
        best_deal_list.dart
        product_card.dart
        zad_bottom_nav.dart
```

- **State:** `StatelessWidget`/`StatefulWidget` + `setState` only. No state-management package.
- **Navigation:** named routes on `MaterialApp`: `/` (splash), `/onboarding`, `/home`,
  using `Navigator.pushReplacementNamed` so back-press never returns to splash/onboarding.
- **Persistence:** `shared_preferences` key `onboarding_done` (bool).

## Design system (`core/theme.dart`)

Colors sampled from the mockups:

| Token | Hex | Used for |
|---|---|---|
| `primary` | `#5AC268` | logo, buttons, active icons, dots, "See All" |
| `ink` | `#101811` | headings, body text |
| `paleGreen` | `#EFF9F0` | onboarding background, promo banner background |
| `surface` | `#FAFAFA` | search field, category tiles, product image area |
| `muted` | `#A9AFAA` | address line, hints, unit size, strikethrough price |
| `white` | `#FFFFFF` | scaffold background, cards |

Typography:

- **Poppins** (Regular 400, Medium 500, SemiBold 600, Bold 700) bundled as TTF assets —
  matches the mockup's geometric sans.
- **Cairo** (same weights) bundled and set as `fontFamilyFallback`, so Arabic glyphs
  automatically render in a matching style.
- Font files are downloaded once during implementation (Google Fonts repo) and committed
  under `assets/fonts/`. If the machine has no network access at implementation time,
  fallback plan: use the `google_fonts` package instead (runtime download) or system fonts,
  and note the substitution in the README.

Shape & spacing:

- Screen padding 20 px; section gap 24 px
- Radii: buttons/tiles 12–14 px, promo banner 16 px, search pill ~28 px (stadium),
  onboarding sheet top radius 30 px
- Buttons: primary green, white text, no elevation

## Screens

### 1. Splash (`features/splash/splash_page.dart`)

- White scaffold. Centered **"Zad"** wordmark: Poppins Bold, ~56 px, `primary` green.
  (Simple styled text — no attempt to recreate the two-tone "R" mark.)
- Produce-spread image (`27_design_…_1.png`, 375×354) anchored to the bottom, full width,
  `BoxFit.fitWidth`, bottom-aligned exactly as in the mockup.
- After 2.5 s (`Timer`): if `onboarding_done` is unset → `/onboarding`, else `/home`.
- No animations — static screen, then navigate.

### 2. Onboarding (`features/onboarding/onboarding_page.dart`)

Layout (per mockup):

- Scaffold background `paleGreen`.
- **Skip control** top-end: localized "Skip" text in `primary` + small green circle with
  arrow icon; tap → set `onboarding_done`, `pushReplacementNamed('/home')`. Visible on
  all three pages.
- **PageView** (3 pages) fills the screen behind a bottom sheet. Each page shows its image
  in the upper ~60% of the screen.
- **White rounded sheet** at the bottom (top corners 30 px, with the subtle notch curve
  around the FAB simplified to a plain rounded card + overlapping FAB):
  - 3 **page dots**: active = wide/green, inactive = grey, animated on page change
  - Title: Poppins SemiBold ~24 px, `ink`, centered, max 2 lines
  - Body: ~14 px, `muted`/dark grey, centered, 2–3 lines
- **Green circular FAB** (56 px) with forward arrow, horizontally centered, overlapping the
  sheet's bottom edge; tap → next page; on page 3 → set `onboarding_done` and go `/home`.
- Swiping and FAB stay in sync (`PageController`).

Content (EN shown; AR translations provided in ARB):

| Page | Image | Title | Body |
|---|---|---|---|
| 1 | Delivery man photo (`30_delivery_concept_…_1.png`) | "Buy Groceries Easily with Us" | Mockup's placeholder text replaced with real copy: "Order fresh groceries from your phone and skip the queue." |
| 2 | Produce spread (`27_design_…_1.png`) | "Fresh Products Every Day" | "Hand-picked fruits, vegetables and daily essentials delivered fresh." |
| 3 | Produce spread (reused) | "Best Deals, Fast Delivery" | "Enjoy exclusive discounts and get your order at your door in minutes." |

Pages 2–3 reuse the produce image because the zip contains only one onboarding photo;
real photos can be swapped in later without layout changes.

### 3. Home (`features/home/home_page.dart`)

Scaffold: white; body = single vertical `ListView`/`CustomScrollView` with 20 px horizontal
padding; `bottomNavigationBar` = custom nav. Sections top to bottom:

1. **Location header** (`location_header.dart`): green location icon (Iconsax `location`),
   column with "Home" + chevron-down (bold, `ink`) and address line
   "6391 Elgin St. Celina, Delaware 10299" (12 px, `muted`); shopping-bag icon
   (Iconsax `bag_2`) at the end. Static.
2. **Search row** (`search_field.dart`): expanded grey pill `TextField` (disabled/decorative)
   with search icon + localized "Search" hint; trailing 48 px green rounded-square button
   with filter/sliders icon (Iconsax `setting_4`).
3. **Shop By Category** (`section_header.dart` + `category_grid.dart`): header row —
   localized title (SemiBold 18 px) + "See All" in `primary`. Grid: 4 columns × 2 rows,
   `shrinkWrap`, no internal scroll. Tile = 76 px rounded `surface` square with product
   image inside (padding ~10 px) + 2-line centered label (11–12 px) below.
4. **Promo banner** (`promo_banner.dart`): full-width `paleGreen` rounded card; start side —
   headline "World Food Festival, Bring the world to your Kitchen!" (SemiBold ~18 px,
   2–3 lines) + green **Shop Now** button; end side — banner product images from the zip,
   bottom-aligned. Static content from mock data.
5. **Best Deal** (`best_deal_list.dart` + `product_card.dart`): section header like #3;
   horizontal `ListView` (~250 px tall) of cards ~160 px wide:
   - `surface` rounded image area with product photo and an outline **heart** icon
     (Iconsax `heart`) top-end; tapping toggles filled/red state (local state only)
   - name (13–14 px, 2 lines max), unit size ("500 ml" / "1 kg", 11 px `muted`)
   - price row: current price (Bold 16 px, `ink`) + old price (12 px `muted`,
     strikethrough) + green **Add** pill button at the end
   - a third card must be partially visible at the screen edge to invite scrolling
6. **Bottom navigation** (`zad_bottom_nav.dart`): white bar, 4 Iconsax icons —
   home, heart, bag, profile. Active item: `primary` colored icon with the small
   green teardrop/blob indicator above it (as in the mockup). Inactive: `ink` outline.
   Tap switches active index (local `setState`) — no page change.

### Mock data (`data/mock_data.dart`)

Categories (8, names in EN + AR):

| # | EN name | Image from zip |
|---|---|---|
| 1 | Vegetables & Fruits | `164_pngitem_1112827_1.png` (fruit pile) |
| 2 | Dairy & Breakfast | cookie box (`166_pngitem_93643_1.png` — verify at copy time) |
| 3 | Cold Drinks & Juices | Coca-Cola can (`190/191_pngitem_…` — verify at copy time) |
| 4 | Instant & Frozen Food | `171_pngitem_2253415_1.png` (Maggi) |
| 5 | Tea & Coffee | `170_image_1570.png` (Taj Mahal) |
| 6 | Atta, Rice & Dal | `174_image_1571.png` (atta bag) |
| 7 | Masala, Oil & Dry Fruits | `178_group_18724.png` (masala + oil) |
| 8 | Chicken, Meat & Fish | `183_image_1574.png` (meat) |

Best-deal products:

| Product | Unit | Price / old | Image |
|---|---|---|---|
| Surf Excel Easy Wash Detergent Power | 500 ml | $12 / ~~$14~~ | `132_image_1577.png` |
| Fortune Arhar Dal (Toor Dal) | 1 kg | $10 / ~~$12~~ | `143_image_1576.png` |
| Fortune Sunflower Oil | 1 L | $8 / ~~$9~~ | `179_image_1573.png` (third, partially visible card) |

Banner: headline + "Shop Now" label localized; images `189_group_18725.png` (or the
individual `190`/`191` pngitems layered — decide at implementation by visual comparison).

Product/category images are copied from the zip into `assets/images/` with meaningful
snake_case names (e.g. `cat_vegetables_fruits.png`, `product_surf_excel.png`,
`onboarding_delivery.png`, `produce_spread.png`). Every "verify at copy time" file is
opened and visually confirmed before wiring in.

## Localization & RTL

- `flutter gen-l10n` via `l10n.yaml`; template `app_en.arb`, plus `app_ar.arb`.
- `supportedLocales: [en, ar]`; no explicit `locale` — device locale wins
  (Arabic device → RTL automatically via `MaterialApp` localization).
- All UI strings go through `AppLocalizations`: onboarding titles/bodies, Skip,
  Search hint, Shop By Category, See All, Best Deal, Shop Now, Add, banner headline,
  location label "Home", nav semantics labels. The street address stays hardcoded
  (mock data, as in mockup).
- Mock data carries `nameEn`/`nameAr` (+ `unitEn`/`unitAr`); a `localizedName(context)`
  helper picks by `Localizations.localeOf(context).languageCode`. Brand names keep
  their English form inside the Arabic string where natural (e.g. "سيرف إكسل").
- Prices stay in the "$12" mockup format via a shared formatter (single place to change
  currency later; Arabic uses the same Western digits as the mockup for now).
- Layout rules: `EdgeInsetsDirectional`, `AlignmentDirectional`, `start/end` everywhere;
  directional icons (arrows, chevrons) use direction-aware widgets or
  `Icons.arrow_forward` variants that mirror under RTL; PageView direction follows
  text direction natively.

## Error handling

Static offline app — no network or IO failure paths beyond `shared_preferences`
(wrapped in try/catch; on failure the app just shows onboarding again, which is benign).
Missing-asset errors are compile/analyze-time concerns, covered by tests below.

## Testing & verification

- `flutter analyze` — zero issues.
- Widget tests:
  - Splash: renders wordmark; after timer fires navigates to `/onboarding` when the flag
    is unset and `/home` when set (mock `SharedPreferences.setMockInitialValues`).
  - Onboarding: 3 pages swipe; dots update; FAB advances pages; FAB on last page and
    Skip both land on home and persist the flag.
  - Home: all six sections render (location header, search, category grid with 8 tiles,
    banner, best-deal list, bottom nav); heart toggle changes state; nav tap changes
    active index.
  - Arabic smoke test: pump `MaterialApp` with `locale: ar` and verify home + onboarding
    render without overflow exceptions (RTL sanity).
- Manual verification: `flutter run` on an available device/emulator, side-by-side visual
  comparison against the three mockups (EN LTR and AR RTL passes).

## Milestones

1. Scaffold project (`flutter create`, platforms android/ios), commit baseline
2. Assets: extract/rename images, bundle fonts, wire `pubspec.yaml`
3. Theme + l10n foundation
4. Splash screen
5. Onboarding flow
6. Home page (sections in order, each a small widget file)
7. Tests + analyze + manual visual pass
