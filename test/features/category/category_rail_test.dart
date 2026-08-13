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

    // Every group renders a keyed tile.
    expect(find.byKey(const ValueKey('railTile-cat-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('railTile-cat-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('railTile-cat-3')), findsOneWidget);

    // Exactly one tile paints the pale-green selected pill; find the
    // Container whose decoration uses ZadColors.paleGreen and assert there is
    // exactly one (the redesign animates this pill, but the invariant holds).
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
