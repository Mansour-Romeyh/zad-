# Zad Grocery App MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Zad Flutter grocery app MVP: pixel-faithful splash, 3-page onboarding, and home page from the Figma export, with English + Arabic (RTL) localization.

**Architecture:** Feature-first lightweight Flutter app (`core/`, `features/`, `models/`, `data/`, `l10n/`), plain named-route navigation, `setState` only, hardcoded mock data, images/fonts bundled as assets.

**Tech Stack:** Flutter 3.41.5 / Dart 3.11.3, `shared_preferences`, `iconsax`, `flutter_localizations` + gen-l10n, `flutter_lints`.

**Spec:** `docs/superpowers/specs/2026-07-11-zad-grocery-app-design.md` (mockups are the visual source of truth: `1_01_splash_screen.png`, `28_02_onboarding.png`, `69_10_home_page.png` in the zip).

## Global Constraints

- Flutter binary is NOT on PATH. Always use the full path: `/home/frappe/.flutter-sdk/bin/flutter` (aliased below as `$FLUTTER`; each command block sets `FLUTTER=/home/frappe/.flutter-sdk/bin/flutter`).
- Project root: `/home/frappe/Flutter/zad` (already git-initialized, contains `docs/`). All paths below are relative to it unless absolute.
- Figma asset source zip: `/home/frappe/Downloads/figma-assets-1783722749278.zip`.
- Colors (exact): primary `#5AC268`, ink `#101811`, paleGreen `#EFF9F0`, surface `#FAFAFA`, muted `#A9AFAA`, scaffold white.
- Fonts: Poppins (400/500/600/700) + Cairo (400/500/600/700) bundled TTFs; Cairo is the `fontFamilyFallback` for Arabic glyphs.
- Locales: `en` (template) + `ar`, device locale wins (never set `MaterialApp.locale` in app code).
- RTL safety: use `EdgeInsetsDirectional` / `PositionedDirectional` / `start`-`end` for asymmetric layout; `EdgeInsets.symmetric` is fine. Directional arrows use `Icons.arrow_forward` (auto-mirrors), all other icons from `iconsax`.
- No state management package, no networking. `flutter analyze` must report zero issues at every commit.
- Prices render via `formatPrice()` only — `"$12"` format, no decimals.
- Brand wordmark "Zad" on the splash is NOT localized; the app title and all other UI strings are.

---

### Task 1: Scaffold Flutter project

**Files:**
- Create: entire Flutter template via `flutter create` (android, ios) in `/home/frappe/Flutter/zad`

**Interfaces:**
- Produces: package name `zad` (imports are `package:zad/...`), org `com.zad`.

- [ ] **Step 1: Scaffold**

```bash
FLUTTER=/home/frappe/.flutter-sdk/bin/flutter
cd /home/frappe/Flutter/zad
$FLUTTER create --org com.zad --project-name zad --platforms android,ios .
```

Expected: "All done!" (creates `lib/main.dart`, `pubspec.yaml`, `android/`, `ios/`, `test/widget_test.dart`, `.gitignore`; keeps existing `docs/` and `.git/`).

- [ ] **Step 2: Verify template is healthy**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER analyze
$FLUTTER test
```

Expected: `No issues found!` and `All tests passed!`

- [ ] **Step 3: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "chore: scaffold Flutter project (android, ios)"
```

---

### Task 2: Bundle images and fonts as assets

**Files:**
- Create: `assets/images/*.png` (14 files), `assets/fonts/*.ttf` (8 files) + 2 OFL license files
- Modify: `pubspec.yaml` (flutter.assets + flutter.fonts)
- Test: `test/assets_test.dart`

**Interfaces:**
- Produces: asset paths used by all UI tasks, exactly:
  `assets/images/produce_spread.png`, `onboarding_delivery.png`,
  `cat_vegetables_fruits.png`, `cat_dairy_breakfast.png`, `cat_cold_drinks.png`,
  `cat_instant_frozen.png`, `cat_tea_coffee.png`, `cat_atta_rice_dal.png`,
  `cat_masala_oil.png`, `cat_chicken_meat_fish.png`,
  `product_surf_excel.png`, `product_toor_dal.png`, `product_sunflower_oil.png`,
  `banner_products.png`; font families `Poppins` and `Cairo`.

- [ ] **Step 1: Write the failing test**

Create `test/assets_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const expectedImages = <String>[
  'assets/images/produce_spread.png',
  'assets/images/onboarding_delivery.png',
  'assets/images/cat_vegetables_fruits.png',
  'assets/images/cat_dairy_breakfast.png',
  'assets/images/cat_cold_drinks.png',
  'assets/images/cat_instant_frozen.png',
  'assets/images/cat_tea_coffee.png',
  'assets/images/cat_atta_rice_dal.png',
  'assets/images/cat_masala_oil.png',
  'assets/images/cat_chicken_meat_fish.png',
  'assets/images/product_surf_excel.png',
  'assets/images/product_toor_dal.png',
  'assets/images/product_sunflower_oil.png',
  'assets/images/banner_products.png',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all design images are bundled', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    for (final path in expectedImages) {
      expect(assets, contains(path), reason: '$path missing from bundle');
    }
  });

  test('Poppins and Cairo font families are bundled', () async {
    final fontManifest = await rootBundle.loadString('FontManifest.json');
    expect(fontManifest, contains('Poppins'));
    expect(fontManifest, contains('Cairo'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/assets_test.dart
```

Expected: FAIL — asset list does not contain `assets/images/...`.

- [ ] **Step 3: Copy and rename images from the zip**

```bash
SRC=/tmp/zad_figma_src
rm -rf "$SRC" && mkdir -p "$SRC"
unzip -oq /home/frappe/Downloads/figma-assets-1783722749278.zip -d "$SRC"
cd /home/frappe/Flutter/zad
mkdir -p assets/images assets/fonts
cp "$SRC/27_design_78d26ec2_4b2f_4002_acb9_389fc152783c_1.png"  assets/images/produce_spread.png
cp "$SRC"/30_delivery_concept_*.png                             assets/images/onboarding_delivery.png
cp "$SRC/164_pngitem_1112827_1.png"                             assets/images/cat_vegetables_fruits.png
cp "$SRC/166_pngitem_93643_1.png"                               assets/images/cat_dairy_breakfast.png
cp "$SRC/190_pngitem_719451_1.png"                              assets/images/cat_cold_drinks.png
cp "$SRC/171_pngitem_2253415_1.png"                             assets/images/cat_instant_frozen.png
cp "$SRC/170_image_1570.png"                                    assets/images/cat_tea_coffee.png
cp "$SRC/176_image_1569.png"                                    assets/images/cat_atta_rice_dal.png
cp "$SRC/178_group_18724.png"                                   assets/images/cat_masala_oil.png
cp "$SRC/183_image_1574.png"                                    assets/images/cat_chicken_meat_fish.png
cp "$SRC/132_image_1577.png"                                    assets/images/product_surf_excel.png
cp "$SRC/143_image_1576.png"                                    assets/images/product_toor_dal.png
cp "$SRC/179_image_1573.png"                                    assets/images/product_sunflower_oil.png
cp "$SRC/189_group_18725.png"                                   assets/images/banner_products.png
ls assets/images | wc -l   # expected: 14
```

(Image-to-screen mapping was visually verified during planning: 166 = cookie box,
190 = Coca-Cola can, 176 = atta bag, 189 = banner cookie+coke composite.)

- [ ] **Step 4: Download fonts (network verified available)**

```bash
cd /home/frappe/Flutter/zad/assets/fonts
for w in Regular Medium SemiBold Bold; do
  curl -fsSL -o "Poppins-$w.ttf" "https://github.com/google/fonts/raw/main/ofl/poppins/Poppins-$w.ttf"
done
curl -fsSL -o /tmp/cairo.zip "https://gwfh.mranftl.com/api/fonts/cairo?download=zip&subsets=arabic,latin&variants=regular,500,600,700&formats=ttf"
rm -rf /tmp/cairo && unzip -oq /tmp/cairo.zip -d /tmp/cairo
cp /tmp/cairo/*-regular.ttf Cairo-Regular.ttf
cp /tmp/cairo/*-500.ttf     Cairo-Medium.ttf
cp /tmp/cairo/*-600.ttf     Cairo-SemiBold.ttf
cp /tmp/cairo/*-700.ttf     Cairo-Bold.ttf
curl -fsSL -o OFL-Poppins.txt "https://github.com/google/fonts/raw/main/ofl/poppins/OFL.txt"
curl -fsSL -o OFL-Cairo.txt   "https://github.com/google/fonts/raw/main/ofl/cairo/OFL.txt"
ls *.ttf | wc -l   # expected: 8
file *.ttf         # every line must say "TrueType Font data"
```

If a download fails, retry once; if the gwfh Cairo zip has different variant
filenames, run `ls /tmp/cairo` and map: regular→Regular, 500→Medium, 600→SemiBold, 700→Bold.

- [ ] **Step 5: Declare assets and fonts in pubspec.yaml**

In `pubspec.yaml`, replace the existing `flutter:` section at the bottom (keeping
`uses-material-design: true`) with:

```yaml
flutter:
  uses-material-design: true

  assets:
    - assets/images/

  fonts:
    - family: Poppins
      fonts:
        - asset: assets/fonts/Poppins-Regular.ttf
        - asset: assets/fonts/Poppins-Medium.ttf
          weight: 500
        - asset: assets/fonts/Poppins-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Poppins-Bold.ttf
          weight: 700
    - family: Cairo
      fonts:
        - asset: assets/fonts/Cairo-Regular.ttf
        - asset: assets/fonts/Cairo-Medium.ttf
          weight: 500
        - asset: assets/fonts/Cairo-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Cairo-Bold.ttf
          weight: 700
```

- [ ] **Step 6: Run test to verify it passes**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER pub get
$FLUTTER test test/assets_test.dart
```

Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "feat: bundle design images and Poppins/Cairo fonts"
```

---

### Task 3: Design system — constants and theme

**Files:**
- Create: `lib/core/constants.dart`, `lib/core/theme.dart`
- Test: `test/core/theme_test.dart`

**Interfaces:**
- Produces:
  - `ZadColors.primary/.ink/.paleGreen/.surface/.muted` (`Color` constants)
  - `ThemeData zadTheme()`
  - `ZadSpacing.screenPadding` (20.0), `ZadSpacing.sectionGap` (24.0)
  - `ZadRadii.tile` (14.0), `.banner` (16.0), `.sheet` (30.0), `.button` (12.0)
  - `const kSplashDuration = Duration(milliseconds: 2500)`
  - `const kOnboardingDoneKey = 'onboarding_done'`
  - `String formatPrice(num price)` → `"$12"`

- [ ] **Step 1: Write the failing test**

Create `test/core/theme_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/core/theme.dart';

void main() {
  test('color tokens match the Figma design', () {
    expect(ZadColors.primary, const Color(0xFF5AC268));
    expect(ZadColors.ink, const Color(0xFF101811));
    expect(ZadColors.paleGreen, const Color(0xFFEFF9F0));
    expect(ZadColors.surface, const Color(0xFFFAFAFA));
    expect(ZadColors.muted, const Color(0xFFA9AFAA));
  });

  test('theme uses Poppins with Cairo fallback on white scaffold', () {
    final theme = zadTheme();
    expect(theme.scaffoldBackgroundColor, Colors.white);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Poppins');
    expect(theme.textTheme.bodyMedium?.fontFamilyFallback, contains('Cairo'));
    expect(theme.colorScheme.primary, ZadColors.primary);
  });

  test('formatPrice renders whole dollars', () {
    expect(formatPrice(12), r'$12');
    expect(formatPrice(9.0), r'$9');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/core/theme_test.dart
```

Expected: FAIL — `package:zad/core/constants.dart` does not exist.

- [ ] **Step 3: Implement constants and theme**

Create `lib/core/constants.dart`:

```dart
abstract final class ZadSpacing {
  static const double screenPadding = 20;
  static const double sectionGap = 24;
}

abstract final class ZadRadii {
  static const double tile = 14;
  static const double banner = 16;
  static const double sheet = 30;
  static const double button = 12;
}

const kSplashDuration = Duration(milliseconds: 2500);
const kOnboardingDoneKey = 'onboarding_done';

String formatPrice(num price) => '\$${price.toStringAsFixed(0)}';
```

Create `lib/core/theme.dart`:

```dart
import 'package:flutter/material.dart';

abstract final class ZadColors {
  static const primary = Color(0xFF5AC268);
  static const ink = Color(0xFF101811);
  static const paleGreen = Color(0xFFEFF9F0);
  static const surface = Color(0xFFFAFAFA);
  static const muted = Color(0xFFA9AFAA);
}

ThemeData zadTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ZadColors.primary,
      primary: ZadColors.primary,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: Colors.white,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Poppins',
      fontFamilyFallback: const ['Cairo'],
      bodyColor: ZadColors.ink,
      displayColor: ZadColors.ink,
    ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/core/theme_test.dart && $FLUTTER analyze
```

Expected: PASS (3 tests), `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "feat: add Zad color tokens, theme, and layout constants"
```

---

### Task 4: Dependencies, localization (EN/AR), and app shell

**Files:**
- Modify: `pubspec.yaml` (dependencies + `generate: true`)
- Create: `l10n.yaml`, `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`, `lib/app.dart`
- Modify: `lib/main.dart` (replace template entirely)
- Delete: `test/widget_test.dart` (references the deleted template app)
- Test: `test/helpers.dart`, `test/app_test.dart`

**Interfaces:**
- Consumes: `zadTheme()` from Task 3.
- Produces:
  - `class ZadApp extends StatelessWidget` in `lib/app.dart` (Task 10 later adds routes)
  - Generated `AppLocalizations` at `package:zad/l10n/app_localizations.dart` with
    non-nullable getter: `AppLocalizations.of(context).skip` etc. Keys:
    `appTitle, skip, onb1Title, onb1Body, onb2Title, onb2Body, onb3Title, onb3Body,
    searchHint, shopByCategory, seeAll, bestDeal, bannerHeadline, shopNow, add, homeLabel,
    navHome, navFavorites, navCart, navProfile`
  - Test helper: `Widget wrapPage(Widget child, {Locale locale, Map<String, WidgetBuilder> routes})`

- [ ] **Step 1: Add dependencies and enable generation**

In `pubspec.yaml` replace the `dependencies:` block with:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  intl: any
  shared_preferences: ^2.3.0
  iconsax: ^0.0.8
```

(Leave `dev_dependencies` with `flutter_test` and `flutter_lints` as scaffolded.
Remove the template's `cupertino_icons` line if present — it is unused.)

In the same file add `generate: true` under `flutter:`:

```yaml
flutter:
  uses-material-design: true
  generate: true
```

(keep the `assets:` and `fonts:` sections from Task 2 below it).

Create `l10n.yaml` in the project root:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
nullable-getter: false
```

- [ ] **Step 2: Write the ARB files**

Create `lib/l10n/app_en.arb`:

```json
{
  "@@locale": "en",
  "appTitle": "Zad",
  "skip": "Skip",
  "onb1Title": "Buy Groceries Easily with Us",
  "onb1Body": "Order fresh groceries from your phone and skip the queue.",
  "onb2Title": "Fresh Products Every Day",
  "onb2Body": "Hand-picked fruits, vegetables and daily essentials delivered fresh.",
  "onb3Title": "Best Deals, Fast Delivery",
  "onb3Body": "Enjoy exclusive discounts and get your order at your door in minutes.",
  "searchHint": "Search",
  "shopByCategory": "Shop By Category",
  "seeAll": "See All",
  "bestDeal": "Best Deal",
  "bannerHeadline": "World Food Festival, Bring the world to your Kitchen!",
  "shopNow": "Shop Now",
  "add": "Add",
  "homeLabel": "Home",
  "navHome": "Home",
  "navFavorites": "Favorites",
  "navCart": "Cart",
  "navProfile": "Profile"
}
```

Create `lib/l10n/app_ar.arb`:

```json
{
  "@@locale": "ar",
  "appTitle": "زاد",
  "skip": "تخطي",
  "onb1Title": "اشترِ مقاضيك بسهولة معنا",
  "onb1Body": "اطلب مقاضيك الطازجة من هاتفك وتجنّب الطوابير.",
  "onb2Title": "منتجات طازجة كل يوم",
  "onb2Body": "فواكه وخضروات ومستلزمات يومية مختارة بعناية تصلك طازجة.",
  "onb3Title": "أفضل العروض وتوصيل سريع",
  "onb3Body": "استمتع بخصومات حصرية واستلم طلبك عند بابك خلال دقائق.",
  "searchHint": "ابحث",
  "shopByCategory": "تسوق حسب الفئة",
  "seeAll": "عرض الكل",
  "bestDeal": "أفضل العروض",
  "bannerHeadline": "مهرجان الطعام العالمي، اجلب العالم إلى مطبخك!",
  "shopNow": "تسوق الآن",
  "add": "أضف",
  "homeLabel": "المنزل",
  "navHome": "الرئيسية",
  "navFavorites": "المفضلة",
  "navCart": "السلة",
  "navProfile": "الملف الشخصي"
}
```

- [ ] **Step 3: Generate and verify localizations**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER pub get
$FLUTTER gen-l10n
ls lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_ar.dart
```

Expected: all three generated files exist.

- [ ] **Step 4: Write the failing tests**

Delete the template test:

```bash
rm /home/frappe/Flutter/zad/test/widget_test.dart
```

Create `test/helpers.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/l10n/app_localizations.dart';

Widget wrapPage(
  Widget child, {
  Locale locale = const Locale('en'),
  Map<String, WidgetBuilder> routes = const {},
}) {
  return MaterialApp(
    locale: locale,
    theme: zadTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routes: routes,
    home: child,
  );
}
```

Create `test/app_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/app.dart';
import 'package:zad/l10n/app_localizations.dart';

import 'helpers.dart';

void main() {
  testWidgets('ZadApp builds a localized MaterialApp', (tester) async {
    await tester.pumpWidget(const ZadApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.supportedLocales, contains(const Locale('ar')));
    expect(app.locale, isNull); // device locale wins
  });

  testWidgets('Arabic strings resolve', (tester) async {
    await tester.pumpWidget(wrapPage(
      Builder(builder: (c) => Text(AppLocalizations.of(c).skip)),
      locale: const Locale('ar'),
    ));
    expect(find.text('تخطي'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Run tests to verify they fail**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/app_test.dart
```

Expected: FAIL — `package:zad/app.dart` does not exist.

- [ ] **Step 6: Implement app shell and entry point**

Create `lib/app.dart`:

```dart
import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'l10n/app_localizations.dart';

class ZadApp extends StatelessWidget {
  const ZadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: zadTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const SizedBox.shrink(),
    );
  }
}
```

(`home` is a temporary empty widget; Task 10 replaces it with the route table.)

Replace `lib/main.dart` entirely with:

```dart
import 'package:flutter/material.dart';

import 'app.dart';

void main() {
  runApp(const ZadApp());
}
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test && $FLUTTER analyze
```

Expected: all tests pass (assets + theme + app), `No issues found!`
(Generated `lib/l10n/app_localizations*.dart` files are lint-clean on Flutter
3.41. If analyze ever flags them, report it — do not edit generated files or
`analysis_options.yaml` to suppress.)

- [ ] **Step 8: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "feat: app shell with EN/AR localization following device locale"
```

---

### Task 5: Models and mock data

**Files:**
- Create: `lib/models/category.dart`, `lib/models/product.dart`, `lib/data/mock_data.dart`
- Test: `test/models_test.dart`

**Interfaces:**
- Consumes: nothing (pure Dart).
- Produces:
  - `class GroceryCategory { String id; String nameEn; String nameAr; String imagePath; String nameFor(String languageCode); }`
  - `class Product { String id; String nameEn; String nameAr; String unitEn; String unitAr; double price; double? oldPrice; String imagePath; String nameFor(String languageCode); String unitFor(String languageCode); }`
  - `const List<GroceryCategory> mockCategories` (8 items, order matches mockup)
  - `const List<Product> mockProducts` (3 items)
  - `const String mockAddress = '6391 Elgin St. Celina, Delaware 10299'`
  - `const String bannerImagePath = 'assets/images/banner_products.png'`

- [ ] **Step 1: Write the failing test**

Create `test/models_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/data/mock_data.dart';

void main() {
  test('mock catalog matches the mockup', () {
    expect(mockCategories, hasLength(8));
    expect(mockCategories.first.nameEn, 'Vegetables & Fruits');
    expect(mockCategories.last.nameEn, 'Chicken, Meat & Fish');
    expect(mockProducts, hasLength(3));
    expect(mockProducts.first.nameEn, 'Surf Excel Easy Wash Detergent Power');
    expect(mockProducts.first.price, 12);
    expect(mockProducts.first.oldPrice, 14);
  });

  test('names and units localize by language code', () {
    final cat = mockCategories.first;
    expect(cat.nameFor('en'), 'Vegetables & Fruits');
    expect(cat.nameFor('ar'), 'خضروات وفواكه');
    final p = mockProducts.first;
    expect(p.unitFor('en'), '500 ml');
    expect(p.unitFor('ar'), '500 مل');
  });

  test('every mock item points at a bundled image path', () {
    for (final c in mockCategories) {
      expect(c.imagePath, startsWith('assets/images/cat_'));
    }
    for (final p in mockProducts) {
      expect(p.imagePath, startsWith('assets/images/product_'));
    }
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/models_test.dart
```

Expected: FAIL — `package:zad/data/mock_data.dart` does not exist.

- [ ] **Step 3: Implement models and mock data**

Create `lib/models/category.dart`:

```dart
class GroceryCategory {
  const GroceryCategory({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.imagePath,
  });

  final String id;
  final String nameEn;
  final String nameAr;
  final String imagePath;

  String nameFor(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;
}
```

Create `lib/models/product.dart`:

```dart
class Product {
  const Product({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.unitEn,
    required this.unitAr,
    required this.price,
    this.oldPrice,
    required this.imagePath,
  });

  final String id;
  final String nameEn;
  final String nameAr;
  final String unitEn;
  final String unitAr;
  final double price;
  final double? oldPrice;
  final String imagePath;

  String nameFor(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;
  String unitFor(String languageCode) => languageCode == 'ar' ? unitAr : unitEn;
}
```

Create `lib/data/mock_data.dart`:

```dart
import '../models/category.dart';
import '../models/product.dart';

const mockAddress = '6391 Elgin St. Celina, Delaware 10299';
const bannerImagePath = 'assets/images/banner_products.png';

const mockCategories = <GroceryCategory>[
  GroceryCategory(
    id: 'veg_fruits',
    nameEn: 'Vegetables & Fruits',
    nameAr: 'خضروات وفواكه',
    imagePath: 'assets/images/cat_vegetables_fruits.png',
  ),
  GroceryCategory(
    id: 'dairy_breakfast',
    nameEn: 'Dairy & Breakfast',
    nameAr: 'ألبان وفطور',
    imagePath: 'assets/images/cat_dairy_breakfast.png',
  ),
  GroceryCategory(
    id: 'cold_drinks',
    nameEn: 'Cold Drinks & Juices',
    nameAr: 'مشروبات باردة وعصائر',
    imagePath: 'assets/images/cat_cold_drinks.png',
  ),
  GroceryCategory(
    id: 'instant_frozen',
    nameEn: 'Instant & Frozen Food',
    nameAr: 'أطعمة فورية ومجمدة',
    imagePath: 'assets/images/cat_instant_frozen.png',
  ),
  GroceryCategory(
    id: 'tea_coffee',
    nameEn: 'Tea & Coffee',
    nameAr: 'شاي وقهوة',
    imagePath: 'assets/images/cat_tea_coffee.png',
  ),
  GroceryCategory(
    id: 'atta_rice_dal',
    nameEn: 'Atta, Rice & Dal',
    nameAr: 'طحين وأرز وبقوليات',
    imagePath: 'assets/images/cat_atta_rice_dal.png',
  ),
  GroceryCategory(
    id: 'masala_oil',
    nameEn: 'Masala, Oil & Dry Fruits',
    nameAr: 'بهارات وزيوت ومكسرات',
    imagePath: 'assets/images/cat_masala_oil.png',
  ),
  GroceryCategory(
    id: 'chicken_meat_fish',
    nameEn: 'Chicken, Meat & Fish',
    nameAr: 'دجاج ولحوم وأسماك',
    imagePath: 'assets/images/cat_chicken_meat_fish.png',
  ),
];

const mockProducts = <Product>[
  Product(
    id: 'surf_excel',
    nameEn: 'Surf Excel Easy Wash Detergent Power',
    nameAr: 'سيرف إكسل مسحوق غسيل سهل الغسل',
    unitEn: '500 ml',
    unitAr: '500 مل',
    price: 12,
    oldPrice: 14,
    imagePath: 'assets/images/product_surf_excel.png',
  ),
  Product(
    id: 'toor_dal',
    nameEn: 'Fortune Arhar Dal (Toor Dal)',
    nameAr: 'فورتشن عدس أصفر (تور دال)',
    unitEn: '1 kg',
    unitAr: '1 كغم',
    price: 10,
    oldPrice: 12,
    imagePath: 'assets/images/product_toor_dal.png',
  ),
  Product(
    id: 'sunflower_oil',
    nameEn: 'Fortune Sunflower Oil',
    nameAr: 'فورتشن زيت دوار الشمس',
    unitEn: '1 L',
    unitAr: '1 لتر',
    price: 8,
    oldPrice: 9,
    imagePath: 'assets/images/product_sunflower_oil.png',
  ),
];
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/models_test.dart && $FLUTTER analyze
```

Expected: PASS (3 tests), `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "feat: grocery category/product models and mock catalog data"
```

---

### Task 6: Home shell — location header, search row, bottom nav

**Files:**
- Create: `lib/features/home/home_page.dart`,
  `lib/features/home/widgets/location_header.dart`,
  `lib/features/home/widgets/search_field.dart`,
  `lib/features/home/widgets/zad_bottom_nav.dart`
- Test: `test/features/home_shell_test.dart`

**Interfaces:**
- Consumes: `ZadColors`, `ZadSpacing`, `ZadRadii` (Task 3), `mockAddress` (Task 5), `AppLocalizations` (Task 4).
- Produces:
  - `class HomePage extends StatefulWidget` with `const HomePage({super.key})`
  - `class ZadBottomNav extends StatelessWidget` —
    `const ZadBottomNav({required int activeIndex, required ValueChanged<int> onTap, super.key})`
  - `class LocationHeader extends StatelessWidget`, `class SearchField extends StatelessWidget` (both `const`, no params)
  - Tasks 7–8 will append section widgets to `HomePage`'s `ListView` children.

- [ ] **Step 1: Write the failing test**

Create `test/features/home_shell_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/data/mock_data.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/zad_bottom_nav.dart';

import '../helpers.dart';

void main() {
  testWidgets('home shows location header and decorative search', (tester) async {
    await tester.pumpWidget(wrapPage(const HomePage()));
    expect(find.text('Home'), findsOneWidget);
    expect(find.text(mockAddress), findsOneWidget);
    expect(find.text('Search'), findsOneWidget); // hint
    expect(find.byIcon(Iconsax.location), findsOneWidget);
    expect(find.byIcon(Iconsax.setting_4), findsOneWidget); // filter button
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse); // decorative only
  });

  testWidgets('bottom nav switches active item locally', (tester) async {
    await tester.pumpWidget(wrapPage(const HomePage()));
    // Scope to the nav bar: heart/bag icons also appear elsewhere on home.
    final nav = find.byType(ZadBottomNav);
    Finder navIcon(IconData d) =>
        find.descendant(of: nav, matching: find.byIcon(d));
    Icon iconOf(IconData d) => tester.widget<Icon>(navIcon(d));
    // Home icon is active (primary) initially.
    expect(iconOf(Iconsax.home_2).color, ZadColors.primary);
    // Tap the heart nav item — it becomes active, home becomes inactive.
    await tester.tap(navIcon(Iconsax.heart));
    await tester.pump();
    expect(iconOf(Iconsax.heart).color, ZadColors.primary);
    expect(iconOf(Iconsax.home_2).color, ZadColors.ink);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/features/home_shell_test.dart
```

Expected: FAIL — `package:zad/features/home/home_page.dart` does not exist.

- [ ] **Step 3: Implement the widgets**

Create `lib/features/home/widgets/location_header.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme.dart';
import '../../../data/mock_data.dart';
import '../../../l10n/app_localizations.dart';

class LocationHeader extends StatelessWidget {
  const LocationHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        const Icon(Iconsax.location, color: ZadColors.primary, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.homeLabel,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: ZadColors.ink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Iconsax.arrow_down_1, size: 14, color: ZadColors.ink),
                ],
              ),
              Text(
                mockAddress,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: ZadColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Iconsax.bag_2, color: ZadColors.ink, size: 24),
      ],
    );
  }
}
```

Create `lib/features/home/widgets/search_field.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';

class SearchField extends StatelessWidget {
  const SearchField({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            decoration: const BoxDecoration(
              color: ZadColors.surface,
              borderRadius: BorderRadius.all(Radius.circular(26)),
            ),
            child: TextField(
              enabled: false,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: l10n.searchHint,
                hintStyle: const TextStyle(fontSize: 14, color: ZadColors.muted),
                prefixIcon:
                    const Icon(Iconsax.search_normal_1, color: ZadColors.muted, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: ZadColors.primary,
            borderRadius: BorderRadius.circular(ZadRadii.tile),
          ),
          child: const Icon(Iconsax.setting_4, color: Colors.white, size: 24),
        ),
      ],
    );
  }
}
```

Create `lib/features/home/widgets/zad_bottom_nav.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';

const _navIcons = <IconData>[
  Iconsax.home_2,
  Iconsax.heart,
  Iconsax.bag_2,
  Iconsax.user,
];

class ZadBottomNav extends StatelessWidget {
  const ZadBottomNav({
    required this.activeIndex,
    required this.onTap,
    super.key,
  });

  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = <String>[
      l10n.navHome,
      l10n.navFavorites,
      l10n.navCart,
      l10n.navProfile,
    ];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: ZadColors.ink.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _navIcons.length; i++)
                _NavItem(
                  icon: _navIcons[i],
                  label: labels[i],
                  active: i == activeIndex,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 5,
                decoration: BoxDecoration(
                  color: active ? ZadColors.primary : Colors.transparent,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(4)),
                ),
              ),
              const SizedBox(height: 12),
              Icon(icon,
                  size: 24,
                  color: active ? ZadColors.primary : ZadColors.ink),
            ],
          ),
        ),
      ),
    );
  }
}
```

Create `lib/features/home/home_page.dart`:

```dart
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'widgets/location_header.dart';
import 'widgets/search_field.dart';
import 'widgets/zad_bottom_nav.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    const hPad =
        EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding);
    return Scaffold(
      bottomNavigationBar: ZadBottomNav(
        activeIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
      body: SafeArea(
        child: ListView(
          children: const [
            SizedBox(height: 12),
            Padding(padding: hPad, child: LocationHeader()),
            SizedBox(height: 20),
            Padding(padding: hPad, child: SearchField()),
            SizedBox(height: ZadSpacing.sectionGap),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/features/home_shell_test.dart && $FLUTTER analyze
```

Expected: PASS (2 tests), `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "feat: home shell with location header, search row, and bottom nav"
```

---

### Task 7: Home content — category grid and promo banner

**Files:**
- Create: `lib/features/home/widgets/section_header.dart`,
  `lib/features/home/widgets/category_grid.dart`,
  `lib/features/home/widgets/promo_banner.dart`
- Modify: `lib/features/home/home_page.dart` (append sections)
- Test: `test/features/home_content_test.dart`

**Interfaces:**
- Consumes: `mockCategories`, `bannerImagePath` (Task 5), `GroceryCategory.nameFor` (Task 5), theme tokens (Task 3), l10n keys (Task 4).
- Produces:
  - `class SectionHeader extends StatelessWidget` — `const SectionHeader({required String title, super.key})` (renders title + localized "See All"); reused by Task 8.
  - `class CategoryGrid extends StatelessWidget` (const, no params — reads `mockCategories`)
  - `class PromoBanner extends StatelessWidget` (const, no params)

- [ ] **Step 1: Write the failing test**

Create `test/features/home_content_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/data/mock_data.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/category_grid.dart';

import '../helpers.dart';

void main() {
  testWidgets('home shows the 8-category grid and promo banner', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrapPage(const HomePage()));

    expect(find.text('Shop By Category'), findsOneWidget);
    expect(find.text('See All'), findsWidgets);
    for (final c in mockCategories) {
      expect(find.text(c.nameEn), findsOneWidget);
    }
    expect(
      find.descendant(
        of: find.byType(CategoryGrid),
        matching: find.byType(Image),
      ),
      findsNWidgets(8),
    );
    expect(
      find.text('World Food Festival, Bring the world to your Kitchen!'),
      findsOneWidget,
    );
    expect(find.text('Shop Now'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/features/home_content_test.dart
```

Expected: FAIL — `category_grid.dart` does not exist.

- [ ] **Step 3: Implement the widgets**

Create `lib/features/home/widgets/section_header.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ZadColors.ink,
          ),
        ),
        Text(
          l10n.seeAll,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: ZadColors.primary,
          ),
        ),
      ],
    );
  }
}
```

Create `lib/features/home/widgets/category_grid.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../data/mock_data.dart';

class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: mockCategories.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
        childAspectRatio: 0.68,
      ),
      itemBuilder: (context, index) {
        final category = mockCategories[index];
        return Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: ZadColors.surface,
                  borderRadius: BorderRadius.circular(ZadRadii.tile),
                ),
                padding: const EdgeInsets.all(10),
                child: Image.asset(category.imagePath, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                category.nameFor(languageCode),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: ZadColors.ink,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
```

Create `lib/features/home/widgets/promo_banner.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../data/mock_data.dart';
import '../../../l10n/app_localizations.dart';

class PromoBanner extends StatelessWidget {
  const PromoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ZadColors.paleGreen,
        borderRadius: BorderRadius.circular(ZadRadii.banner),
      ),
      padding: const EdgeInsetsDirectional.only(start: 20, top: 20, bottom: 20, end: 12),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.bannerHeadline,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: ZadColors.ink,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: ZadColors.primary,
                    borderRadius: BorderRadius.circular(ZadRadii.button),
                  ),
                  child: Text(
                    l10n.shopNow,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Image.asset(
              bannerImagePath,
              height: 120,
              fit: BoxFit.contain,
              alignment: AlignmentDirectional.bottomEnd,
            ),
          ),
        ],
      ),
    );
  }
}
```

Modify `lib/features/home/home_page.dart` — replace the whole file with:

```dart
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/category_grid.dart';
import 'widgets/location_header.dart';
import 'widgets/promo_banner.dart';
import 'widgets/search_field.dart';
import 'widgets/section_header.dart';
import 'widgets/zad_bottom_nav.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _navIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const hPad =
        EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding);
    return Scaffold(
      bottomNavigationBar: ZadBottomNav(
        activeIndex: _navIndex,
        onTap: (i) => setState(() => _navIndex = i),
      ),
      body: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 12),
            const Padding(padding: hPad, child: LocationHeader()),
            const SizedBox(height: 20),
            const Padding(padding: hPad, child: SearchField()),
            const SizedBox(height: ZadSpacing.sectionGap),
            Padding(
              padding: hPad,
              child: SectionHeader(title: l10n.shopByCategory),
            ),
            const SizedBox(height: 12),
            const Padding(padding: hPad, child: CategoryGrid()),
            const SizedBox(height: ZadSpacing.sectionGap),
            const Padding(padding: hPad, child: PromoBanner()),
            const SizedBox(height: ZadSpacing.sectionGap),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/features/ && $FLUTTER analyze
```

Expected: PASS (home shell + home content tests), `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "feat: home category grid and promo banner sections"
```

---

### Task 8: Home content — best-deal list with product cards

**Files:**
- Create: `lib/features/home/widgets/product_card.dart`,
  `lib/features/home/widgets/best_deal_list.dart`
- Modify: `lib/features/home/home_page.dart` (append the Best Deal section)
- Test: `test/features/best_deal_test.dart`

**Interfaces:**
- Consumes: `mockProducts`, `Product.nameFor/unitFor` (Task 5), `formatPrice` (Task 3), `SectionHeader` (Task 7), l10n `bestDeal`/`add` (Task 4).
- Produces:
  - `class ProductCard extends StatefulWidget` — `const ProductCard({required Product product, super.key})`, local favorite toggle
  - `class BestDealList extends StatelessWidget` (const, no params — reads `mockProducts`)

- [ ] **Step 1: Write the failing test**

Create `test/features/best_deal_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:zad/data/mock_data.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/product_card.dart';

import '../helpers.dart';

void main() {
  testWidgets('best deal section renders product cards with prices',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrapPage(const HomePage()));

    expect(find.text('Best Deal'), findsOneWidget);
    final first = mockProducts.first;
    expect(find.text(first.nameEn), findsOneWidget);
    expect(find.text(first.unitEn), findsOneWidget);
    expect(find.text(r'$12'), findsOneWidget);
    expect(find.text(r'$14'), findsOneWidget); // strikethrough old price
    expect(find.text('Add'), findsWidgets);
  });

  testWidgets('heart icon toggles favorite state', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrapPage(const HomePage()));

    expect(find.byIcon(Iconsax.heart5), findsNothing);
    // Scope to a ProductCard: Iconsax.heart is also the bottom-nav icon.
    final cardHeart = find.descendant(
      of: find.byType(ProductCard).first,
      matching: find.byIcon(Iconsax.heart),
    );
    await tester.tap(cardHeart, warnIfMissed: false);
    await tester.pump();
    expect(find.byIcon(Iconsax.heart5), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/features/best_deal_test.dart
```

Expected: FAIL — "Best Deal" text not found.

- [ ] **Step 3: Implement the widgets**

Create `lib/features/home/widgets/product_card.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/product.dart';

class ProductCard extends StatefulWidget {
  const ProductCard({required this.product, super.key});

  final Product product;

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _favorite = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final product = widget.product;
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 140,
                width: 160,
                decoration: BoxDecoration(
                  color: ZadColors.surface,
                  borderRadius: BorderRadius.circular(ZadRadii.tile),
                ),
                padding: const EdgeInsets.all(16),
                child: Image.asset(product.imagePath, fit: BoxFit.contain),
              ),
              PositionedDirectional(
                top: 10,
                end: 10,
                child: GestureDetector(
                  onTap: () => setState(() => _favorite = !_favorite),
                  child: Icon(
                    _favorite ? Iconsax.heart5 : Iconsax.heart,
                    size: 20,
                    color: _favorite ? Colors.redAccent : ZadColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            product.nameFor(languageCode),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: ZadColors.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            product.unitFor(languageCode),
            style: const TextStyle(fontSize: 11, color: ZadColors.muted),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                formatPrice(product.price),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ZadColors.ink,
                ),
              ),
              const SizedBox(width: 6),
              if (product.oldPrice != null)
                Text(
                  formatPrice(product.oldPrice!),
                  style: const TextStyle(
                    fontSize: 12,
                    color: ZadColors.muted,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: ZadColors.muted,
                  ),
                ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: ZadColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  l10n.add,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
```

Create `lib/features/home/widgets/best_deal_list.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../data/mock_data.dart';
import 'product_card.dart';

class BestDealList extends StatelessWidget {
  const BestDealList({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 244,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
            horizontal: ZadSpacing.screenPadding),
        itemCount: mockProducts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) =>
            ProductCard(product: mockProducts[index]),
      ),
    );
  }
}
```

Modify `lib/features/home/home_page.dart` — add two imports:

```dart
import 'widgets/best_deal_list.dart';
```

(alphabetically first among the `widgets/` imports) and inside the `ListView`
`children`, immediately after the `PromoBanner` padding row and its following
`SizedBox(height: ZadSpacing.sectionGap)`, insert:

```dart
            Padding(
              padding: hPad,
              child: SectionHeader(title: l10n.bestDeal),
            ),
            const SizedBox(height: 12),
            const BestDealList(), // full-bleed: own start/end padding
            const SizedBox(height: 16),
```

(The `BestDealList` is intentionally NOT wrapped in `hPad` so cards scroll
edge-to-edge with a partially visible third card, as in the mockup.)

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test && $FLUTTER analyze
```

Expected: ALL tests pass, `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "feat: best-deal horizontal product cards with favorite toggle"
```

---

### Task 9: Onboarding flow (3 pages, dots, skip, FAB)

**Files:**
- Create: `lib/features/onboarding/onboarding_page.dart`,
  `lib/features/onboarding/widgets/onboarding_card.dart`,
  `lib/features/onboarding/widgets/page_dots.dart`
- Test: `test/features/onboarding_test.dart`

**Interfaces:**
- Consumes: theme tokens + `kOnboardingDoneKey` (Task 3), l10n `skip`/`onbNTitle`/`onbNBody` (Task 4), asset paths (Task 2), `shared_preferences`.
- Produces:
  - `class OnboardingPage extends StatefulWidget` — `const OnboardingPage({super.key})`; on finish/skip sets `kOnboardingDoneKey=true` and `Navigator.pushReplacementNamed(context, '/home')`
  - `class OnboardingCard extends StatelessWidget` — `const OnboardingCard({required int index, required String title, required String body, required VoidCallback onNext, super.key})`
  - `class PageDots extends StatelessWidget` — `const PageDots({required int count, required int index, super.key})`

- [ ] **Step 1: Write the failing test**

Create `test/features/onboarding_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/features/onboarding/onboarding_page.dart';

import '../helpers.dart';

Widget _app() => wrapPage(
      const OnboardingPage(),
      routes: {
        '/home': (_) => const Scaffold(body: Text('HOME_MARKER')),
      },
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('FAB advances through all 3 pages then lands home',
      (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('Buy Groceries Easily with Us'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward).last); // FAB
    await tester.pumpAndSettle();
    expect(find.text('Fresh Products Every Day'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward).last);
    await tester.pumpAndSettle();
    expect(find.text('Best Deals, Fast Delivery'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward).last);
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kOnboardingDoneKey), isTrue);
  });

  testWidgets('swiping the image area changes the page dots/text',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.fling(find.byType(PageView), const Offset(-320, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text('Fresh Products Every Day'), findsOneWidget);
  });

  testWidgets('skip persists the flag and lands home', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kOnboardingDoneKey), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/features/onboarding_test.dart
```

Expected: FAIL — `onboarding_page.dart` does not exist.

- [ ] **Step 3: Implement the widgets**

Create `lib/features/onboarding/widgets/page_dots.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

class PageDots extends StatelessWidget {
  const PageDots({required this.count, required this.index, super.key});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == index ? 20 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == index
                  ? ZadColors.primary
                  : ZadColors.muted.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
```

Create `lib/features/onboarding/widgets/onboarding_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import 'page_dots.dart';

class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    required this.index,
    required this.title,
    required this.body,
    required this.onNext,
    super.key,
  });

  final int index;
  final String title;
  final String body;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ZadRadii.sheet)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PageDots(count: 3, index: index),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: ZadColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: ZadColors.muted,
              ),
            ),
            const SizedBox(height: 24),
            Material(
              color: ZadColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onNext,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 56,
                  height: 56,
                  child:
                      Icon(Icons.arrow_forward, color: Colors.white, size: 24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

Create `lib/features/onboarding/onboarding_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/onboarding_card.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  static const _images = <String>[
    'assets/images/onboarding_delivery.png',
    'assets/images/produce_spread.png',
    'assets/images/produce_spread.png',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingDoneKey, true);
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  void _next() {
    if (_index < _images.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titles = [l10n.onb1Title, l10n.onb2Title, l10n.onb3Title];
    final bodies = [l10n.onb1Body, l10n.onb2Body, l10n.onb3Body];

    return Scaffold(
      backgroundColor: ZadColors.paleGreen,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: _finish,
                    borderRadius: BorderRadius.circular(20),
                    child: Row(
                      children: [
                        Text(
                          l10n.skip,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: ZadColors.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            color: ZadColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _controller,
              onPageChanged: (i) => setState(() => _index = i),
              itemCount: _images.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Image.asset(
                  _images[i],
                  fit: BoxFit.contain,
                  alignment: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          OnboardingCard(
            index: _index,
            title: titles[_index],
            body: bodies[_index],
            onNext: _next,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/features/onboarding_test.dart && $FLUTTER analyze
```

Expected: PASS (3 tests), `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "feat: 3-page onboarding with dots, skip, and next FAB"
```

---

### Task 10: Splash screen and route wiring

**Files:**
- Create: `lib/features/splash/splash_page.dart`
- Modify: `lib/app.dart` (replace `home:` with routes), `test/app_test.dart` (splash now boots at `/`)
- Test: `test/features/splash_test.dart`

**Interfaces:**
- Consumes: `kSplashDuration`, `kOnboardingDoneKey` (Task 3), `OnboardingPage` (Task 9), `HomePage` (Task 6), produce-spread asset (Task 2).
- Produces:
  - `class SplashPage extends StatefulWidget` — `const SplashPage({super.key})`
  - Final route table: `'/'` → SplashPage, `'/onboarding'` → OnboardingPage, `'/home'` → HomePage.

- [ ] **Step 1: Write the failing test**

Create `test/features/splash_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/features/splash/splash_page.dart';

import '../helpers.dart';

Widget _app() => wrapPage(
      const SplashPage(),
      routes: {
        '/onboarding': (_) => const Scaffold(body: Text('ONBOARDING_MARKER')),
        '/home': (_) => const Scaffold(body: Text('HOME_MARKER')),
      },
    );

void main() {
  testWidgets('shows wordmark, first launch goes to onboarding',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app());
    expect(find.text('Zad'), findsOneWidget);
    await tester.pump(kSplashDuration);
    await tester.pumpAndSettle();
    expect(find.text('ONBOARDING_MARKER'), findsOneWidget);
  });

  testWidgets('returning user goes straight home', (tester) async {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    await tester.pumpWidget(_app());
    await tester.pump(kSplashDuration);
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test test/features/splash_test.dart
```

Expected: FAIL — `splash_page.dart` does not exist.

- [ ] **Step 3: Implement splash and wire routes**

Create `lib/features/splash/splash_page.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(kSplashDuration, _navigateNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _navigateNext() async {
    var done = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      done = prefs.getBool(kOnboardingDoneKey) ?? false;
    } catch (_) {
      // Storage unavailable: showing onboarding again is benign.
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, done ? '/home' : '/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          const Center(
            child: Text(
              'Zad', // brand wordmark — intentionally not localized
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 56,
                fontWeight: FontWeight.w700,
                color: ZadColors.primary,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              'assets/images/produce_spread.png',
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
          ),
        ],
      ),
    );
  }
}
```

Modify `lib/app.dart` — replace the whole file with:

```dart
import 'package:flutter/material.dart';

import 'core/theme.dart';
import 'features/home/home_page.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/splash/splash_page.dart';
import 'l10n/app_localizations.dart';

class ZadApp extends StatelessWidget {
  const ZadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: zadTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashPage(),
        '/onboarding': (_) => const OnboardingPage(),
        '/home': (_) => const HomePage(),
      },
    );
  }
}
```

Modify `test/app_test.dart` — the first test now boots the splash (which starts a
timer), so replace the whole file with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/app.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/l10n/app_localizations.dart';

import 'helpers.dart';

void main() {
  testWidgets('ZadApp boots to splash and reaches home for returning user',
      (tester) async {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    await tester.pumpWidget(const ZadApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.supportedLocales, contains(const Locale('ar')));
    expect(app.locale, isNull); // device locale wins
    expect(find.text('Zad'), findsOneWidget);
    await tester.pump(kSplashDuration);
    await tester.pumpAndSettle();
    expect(find.text('Search'), findsOneWidget); // home search hint
  });

  testWidgets('Arabic strings resolve', (tester) async {
    await tester.pumpWidget(wrapPage(
      Builder(builder: (c) => Text(AppLocalizations.of(c).skip)),
      locale: const Locale('ar'),
    ));
    expect(find.text('تخطي'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test && $FLUTTER analyze
```

Expected: ALL tests pass, `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "feat: splash screen with first-launch routing to onboarding"
```

---

### Task 11: Arabic RTL smoke tests and final verification

**Files:**
- Test: `test/rtl_smoke_test.dart`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write the RTL smoke test (expected to pass — it is a safety net)**

Create `test/rtl_smoke_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/onboarding/onboarding_page.dart';

import 'helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home renders RTL in Arabic without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      wrapPage(const HomePage(), locale: const Locale('ar')),
    );
    expect(find.text('تسوق حسب الفئة'), findsOneWidget);
    expect(find.text('خضروات وفواكه'), findsOneWidget);
    final context = tester.element(find.byType(HomePage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding renders RTL in Arabic without overflow',
      (tester) async {
    await tester.pumpWidget(
      wrapPage(const OnboardingPage(), locale: const Locale('ar')),
    );
    expect(find.text('اشترِ مقاضيك بسهولة معنا'), findsOneWidget);
    expect(find.text('تخطي'), findsOneWidget);
    final context = tester.element(find.byType(OnboardingPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run the full suite and analyzer**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER test && $FLUTTER analyze
```

Expected: ALL tests pass, `No issues found!`
If an RTL test fails with a RenderFlex overflow, fix the offending widget by
adding `Flexible`/`Expanded` or tightening font sizes — do not skip the test.

- [ ] **Step 3: Build/run for manual visual verification**

```bash
cd /home/frappe/Flutter/zad
$FLUTTER devices
```

If a device/emulator is listed: `$FLUTTER run` and visually compare each screen
against the mockups (`1_01_splash_screen.png`, `28_02_onboarding.png`,
`69_10_home_page.png` from the zip), in English and with the device set to
Arabic. If no device is available:

```bash
$FLUTTER build apk --debug
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk` — proves a full
compile; report to the user that on-device visual verification is pending.

- [ ] **Step 4: Commit**

```bash
cd /home/frappe/Flutter/zad
git add -A
git commit -m "test: Arabic RTL smoke tests for home and onboarding"
```
