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

// The shelf as it lives on the home screen: inside a vertical ListView, so the
// page owns the vertical scroll and the shelf owns its own horizontal one.
Widget _page(int count) => wrapPage(
  Scaffold(
    body: ListView(
      children: [CategoryGrid(categories: List.generate(count, _cat))],
    ),
  ),
);

// Pin the viewport to a 350dp-wide phone (390dp minus the home screen's
// horizontal padding) so column sizing is deterministic, and tall enough that
// the three-row shelf lays out without the page needing to scroll.
Future<void> _pinViewport(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(350, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

// The shelf's own (horizontal) ListView, scoped under CategoryGrid so the
// enclosing page ListView (an ancestor) is never matched.
ListView _shelf(WidgetTester tester) => tester.widget<ListView>(
  find.descendant(of: find.byType(CategoryGrid), matching: find.byType(ListView)),
);

void main() {
  testWidgets('nine groups fill three rows and three columns without scrolling',
      (tester) async {
    await _pinViewport(tester);
    await tester.pumpWidget(_page(9));
    await tester.pumpAndSettle();

    for (var i = 0; i < 9; i++) {
      expect(find.text('Category $i'), findsOneWidget);
    }

    // The nine tiles occupy exactly three rows (three distinct top edges).
    final rows = {
      for (var i = 0; i < 9; i++)
        tester.getTopLeft(find.text('Category $i')).dy.roundToDouble(),
    };
    expect(rows.length, 3);

    // It's a horizontal shelf, and with everything in view it does not scroll.
    expect(_shelf(tester).scrollDirection, Axis.horizontal);
    expect(_shelf(tester).physics, isA<NeverScrollableScrollPhysics>());
  });

  testWidgets(
      'a tenth group adds a fourth column that scrolls sideways, never a fourth row',
      (tester) async {
    await _pinViewport(tester);
    await tester.pumpWidget(_page(10));
    await tester.pumpAndSettle();

    // Still only three rows across the first nine groups — no fourth row.
    final rows = {
      for (var i = 0; i < 9; i++)
        tester.getTopLeft(find.text('Category $i')).dy.roundToDouble(),
    };
    expect(rows.length, 3);

    // The overflow is absorbed sideways: the shelf now scrolls horizontally.
    expect(_shelf(tester).scrollDirection, Axis.horizontal);
    expect(_shelf(tester).physics, isA<BouncingScrollPhysics>());
  });
}
