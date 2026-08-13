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
    // The products pane animates group switches rather than swapping hard.
    expect(find.byType(AnimatedSwitcher), findsOneWidget);
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
