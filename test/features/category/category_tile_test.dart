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
