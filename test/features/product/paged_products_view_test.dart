import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/features/product/paged_products_view.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(
      requestOptions: options,
      statusCode: 200,
      data: {'message': message},
    );

List<Map<String, dynamic>> _items(
  int start,
  int count, {
  bool inStock = true,
}) => List.generate(
  count,
  (i) => {
    'item_code': 'ITEM-${start + i}',
    'item_name': 'Item ${start + i}',
    'price_per_uom': 1000,
    'uom': 'pc',
    'in_stock': inStock,
  },
);

/// The real backend contract for paged lists: `{items, page, has_more}`.
Map<String, dynamic> _page(
  int start,
  int count, {
  required int page,
  required bool hasMore,
}) => {'items': _items(start, count), 'page': page, 'has_more': hasMore};

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

void main() {
  testWidgets('renders the first page of items', (tester) async {
    final requests = <RequestOptions>[];
    final client = ApiClient(
      dio: buildFakeDio(
        (options) => _envelope(options, _page(1, 6, page: 1, hasMore: false)),
        capturedRequests: requests,
      ),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

    await tester.pumpWidget(_wrap(CatalogRepository(client)));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
    expect(requests, hasLength(1));
    expect(requests.single.data, {
      'item_group': 'veg',
      'page': 1,
      'page_size': 20,
    });
  });

  testWidgets('shows empty state when the category has no items', (
    tester,
  ) async {
    final client = ApiClient(
      dio: buildFakeDio(
        (options) => _envelope(options, {
          'items': <dynamic>[],
          'page': 1,
          'has_more': false,
        }),
      ),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

    await tester.pumpWidget(_wrap(CatalogRepository(client)));
    await tester.pumpAndSettle();

    expect(find.text('No items in this category yet'), findsOneWidget);
  });

  testWidgets('shows a retry prompt on first-page load failure', (
    tester,
  ) async {
    var callCount = 0;
    final client = ApiClient(
      dio: buildFakeDio((options) {
        callCount++;
        if (callCount == 1) {
          return Response(
            requestOptions: options,
            statusCode: 500,
            data: {'message': 'boom'},
          );
        }
        return _envelope(options, _page(1, 3, page: 1, hasMore: false));
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

    await tester.pumpWidget(_wrap(CatalogRepository(client)));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets(
    'loads the next page on scroll and stops once has_more is false',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final requests = <RequestOptions>[];
      final client = ApiClient(
        dio: buildFakeDio((options) {
          final page = options.data is Map ? options.data['page'] as int : 1;
          if (page == 1) {
            return _envelope(options, _page(1, 20, page: 1, hasMore: true));
          }
          if (page == 2) {
            return _envelope(options, _page(21, 4, page: 2, hasMore: false));
          }
          return _envelope(options, {
            'items': <dynamic>[],
            'page': page,
            'has_more': false,
          });
        }, capturedRequests: requests),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      );

      await tester.pumpWidget(_wrap(CatalogRepository(client)));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(find.text('Item 21'), findsNothing);

      // Drag the grid to (and past) its scroll end to trigger the near-bottom
      // fetch of page 2.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
      await tester.pumpAndSettle();

      expect(requests, hasLength(2));
      expect(requests[1].data, {
        'item_group': 'veg',
        'page': 2,
        'page_size': 20,
      });
      expect(find.text('Item 21'), findsOneWidget);

      // Page 2 reported has_more=false: further scrolling must not issue a
      // third request.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
      await tester.pumpAndSettle();

      expect(requests, hasLength(2));
    },
  );

  testWidgets('has_more=false stops pagination even when the page is full', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final requests = <RequestOptions>[];
    final client = ApiClient(
      dio: buildFakeDio(
        // A complete page (20 items == page_size) whose envelope still says
        // there is nothing more — the envelope must win over any length
        // heuristic.
        (options) => _envelope(options, _page(1, 20, page: 1, hasMore: false)),
        capturedRequests: requests,
      ),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );

    await tester.pumpWidget(_wrap(CatalogRepository(client)));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
    await tester.pumpAndSettle();

    expect(requests, hasLength(1)); // no second fetch
  });

  testWidgets(
    'has_more=true fetches the next page even when the page is short',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final requests = <RequestOptions>[];
      final client = ApiClient(
        dio: buildFakeDio((options) {
          final page = options.data is Map ? options.data['page'] as int : 1;
          // A short page (6 < page_size 20) whose envelope still promises
          // more — e.g. server-side filtering thinned the page out.
          if (page == 1) {
            return _envelope(options, _page(1, 6, page: 1, hasMore: true));
          }
          return _envelope(options, _page(7, 2, page: 2, hasMore: false));
        }, capturedRequests: requests),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      );

      await tester.pumpWidget(_wrap(CatalogRepository(client)));
      await tester.pumpAndSettle();
      expect(requests, hasLength(1));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
      await tester.pumpAndSettle();

      expect(requests, hasLength(2));
      expect(requests[1].data, {
        'item_group': 'veg',
        'page': 2,
        'page_size': 20,
      });
      expect(find.text('Item 7'), findsOneWidget);
    },
  );

  testWidgets(
    'auto-loads the next page when content does not fill the viewport',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final requests = <RequestOptions>[];
      final client = ApiClient(
        dio: buildFakeDio((options) {
          final page = options.data is Map ? options.data['page'] as int : 1;
          // Page 1 renders a single grid row — far shorter than the
          // viewport, so no scroll gesture is ever possible.
          if (page == 1) {
            return _envelope(options, _page(1, 2, page: 1, hasMore: true));
          }
          return _envelope(options, _page(3, 2, page: 2, hasMore: false));
        }, capturedRequests: requests),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      );

      await tester.pumpWidget(_wrap(CatalogRepository(client)));
      // No drag at all: the post-load viewport-fill check must fetch page 2
      // on its own.
      await tester.pumpAndSettle();

      expect(requests, hasLength(2));
      expect(requests[1].data, {
        'item_group': 'veg',
        'page': 2,
        'page_size': 20,
      });
      expect(find.text('Item 1'), findsOneWidget);
      expect(find.text('Item 2'), findsOneWidget);
      expect(find.text('Item 3'), findsOneWidget);
      expect(find.text('Item 4'), findsOneWidget);
    },
  );

  testWidgets(
    'short content with has_more=false does not auto-fetch (no loop)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final requests = <RequestOptions>[];
      final client = ApiClient(
        dio: buildFakeDio(
          // One thin page and the envelope says that's everything.
          (options) => _envelope(options, _page(1, 2, page: 1, hasMore: false)),
          capturedRequests: requests,
        ),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      );

      await tester.pumpWidget(_wrap(CatalogRepository(client)));
      await tester.pumpAndSettle();
      // Extra frames: a buggy auto-load loop would fire on these.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(requests, hasLength(1));
      expect(find.text('Item 1'), findsOneWidget);
    },
  );

  testWidgets('defaults to a fixed cell extent', (
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
    // Width-independent default — never null/ratio-governed, so a narrow /
    // large-font device can't shrink the cell shorter than the fixed-height
    // card.
    expect(delegate.mainAxisExtent, kPagedProductCellExtent);
  });

  testWidgets('uses a fixed mainAxisExtent when one is passed', (tester) async {
    final client = ApiClient(
      dio: buildFakeDio(
        (options) => _envelope(options, _page(1, 4, page: 1, hasMore: false)),
      ),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    // 250 + the reserved control row (kProductCardControlHeight + gap) so the
    // taller card fits — mirrors the real fixed-height callers (category
    // browser, skeleton).
    const extent = 250 + kProductCardControlHeight + kProductCardControlGap;
    await tester.pumpWidget(
      _wrap(CatalogRepository(client), mainAxisExtent: extent),
    );
    await tester.pumpAndSettle();

    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 2);
    expect(delegate.mainAxisExtent, extent);
  });
}
