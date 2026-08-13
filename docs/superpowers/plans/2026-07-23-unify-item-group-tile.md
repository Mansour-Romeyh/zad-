# Unify Item Group Tile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the Item Group image identically in the Home category grid and the category browser's side rail by extracting one shared rounded-square tile widget.

**Architecture:** Add a presentational `CategoryTile` widget (rounded-square, radius `ZadRadii.tile`, image *contained*, `Iconsax.category` placeholder). The Home grid uses it with a grey `surface` fill (unchanged look). The side rail replaces its circular avatar with the same tile on a white fill so it reads against the rail's grey panel; the rail keeps its pale-green selected pill, green border, bold label, press-scale, keyed tiles, and RTL behaviour.

**Tech Stack:** Flutter (Dart), `flutter_test` widget tests. Flutter binary: `~/.flutter-sdk/bin/flutter`.

## Global Constraints

- Flutter binary is not on PATH — run it as `~/.flutter-sdk/bin/flutter`.
- Design tokens come from `lib/core/theme.dart` (`ZadColors`) and `lib/core/constants.dart` (`ZadRadii.tile` = 14). Never hardcode hex/radius literals that a token already covers.
- Images render through `RemoteImage` (`lib/core/widgets/remote_image.dart`); its `placeholder` shows on null/empty/failed loads. Default `fit` is `BoxFit.contain`.
- The rail test invariant must keep passing unchanged: exactly one `Container` whose decoration color is `ZadColors.paleGreen` (#EFF9F0). Therefore `CategoryTile` MUST use `DecoratedBox` (NOT `Container`/`AnimatedContainer`), so a pale-green tile fill can never be miscounted as the selected pill.
- Directionality: the rail is used in both `en` and `ar`; do not introduce hardcoded left/right.
- The machine has 15GB RAM — do not launch heavy Gradle/Android builds; widget tests only.

---

### Task 1: `CategoryTile` shared widget

**Files:**
- Create: `lib/features/category/widgets/category_tile.dart`
- Test: `test/features/category/category_tile_test.dart`

**Interfaces:**
- Consumes: `RemoteImage` (`lib/core/widgets/remote_image.dart`), `ZadColors` (`lib/core/theme.dart`), `ZadRadii` (`lib/core/constants.dart`), `Iconsax` (`package:iconsax/iconsax.dart`).
- Produces: `CategoryTile({required String? imageUrl, Color fillColor = ZadColors.surface, Color? borderColor, double borderWidth = 1, EdgeInsets padding = const EdgeInsets.all(10), Key? key})` — a rounded-square `DecoratedBox` containing a padded, contained `RemoteImage` with an `Iconsax.category` placeholder. Callers wrap it in their own sizing (e.g. `AspectRatio`).

- [ ] **Step 1: Write the failing test**

Create `test/features/category/category_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:zad/features/category/widgets/category_tile.dart';

import '../../helpers.dart';

/// The tile's root DecoratedBox (CategoryTile builds a DecoratedBox as its
/// root), scoped to the CategoryTile subtree so no ancestor box is matched.
DecoratedBox _decoratedTile(WidgetTester tester) => tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(CategoryTile),
        matching: find.byType(DecoratedBox),
      ),
    );

void main() {
  testWidgets('shows the placeholder icon when imageUrl is null', (tester) async {
    await tester.pumpWidget(
      wrapPage(const Scaffold(body: CategoryTile(imageUrl: null))),
    );

    expect(find.byIcon(Iconsax.category), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows the placeholder icon when imageUrl is empty', (tester) async {
    await tester.pumpWidget(
      wrapPage(const Scaffold(body: CategoryTile(imageUrl: ''))),
    );

    expect(find.byIcon(Iconsax.category), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('builds an Image when imageUrl is provided', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: CategoryTile(imageUrl: 'https://example.test/x.png')),
      ),
    );

    // The Image widget is built (its network load fails harmlessly in tests).
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('applies the given fill color and border', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(
          body: CategoryTile(
            imageUrl: null,
            fillColor: Color(0xFFFFFFFF),
            borderColor: Color(0xFF5AC268),
            borderWidth: 1.5,
          ),
        ),
      ),
    );

    final decoration = _decoratedTile(tester).decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFFFFFFF));
    expect(decoration.border, isNotNull);
    expect((decoration.border as Border).top.color, const Color(0xFF5AC268));
    expect((decoration.border as Border).top.width, 1.5);
  });

  testWidgets('has no border by default', (tester) async {
    await tester.pumpWidget(
      wrapPage(const Scaffold(body: CategoryTile(imageUrl: null))),
    );

    final decoration = _decoratedTile(tester).decoration as BoxDecoration;
    expect(decoration.border, isNull);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `~/.flutter-sdk/bin/flutter test test/features/category/category_tile_test.dart`
Expected: FAIL — compile error, `category_tile.dart` / `CategoryTile` does not exist.

- [ ] **Step 3: Write the widget**

Create `lib/features/category/widgets/category_tile.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/remote_image.dart';

/// The shared Item Group image container: a rounded-square tile (radius
/// [ZadRadii.tile]) holding the group image *contained* with [padding], and an
/// [Iconsax.category] placeholder when the image is missing or fails to load.
/// Used by both the Home category grid and the category browser's side rail so
/// the same Item Group renders identically in both. Purely presentational —
/// each caller supplies the [fillColor]/[borderColor] that contrast with its
/// own background, and owns its own sizing (e.g. an [AspectRatio]) and any
/// press/selection animation.
///
/// Deliberately a [DecoratedBox], not a [Container]/[AnimatedContainer]: the
/// rail test asserts exactly one pale-green [Container] (its selected pill), so
/// a pale-green tile fill must never register as a `Container`.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    required this.imageUrl,
    this.fillColor = ZadColors.surface,
    this.borderColor,
    this.borderWidth = 1,
    this.padding = const EdgeInsets.all(10),
    super.key,
  });

  final String? imageUrl;
  final Color fillColor;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      child: Padding(
        padding: padding,
        child: RemoteImage(
          url: imageUrl,
          placeholder: const Icon(Iconsax.category, color: ZadColors.muted),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `~/.flutter-sdk/bin/flutter test test/features/category/category_tile_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/category/widgets/category_tile.dart test/features/category/category_tile_test.dart
git commit -m "feat(category): add shared CategoryTile for Item Group image"
```

---

### Task 2: Home grid uses `CategoryTile`

**Files:**
- Modify: `lib/features/home/widgets/category_grid.dart`
- Test (regression, no change): `test/features/home_category_nav_test.dart`, `test/features/home_content_test.dart`

**Interfaces:**
- Consumes: `CategoryTile` from Task 1.
- Produces: no API change — `CategoryGrid` still renders a 4-column grid of tapped tiles that navigate to `/categories`.

- [ ] **Step 1: Establish the green baseline**

Run: `~/.flutter-sdk/bin/flutter test test/features/home_category_nav_test.dart test/features/home_content_test.dart`
Expected: PASS (baseline before refactor).

- [ ] **Step 2: Swap the inline square for `CategoryTile`**

In `lib/features/home/widgets/category_grid.dart`, replace the `AspectRatio` → `Container` → `RemoteImage` block (lines ~40-56) with:

```dart
              AspectRatio(
                aspectRatio: 1,
                child: CategoryTile(imageUrl: category.imageUrl),
              ),
```

`CategoryTile`'s defaults (`fillColor: ZadColors.surface`, `padding: EdgeInsets.all(10)`, contained image, `Iconsax.category` placeholder) reproduce the current look exactly.

- [ ] **Step 3: Fix imports**

Update the import block at the top of `lib/features/home/widgets/category_grid.dart` to:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/category.dart';
import '../../category/category_browser_page.dart';
import '../../category/widgets/category_tile.dart';
```

(Removes the now-unused `package:iconsax/iconsax.dart`, `../../../core/constants.dart`, and `../../../core/widgets/remote_image.dart`. `../../../core/theme.dart` stays — the label still uses `ZadColors.ink`.)

- [ ] **Step 4: Run the analyzer for this file**

Run: `~/.flutter-sdk/bin/flutter analyze lib/features/home/widgets/category_grid.dart`
Expected: No issues (no unused-import warnings).

- [ ] **Step 5: Run the regression tests**

Run: `~/.flutter-sdk/bin/flutter test test/features/home_category_nav_test.dart test/features/home_content_test.dart`
Expected: PASS — the grid still renders tiles and tapping a label navigates to `/categories`.

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/widgets/category_grid.dart
git commit -m "refactor(home): render category grid via shared CategoryTile"
```

---

### Task 3: Side rail uses `CategoryTile`

**Files:**
- Modify: `lib/features/category/widgets/category_rail.dart`
- Test (regression, no change): `test/features/category/category_rail_test.dart`

**Interfaces:**
- Consumes: `CategoryTile` from Task 1.
- Produces: no API change — `CategoryRail({categories, selectedId, onSelect})` unchanged; each entry keeps its `ValueKey('railTile-<id>')` and pale-green selected pill.

- [ ] **Step 1: Establish the green baseline**

Run: `~/.flutter-sdk/bin/flutter test test/features/category/category_rail_test.dart`
Expected: PASS (baseline before refactor).

- [ ] **Step 2: Replace the circular avatar with `CategoryTile`**

In `lib/features/category/widgets/category_rail.dart`, inside `_RailTileState.build`, replace the selected-avatar block — the outer `AnimatedScale(scale: selected ? 1.06 : 1.0, ...)` down through its `ClipOval` → `AspectRatio` → `RemoteImage` child (the first child of the `Column`) — with:

```dart
              AspectRatio(
                aspectRatio: 1,
                child: CategoryTile(
                  imageUrl: widget.category.imageUrl,
                  fillColor: ZadColors.white,
                  borderColor: selected
                      ? ZadColors.primary
                      : ZadColors.muted.withValues(alpha: 0.2),
                  borderWidth: selected ? 1.5 : 1,
                  padding: const EdgeInsets.all(8),
                ),
              ),
```

Notes for the implementer:
- The tile fill stays **white** in both states so the Item Group image reads clearly; selection is carried by the border (`primary` green when selected) plus the existing pale-green pill and bold label. This refines the spec's "paleGreen tile fill" — white keeps the product image legible and avoids a second pale-green surface.
- Keep everything else in the method as-is: the outer `GestureDetector` with press handlers, the `AnimatedScale(scale: _pressed ? 0.96 : 1.0, ...)`, the pill `AnimatedContainer` (`color: selected ? ZadColors.paleGreen : Colors.transparent`, `borderRadius: BorderRadius.circular(18)`), the `SizedBox(height: 8)`, and the `AnimatedDefaultTextStyle` label.
- The selected-avatar `scale: 1.06` enlargement and the circular ring `AnimatedContainer`/`ClipOval` are removed with the block above.

- [ ] **Step 3: Fix imports**

Update the import block at the top of `lib/features/category/widgets/category_rail.dart` to:

```dart
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/category.dart';
import 'category_tile.dart';
```

(Removes the now-unused `package:iconsax/iconsax.dart` and `../../../core/widgets/remote_image.dart`; both moved into `CategoryTile`. `../../../core/theme.dart` stays — the pill, border, and label still use `ZadColors`.)

- [ ] **Step 4: Run the analyzer for this file**

Run: `~/.flutter-sdk/bin/flutter analyze lib/features/category/widgets/category_rail.dart`
Expected: No issues (no unused-import warnings).

- [ ] **Step 5: Run the rail regression test**

Run: `~/.flutter-sdk/bin/flutter test test/features/category/category_rail_test.dart`
Expected: PASS — a keyed tile per category, taps report the id, and exactly one pale-green `Container` (the pill) remains. The white `CategoryTile` fill is a `DecoratedBox`, so it is not counted.

- [ ] **Step 6: Full suite + analyze**

Run: `~/.flutter-sdk/bin/flutter test`
Expected: PASS (whole suite green).

Run: `~/.flutter-sdk/bin/flutter analyze`
Expected: No new issues.

- [ ] **Step 7: Commit**

```bash
git add lib/features/category/widgets/category_rail.dart
git commit -m "refactor(category): unify rail Item Group tile with home via CategoryTile"
```

---

## Verification (manual, after all tasks)

Per the `verify` skill, drive the real UI once the suite is green: launch the app,
open Home (category grid shows rounded-square tiles), tap a category to open the
"Shop By Category" browser, and confirm the side-rail entries now show the same
rounded-square tile (not circles), with the selected entry highlighted by the
pale-green pill + green border. Check both `en` and `ar` (rail flips to the end
edge in Arabic). Capture a screenshot for the PR.
