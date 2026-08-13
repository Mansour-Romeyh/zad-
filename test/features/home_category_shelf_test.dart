import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/home/widgets/category_grid.dart';
import 'package:zad/models/category.dart';

import '../helpers.dart';

GroceryCategory _cat(int i) => GroceryCategory(
  id: 'cat-$i',
  nameEn: 'Category $i',
  nameAr: 'Category $i',
  imagePath: '',
  name: 'cat-$i',
);

// Pins the shelf to a fixed width so column sizing is deterministic: 350dp is
// a 390dp phone minus the home screen's horizontal padding.
Widget _shelf(int count) => wrapPage(
  Scaffold(
    body: Center(
      child: SizedBox(
        width: 350,
        child: CategoryGrid(categories: List.generate(count, _cat)),
      ),
    ),
  ),
);

void main() {
  testWidgets('eight groups fill the row in two rows without scrolling', (
    tester,
  ) async {
    await tester.pumpWidget(_shelf(8));
    await tester.pumpAndSettle();

    for (var i = 0; i < 8; i++) {
      expect(find.text('Category $i'), findsOneWidget);
    }

    // The eight tiles occupy exactly two rows (two distinct top edges).
    final rows = {
      for (var i = 0; i < 8; i++)
        tester.getTopLeft(find.text('Category $i')).dy.roundToDouble(),
    };
    expect(rows.length, 2);

    // Nothing to reveal, so the shelf does not scroll.
    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable));
    expect(scrollable.physics, isA<NeverScrollableScrollPhysics>());
  });

  testWidgets('a ninth group peeks in and scrolls sideways, never a third row', (
    tester,
  ) async {
    await tester.pumpWidget(_shelf(9));
    await tester.pumpAndSettle();

    // Still only two rows across the first eight groups — no third row.
    final rows = {
      for (var i = 0; i < 8; i++)
        tester.getTopLeft(find.text('Category $i')).dy.roundToDouble(),
    };
    expect(rows.length, 2);

    // The shelf now scrolls horizontally...
    final scrollableFinder = find.byType(Scrollable);
    final scrollable = tester.widget<Scrollable>(scrollableFinder);
    expect(scrollable.axisDirection, AxisDirection.right);

    // ...and the ninth group is already built (peeking at the edge) and fully
    // reachable by a sideways drag.
    expect(find.text('Category 8'), findsOneWidget);
    await tester.drag(scrollableFinder, const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('Category 8'), findsOneWidget);
  });
}
