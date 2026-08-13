import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/category/widgets/category_products_skeleton.dart';
import 'package:zad/features/product/paged_products_view.dart';
import 'package:zad/models/paged_items.dart';
import 'package:zad/models/product.dart';

import '../../helpers.dart';

void main() {
  testWidgets('CategoryProductsSkeleton lays out a static placeholder grid', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrapPage(const Scaffold(body: CategoryProductsSkeleton())),
    );
    // No pumpAndSettle needed: the skeleton is intentionally un-animated.
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    // It never shows a spinner (that is the thing we are replacing).
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('PagedProductsView shows its skeleton while the first page loads', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A fetch that never completes keeps the view in its loading state, so the
    // provided skeleton is what renders.
    final pending = Completer<PagedItems<Product>>();
    await tester.pumpWidget(
      wrapPage(
        Scaffold(
          body: PagedProductsView(
            fetchPage: (_) => pending.future,
            emptyText: 'none',
            skeleton: const CategoryProductsSkeleton(),
          ),
        ),
        providers: homeTestProviders(),
      ),
    );
    await tester.pump();

    expect(find.byType(CategoryProductsSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
