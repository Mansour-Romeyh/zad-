# In-place Category Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "Shop by Category" See-All grid (and single-category page) with a two-pane browser — a rail of every Item Group on the start side, the selected group's paged products on the other, switchable in place.

**Architecture:** A new `CategoryBrowserPage` (`/categories`) loads `get_categories`, holds the selected group id, and lays out `Row(CategoryRail, PagedProductsView)`. The products pane reuses the existing `PagedProductsView` keyed by the selected id (recreated → refetched on switch). Both the home "See All" and home category tiles route here; the old `CategoryPage`/`CategoriesPage` are retired.

**Tech Stack:** Flutter, Provider, Dio (via `CatalogRepository`), existing `AsyncSection`/`SectionState` helpers, `flutter_test` widget tests.

## Global Constraints

- Flutter SDK lives at `~/.flutter-sdk` (not on PATH). Run the toolchain as `~/.flutter-sdk/bin/flutter ...` (or `~/.flutter-sdk/bin/dart ...`). Machine has ~15 GB RAM — do not run heavy Gradle/Android builds; `flutter test` is fine.
- Colors/spacing/radii come from `ZadColors` (`lib/core/theme.dart`) and `ZadSpacing`/`ZadRadii` (`lib/core/constants.dart`) — no raw literals for themed values.
- Localized copy only via `AppLocalizations.of(context)` (keys used here already exist: `shopByCategory` → "Shop By Category", `categoriesEmpty`, `categoryItemsEmpty` → "No items in this category yet", `seeAll`, `add`, `outOfStock`, `addToFavorites`).
- Category labels resolve per-locale via `GroceryCategory.nameFor(languageCode)`; layout must be RTL-safe (use `Row` + directional widgets, not hard-coded left/right).
- Backend is unchanged: `catalog.get_categories` (flat list) and `catalog.items_by_category` (`{items, page, has_more}`, page_size 20).
- Run the full suite with `~/.flutter-sdk/bin/flutter test` and keep it green after every task.

---

### Task 1: `PagedProductsView` — optional `mainAxisExtent` + tests mount it directly

Make the shared products grid usable in the browser's narrow pane (fixed cell height) and preserve its pagination coverage by testing the widget directly (before `CategoryPage`, which currently hosts these tests, is deleted in Task 5).

**Files:**
- Modify: `lib/features/product/paged_products_view.dart`
- Rename + rewrite harness: `test/features/category/category_page_test.dart` → `test/features/product/paged_products_view_test.dart`

**Interfaces:**
- Produces: `PagedProductsView({required Future<PagedItems<Product>> Function(int) fetchPage, required String emptyText, double? mainAxisExtent, Key? key})`. When `mainAxisExtent` is non-null the grid uses it for cell height (overriding `childAspectRatio`); when null, behavior is exactly as today (`childAspectRatio: 0.62`).

- [ ] **Step 1: Migrate the pagination tests to mount `PagedProductsView` directly**

Move the file and adjust the harness so the tests exercise `PagedProductsView` instead of `CategoryPage`:

```bash
git mv test/features/category/category_page_test.dart test/features/product/paged_products_view_test.dart
```

Then edit `test/features/product/paged_products_view_test.dart`:

1. Replace the import `import 'package:zad/features/category/category_page.dart';` with `import 'package:zad/features/product/paged_products_view.dart';`.
2. Replace the whole `_wrap(...)` helper (the `Builder`+`ElevatedButton` that pushed `CategoryPage`) with the direct-mount helper below:

```dart
Widget _wrap(
  CatalogRepository repo, {
  String itemGroup = 'veg',
  double? mainAxisExtent,
}) {
  return wrapPage(
    PagedProductsView(
      fetchPage: (page) => repo.itemsByCategory(itemGroup, page: page),
      emptyText: 'No items in this category yet',
      mainAxisExtent: mainAxisExtent,
    ),
    providers: homeTestProviders(catalogRepository: repo),
  );
}
```

3. In every test body, delete the line `await tester.tap(find.text('open'));` (the widget now loads on mount, no button to tap).
4. In the first test ("shows the category label…"), remove the two app-bar-label lines — `_wrap(CatalogRepository(client), label: 'Vegetables & Fruits')` becomes `_wrap(CatalogRepository(client))`, and delete `expect(find.text('Vegetables & Fruits'), findsOneWidget);`. Rename that test to `'renders the first page of items'`. Keep the `Item 1` and `requests.single.data == {item_group: 'veg', page: 1, page_size: 20}` assertions.
5. Leave all other tests (empty state, retry on failure, scroll pagination, has_more variants, auto-load, no-loop) byte-for-byte as they are apart from the removed `tap('open')` lines — they already assert on `find.byType(CustomScrollView)`, request payloads, and item text, all of which still hold.

- [ ] **Step 2: Add the two new grid-metric tests**

Append these to `test/features/product/paged_products_view_test.dart` inside `main()`:

```dart
  testWidgets('defaults to null mainAxisExtent (aspect-ratio cells)', (
    tester,
  ) async {
    final client = ApiClient(
      dio: buildFakeDio(
        (options) => _envelope(options, _page(1, 4, page: 1, hasMore: false)),
      ),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    await tester.pumpWidget(_wrap(CatalogRepository(client)));
    await tester.pumpAndSettle();

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.mainAxisExtent, isNull);
    expect(delegate.childAspectRatio, 0.62);
  });

  testWidgets('uses a fixed mainAxisExtent when one is passed', (tester) async {
    final client = ApiClient(
      dio: buildFakeDio(
        (options) => _envelope(options, _page(1, 4, page: 1, hasMore: false)),
      ),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    await tester.pumpWidget(
      _wrap(CatalogRepository(client), mainAxisExtent: 250),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.mainAxisExtent, 250);
  });
```

- [ ] **Step 3: Run the new tests to verify they fail (param not yet added)**

Run: `~/.flutter-sdk/bin/flutter test test/features/product/paged_products_view_test.dart`
Expected: FAIL — the two new tests fail to compile / the `mainAxisExtent:` named arg does not exist on `PagedProductsView`.

- [ ] **Step 4: Add the `mainAxisExtent` param to `PagedProductsView`**

In `lib/features/product/paged_products_view.dart`, add the field to the constructor and class:

```dart
  const PagedProductsView({
    required this.fetchPage,
    required this.emptyText,
    this.mainAxisExtent,
    super.key,
  });

  /// Fetches one page of the listing (1-based).
  final Future<PagedItems<Product>> Function(int page) fetchPage;

  /// Message shown when the first page comes back empty.
  final String emptyText;

  /// Fixed cell height (px) for the 2-column grid. When null the grid sizes
  /// cells by [childAspectRatio] (full-width default); the category browser's
  /// narrow pane passes a fixed extent so cards never overflow.
  final double? mainAxisExtent;
```

Thread it into the builder call at the bottom of `build`:

```dart
      builder: (context, items) => _ProductsGrid(
        items: items,
        controller: _scrollController,
        loadingMore: _loadingMore,
        mainAxisExtent: widget.mainAxisExtent,
      ),
```

Update `_ProductsGrid` to accept and apply it (and drop the `Center` wrapper so the now-adaptive card fills the cell):

```dart
class _ProductsGrid extends StatelessWidget {
  const _ProductsGrid({
    required this.items,
    required this.controller,
    required this.loadingMore,
    required this.mainAxisExtent,
  });

  final List<Product> items;
  final ScrollController controller;
  final bool loadingMore;
  final double? mainAxisExtent;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 14,
              childAspectRatio: 0.62,
              mainAxisExtent: mainAxisExtent,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => ProductCard(product: items[index]),
              childCount: items.length,
            ),
          ),
        ),
        if (loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
      ],
    );
  }
}
```

(The `SliverGridDelegateWithFixedCrossAxisCount` is no longer `const` because `mainAxisExtent` is a runtime value — that is expected.)

- [ ] **Step 5: Run the file's tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/features/product/paged_products_view_test.dart`
Expected: PASS (all migrated pagination tests + the two new grid tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/product/paged_products_view.dart test/features/product/paged_products_view_test.dart
git rm --cached test/features/category/category_page_test.dart 2>/dev/null || true
git commit -m "feat(products): PagedProductsView mainAxisExtent param; test it directly"
```

---

### Task 2: Make `ProductCard` width-adaptive

Two cards must fit the narrow browser pane. Remove the card's fixed 160-px width so it fills its cell; keep the one horizontal-list caller sized via a wrapper. Height is unchanged, so no grid overflows.

**Files:**
- Modify: `lib/features/home/widgets/product_card.dart`
- Modify: `lib/features/home/widgets/best_deal_list.dart`
- Test: `test/features/product/product_card_width_test.dart` (create)

**Interfaces:**
- Produces: `ProductCard` now expands to its parent's width (no intrinsic 160-px width). Callers in unbounded-width contexts must constrain it (`BestDealList` wraps it in `SizedBox(width: 160)`).

- [ ] **Step 1: Write the failing test**

Create `test/features/product/product_card_width_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/home/widgets/product_card.dart';
import 'package:zad/models/product.dart';

import '../../helpers.dart';

Product _product() => const Product(
      id: 'ITEM-1',
      itemCode: 'ITEM-1',
      nameEn: 'Toor Dal',
      nameAr: 'Toor Dal',
      unitEn: '1 kg',
      unitAr: '1 kg',
      price: 10000,
      imagePath: '',
      pricePerUom: 10000,
      inStock: true,
    );

void main() {
  testWidgets('ProductCard fills the width it is given', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        Center(
          child: SizedBox(width: 120, child: ProductCard(product: _product())),
        ),
        providers: homeTestProviders(),
      ),
    );
    await tester.pumpAndSettle();

    // The card takes the full 120px it is offered (no fixed 160 clamp),
    // and renders without overflow in the narrow box.
    expect(tester.getSize(find.byType(ProductCard)).width, 120);
    expect(tester.takeException(), isNull);
  });
}
```

(The named args above match `Product`'s real constructor in
`lib/models/product.dart`: `id, nameEn, nameAr, unitEn, unitAr, price,
imagePath` are required; `itemCode, pricePerUom, inStock` are optional — no
adjustment needed.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/features/product/product_card_width_test.dart`
Expected: FAIL — the card reports width `160` (its current fixed width), not `120`.

- [ ] **Step 3: Make the card width-adaptive**

In `lib/features/home/widgets/product_card.dart`, in `build`, change the outer `SizedBox(width: 160, child: Column(...))` to just the `Column` (remove the fixed width), and change the image `Container`'s `width: 160` to `width: double.infinity`:

```dart
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openDetail(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: ZadColors.surface,
                  borderRadius: BorderRadius.circular(ZadRadii.tile),
                ),
                padding: const EdgeInsets.all(16),
                child: RemoteImage(
                  url: product.imageUrl,
                  placeholder: const Icon(
                    Iconsax.gallery,
                    color: ZadColors.muted,
                    size: 36,
                  ),
                ),
              ),
              // ...heart + out-of-stock badge unchanged...
```

Leave everything below the image (`Stack` children, name, unit, price/Add `Row`) exactly as-is.

- [ ] **Step 4: Constrain the one unbounded caller (`BestDealList`)**

In `lib/features/home/widgets/best_deal_list.dart`, wrap the card so the horizontal list keeps today's 160-px cards:

```dart
        itemBuilder: (context, index) => SizedBox(
          width: 160,
          child: ProductCard(product: products[index]),
        ),
```

- [ ] **Step 5: Run the width test + the existing card/best-deal tests**

Run: `~/.flutter-sdk/bin/flutter test test/features/product/product_card_width_test.dart test/features/best_deal_test.dart`
Expected: PASS (card is 120px wide in the box; best-deal list still renders its cards and price/heart/add assertions hold).

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/widgets/product_card.dart lib/features/home/widgets/best_deal_list.dart test/features/product/product_card_width_test.dart
git commit -m "feat(product-card): make width-adaptive; fix Best Deals list sizing"
```

---

### Task 3: `CategoryRail` widget

The left rail: a vertical, independently-scrollable list of every Item Group, with the selected one highlighted (pale-green fill + green start-edge accent bar).

**Files:**
- Create: `lib/features/category/widgets/category_rail.dart`
- Test: `test/features/category/category_rail_test.dart` (create)

**Interfaces:**
- Produces: `CategoryRail({required List<GroceryCategory> categories, required String selectedId, required ValueChanged<String> onSelect, Key? key})` with `static const double width = 96`.

- [ ] **Step 1: Write the failing test**

Create `test/features/category/category_rail_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/category/widgets/category_rail.dart';
import 'package:zad/models/category.dart';

import '../../helpers.dart';

GroceryCategory _cat(String id, String label) => GroceryCategory(
      id: id,
      nameEn: label,
      nameAr: label,
      imagePath: '',
      name: id,
      label: label,
    );

void main() {
  final categories = [
    _cat('cat-1', 'Atta'),
    _cat('cat-2', 'Rice'),
    _cat('cat-3', 'Sooji'),
  ];

  testWidgets('renders a tile per category and reports taps', (tester) async {
    String? tapped;
    await tester.pumpWidget(
      wrapPage(
        Scaffold(
          body: CategoryRail(
            categories: categories,
            selectedId: 'cat-1',
            onSelect: (id) => tapped = id,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Atta'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    expect(find.text('Sooji'), findsOneWidget);

    await tester.tap(find.text('Rice'));
    expect(tapped, 'cat-2');
  });

  testWidgets('highlights exactly the selected tile', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        Scaffold(
          body: CategoryRail(
            categories: categories,
            selectedId: 'cat-2',
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The selected tile paints a pale-green background; find the Container
    // whose decoration uses ZadColors.paleGreen and assert there is exactly
    // one.
    final highlighted = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color?.toARGB32() ==
              const Color(0xFFEFF9F0).toARGB32(),
    );
    expect(highlighted, findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/features/category/category_rail_test.dart`
Expected: FAIL — `category_rail.dart` does not exist (compile error).

- [ ] **Step 3: Implement `CategoryRail`**

Create `lib/features/category/widgets/category_rail.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/remote_image.dart';
import '../../../models/category.dart';

/// The category browser's left rail: a vertical, independently scrollable
/// list of every Item Group. The [selectedId] tile is highlighted with a
/// pale-green fill and a green start-edge accent bar; tapping any tile calls
/// [onSelect] with that group's id. Laid out with directional widgets, so in
/// Arabic it flips to the screen's right edge automatically.
class CategoryRail extends StatelessWidget {
  const CategoryRail({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    super.key,
  });

  /// Fixed rail width (px).
  static const double width = 96;

  final List<GroceryCategory> categories;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return SizedBox(
      width: width,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.id == selectedId;
          final label = category.nameFor(languageCode);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(category.id),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: selected ? ZadColors.paleGreen : Colors.transparent,
                border: BorderDirectional(
                  start: BorderSide(
                    color: selected ? ZadColors.primary : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: ZadColors.surface,
                        borderRadius: BorderRadius.circular(ZadRadii.tile),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: RemoteImage(
                        url: category.imageUrl,
                        placeholder: const Icon(
                          Iconsax.category,
                          color: ZadColors.muted,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.2,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? ZadColors.ink : ZadColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/features/category/category_rail_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/category/widgets/category_rail.dart test/features/category/category_rail_test.dart
git commit -m "feat(category): add CategoryRail widget for the browser"
```

---

### Task 4: `CategoryBrowserPage` + `CategoryBrowserArgs`

The two-pane page: load categories, hold the selection, lay out rail + keyed products.

**Files:**
- Create: `lib/features/category/category_browser_page.dart`
- Test: `test/features/category/category_browser_page_test.dart` (create)

**Interfaces:**
- Consumes: `CategoryRail` (Task 3), `PagedProductsView` + `mainAxisExtent` (Task 1), `CatalogRepository.getCategories()` / `.itemsByCategory(id, page:)`.
- Produces: `CategoryBrowserPage()` widget and `CategoryBrowserArgs({String? initialGroupId})` route-args type.

- [ ] **Step 1: Write the failing tests**

Create `test/features/category/category_browser_page_test.dart`:

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/features/category/category_browser_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

/// A fake catalog server: `get_categories` returns [categories]; every
/// `items_by_category` returns a single item whose name encodes the requested
/// `item_group`, so a test can read which category is showing.
CatalogRepository _repo({
  required List<Map<String, dynamic>> categories,
  List<RequestOptions>? captured,
}) {
  return CatalogRepository(
    ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) {
          return _envelope(options, categories);
        }
        final group = options.data is Map ? options.data['item_group'] : '?';
        return _envelope(options, {
          'items': [
            {
              'item_code': 'ITEM-$group',
              'item_name': 'Item of $group',
              'price_per_uom': 1000,
              'uom': 'pc',
              'in_stock': true,
            },
          ],
          'page': 1,
          'has_more': false,
        });
      }, capturedRequests: captured),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    ),
  );
}

const _threeCategories = [
  {'name': 'cat-1', 'label': 'Atta', 'item_count': 5},
  {'name': 'cat-2', 'label': 'Rice', 'item_count': 9},
  {'name': 'cat-3', 'label': 'Sooji', 'item_count': 2},
];

Widget _direct(CatalogRepository repo) => wrapPage(
      const CategoryBrowserPage(),
      providers: homeTestProviders(catalogRepository: repo),
    );

Widget _withArgs(CatalogRepository repo, CategoryBrowserArgs args) => wrapPage(
      Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const CategoryBrowserPage(),
              settings: RouteSettings(arguments: args),
            ),
          ),
          child: const Text('open'),
        ),
      ),
      providers: homeTestProviders(catalogRepository: repo),
    );

void main() {
  testWidgets('selects the first category and shows its products', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_direct(_repo(categories: _threeCategories)));
    await tester.pumpAndSettle();

    expect(find.text('Shop By Category'), findsOneWidget); // app bar
    expect(find.text('Atta'), findsOneWidget); // rail
    expect(find.text('Item of cat-1'), findsOneWidget); // first group's product
  });

  testWidgets('pre-selects the category from CategoryBrowserArgs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _withArgs(
        _repo(categories: _threeCategories),
        const CategoryBrowserArgs(initialGroupId: 'cat-2'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Item of cat-2'), findsOneWidget);
  });

  testWidgets('tapping a rail item swaps the products pane', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final captured = <RequestOptions>[];
    await tester.pumpWidget(
      _direct(_repo(categories: _threeCategories, captured: captured)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Item of cat-1'), findsOneWidget);

    await tester.tap(find.text('Sooji'));
    await tester.pumpAndSettle();

    expect(find.text('Item of cat-3'), findsOneWidget);
    expect(find.text('Item of cat-1'), findsNothing);
    // A fresh items_by_category request went out for the tapped group.
    expect(
      captured.any((r) => r.data is Map && r.data['item_group'] == 'cat-3'),
      isTrue,
    );
  });

  testWidgets('shows the empty state when there are no categories', (
    tester,
  ) async {
    await tester.pumpWidget(_direct(_repo(categories: const [])));
    await tester.pumpAndSettle();

    expect(find.text('No categories yet'), findsOneWidget); // l10n.categoriesEmpty
  });

  testWidgets('shows retry on a categories load failure', (tester) async {
    var calls = 0;
    final repo = CatalogRepository(
      ApiClient(
        dio: buildFakeDio((options) {
          if (options.path.endsWith('get_categories')) {
            calls++;
            if (calls == 1) {
              return Response(
                requestOptions: options,
                statusCode: 500,
                data: {'message': 'boom'},
              );
            }
            return _envelope(options, _threeCategories);
          }
          return _envelope(options, {
            'items': <dynamic>[],
            'page': 1,
            'has_more': false,
          });
        }),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      ),
    );
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_direct(repo));
    await tester.pumpAndSettle();
    expect(find.text('Atta'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Atta'), findsOneWidget);
  });
}
```

Note: the empty-state test asserts the exact English text of `l10n.categoriesEmpty`. Confirm that string in `lib/l10n/` and update the expectation to match (the design uses `l10n.categoriesEmpty`; use whatever its real English value is).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `~/.flutter-sdk/bin/flutter test test/features/category/category_browser_page_test.dart`
Expected: FAIL — `category_browser_page.dart` does not exist (compile error).

- [ ] **Step 3: Implement `CategoryBrowserPage`**

Create `lib/features/category/category_browser_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/catalog_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/section_state.dart';
import '../product/paged_products_view.dart';
import 'widgets/category_rail.dart';

/// Route arguments for `/categories`. [initialGroupId] pre-selects a rail
/// entry when the browser is opened from a specific category tile; null (the
/// "See All" entry point) selects the first category.
class CategoryBrowserArgs {
  const CategoryBrowserArgs({this.initialGroupId});

  final String? initialGroupId;
}

/// `/categories` — the "Shop By Category" browser (PRD F3): a rail of every
/// Item Group on the start side and the selected group's paged products on
/// the other. Selection is swapped in place (no navigation); the products
/// pane is a [PagedProductsView] keyed by the selected id so it reloads on
/// switch. The narrow pane passes a fixed [PagedProductsView.mainAxisExtent]
/// so its 2-column cards never overflow.
class CategoryBrowserPage extends StatefulWidget {
  const CategoryBrowserPage({super.key});

  @override
  State<CategoryBrowserPage> createState() => _CategoryBrowserPageState();
}

class _CategoryBrowserPageState extends State<CategoryBrowserPage> {
  static const double _cellHeight = 250;

  SectionState<List<GroceryCategory>> _state = const SectionState.loading();

  /// Null until the user taps a rail item; while null the selection falls back
  /// to the route arg / first category (see [_resolveSelected]).
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const SectionState.loading());
    try {
      final categories = await context.read<CatalogRepository>().getCategories();
      if (!mounted) return;
      setState(() => _state = SectionState.data(categories));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = SectionState.error(e));
    }
  }

  /// The active group: the user's tapped id if any, else the route arg's group
  /// (when present in the loaded list), else the first category.
  String _resolveSelected(List<GroceryCategory> categories) {
    final tapped = _selectedId;
    if (tapped != null) return tapped;
    final args = ModalRoute.of(context)?.settings.arguments;
    final wanted = args is CategoryBrowserArgs ? args.initialGroupId : null;
    final match = categories.where((c) => c.id == wanted);
    return match.isNotEmpty ? match.first.id : categories.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        title: Text(l10n.shopByCategory),
      ),
      body: SafeArea(
        child: AsyncSection<List<GroceryCategory>>(
          state: _state,
          skeleton: const Center(child: CircularProgressIndicator()),
          onRetry: _load,
          isEmpty: (data) => data.isEmpty,
          emptyBuilder: (context) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ZadSpacing.screenPadding),
              child: Text(
                l10n.categoriesEmpty,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ZadColors.muted, fontSize: 14),
              ),
            ),
          ),
          builder: (context, categories) {
            final selectedId = _resolveSelected(categories);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CategoryRail(
                  categories: categories,
                  selectedId: selectedId,
                  onSelect: (id) => setState(() => _selectedId = id),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: PagedProductsView(
                    key: ValueKey(selectedId),
                    fetchPage: (page) => context
                        .read<CatalogRepository>()
                        .itemsByCategory(selectedId, page: page),
                    emptyText: l10n.categoryItemsEmpty,
                    mainAxisExtent: _cellHeight,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `~/.flutter-sdk/bin/flutter test test/features/category/category_browser_page_test.dart`
Expected: PASS. If any product-pane test throws a render-overflow exception, raise `_cellHeight` (e.g. to 260) until `tester.takeException()` is null — the card must fit the fixed cell.

- [ ] **Step 5: Commit**

```bash
git add lib/features/category/category_browser_page.dart test/features/category/category_browser_page_test.dart
git commit -m "feat(category): add two-pane CategoryBrowserPage"
```

---

### Task 5: Wire routes + home; retire the old pages

Point both entry points at the browser, delete the retired pages, and fix the two tests that referenced them.

**Files:**
- Modify: `lib/app.dart` (imports + routes)
- Modify: `lib/features/home/widgets/category_grid.dart`
- Delete: `lib/features/category/category_page.dart`, `lib/features/category/categories_page.dart`
- Delete: `test/features/category/categories_page_test.dart`
- Modify: `test/rtl_smoke_test.dart`
- Create: `test/features/home_category_nav_test.dart` (home tile → browser)

**Interfaces:**
- Consumes: `CategoryBrowserPage` / `CategoryBrowserArgs` (Task 4).

- [ ] **Step 1: Repoint the routes in `lib/app.dart`**

Replace the two category route lines:

```dart
            '/category': (_) => const CategoryPage(),
            '/categories': (_) => const CategoriesPage(),
```

with a single browser route:

```dart
            '/categories': (_) => const CategoryBrowserPage(),
```

Update the imports at the top of `lib/app.dart`: remove the `category_page.dart` and `categories_page.dart` imports and add `import 'features/category/category_browser_page.dart';` (match the file's existing relative-import style).

- [ ] **Step 2: Repoint the home category tiles in `category_grid.dart`**

In `lib/features/home/widgets/category_grid.dart`, change the import
`import '../../category/category_page.dart';` to
`import '../../category/category_browser_page.dart';`, and change the tile's
`onTap` to open the browser pre-selected to that group:

```dart
          onTap: () => Navigator.pushNamed(
            context,
            '/categories',
            arguments: CategoryBrowserArgs(initialGroupId: category.id),
          ),
```

(The `label` local is no longer needed for navigation, but it is still used for
the tile's `Text` — leave that usage as-is.)

- [ ] **Step 3: Delete the retired pages and their test**

```bash
git rm lib/features/category/category_page.dart lib/features/category/categories_page.dart test/features/category/categories_page_test.dart
```

- [ ] **Step 4: Update the RTL smoke test to the browser**

In `test/rtl_smoke_test.dart`:

1. Change the import `import 'package:zad/features/category/category_page.dart';` to `import 'package:zad/features/category/category_browser_page.dart';`.
2. In the `'category page renders RTL in Arabic without overflow'` test, make the fake server also answer `get_categories`, and mount `CategoryBrowserPage`. Replace that test's `dio` handler and `pumpWidget` block with:

```dart
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) {
          return _envelope(options, [
            {'name': 'veg', 'label': 'خضار', 'item_count': 3},
          ]);
        }
        // items_by_category returns the paged envelope.
        return _envelope(options, {
          'items': [
            {
              'item_code': 'ITEM-1',
              'item_name': 'طماطم طازجة',
              'price_per_uom': 1500,
              'uom': 'كغم',
              'in_stock': true,
            },
          ],
          'page': 1,
          'has_more': false,
        });
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    await tester.pumpWidget(
      wrapPage(
        const CategoryBrowserPage(),
        locale: const Locale('ar'),
        providers: homeTestProviders(catalogRepository: CatalogRepository(client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('طماطم طازجة'), findsOneWidget);
    final context = tester.element(find.byType(CategoryBrowserPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
```

(Keep the surrounding `testWidgets(...)` wrapper, the `setSurfaceSize(390, 900)` lines, and the `_envelope` helper the file already defines.)

- [ ] **Step 5: Add a home tile → browser navigation test (new self-contained file)**

Create `test/features/home_category_nav_test.dart` (mirrors the fake/provider
pattern already used in `home_see_all_test.dart`):

```dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/home/home_page.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

ApiClient _client() => ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) {
          return _envelope(options, [
            {'name': 'cat-1', 'label': 'Fruits', 'item_count': 3},
          ]);
        }
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

void main() {
  testWidgets('tapping a home category tile opens the category browser', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = _client();
    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
        routes: {
          '/categories': (_) => const Scaffold(body: Text('BROWSER_MARKER')),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fruits')); // the category tile label
    await tester.pumpAndSettle();

    expect(find.text('BROWSER_MARKER'), findsOneWidget);
  });
}
```

The stubbed `/categories` route makes the push observable without mounting the
real browser; the test only proves a category tile lands on `/categories`.

- [ ] **Step 6: Run the whole suite**

Run: `~/.flutter-sdk/bin/flutter test`
Expected: PASS — no references to `CategoryPage`/`CategoriesPage` remain; app boots; `app_test.dart`'s route-key assertion (`containsAll([... '/categories' ...])` still holds; `home_see_all_test.dart` still lands on `/categories`.

- [ ] **Step 7: Analyze + commit**

```bash
~/.flutter-sdk/bin/flutter analyze
git add -A
git commit -m "feat(category): route See All + home tiles to the browser; retire old pages"
```

---

## Verification (after all tasks)

- [ ] `~/.flutter-sdk/bin/flutter analyze` is clean.
- [ ] `~/.flutter-sdk/bin/flutter test` is green.
- [ ] Drive the real app (use the `run` skill): open Home → tap **See All** by "Shop by Category" → the two-pane browser opens with the first category selected and its products in **2 columns**; tap other rail items and confirm the right pane swaps in place with no overflow; tap a home category tile directly and confirm the browser opens pre-selected to it. Repeat in Arabic to confirm the rail sits on the right (RTL).
