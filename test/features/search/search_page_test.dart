import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/search_repository.dart';
import 'package:zad/features/home/widgets/product_card.dart';
import 'package:zad/features/search/search_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(
      requestOptions: options,
      statusCode: 200,
      data: {'message': message},
    );

List<Map<String, dynamic>> _items(int start, int count) => List.generate(
  count,
  (i) => {
    'item_code': 'ITEM-${start + i}',
    'item_name': 'Item ${start + i}',
    'price_per_uom': 1000,
    'uom': 'pc',
    'in_stock': true,
  },
);

/// The real backend contract for `search.query`: `{items, page, has_more}`.
Map<String, dynamic> _page(
  int start,
  int count, {
  required int page,
  required bool hasMore,
}) => {'items': _items(start, count), 'page': page, 'has_more': hasMore};

/// Routes the `grocery.api.search.*` endpoints of a fake backend.
FakeDioHandler _searchBackend({
  Map<String, dynamic> Function(String q, int page)? onQuery,
  List<String> Function()? onRecent,
  List<Map<String, dynamic>>? trending,
}) {
  return (options) {
    if (options.path.endsWith('search.clear_recent')) {
      return _envelope(options, {'ok': true});
    }
    if (options.path.endsWith('search.recent')) {
      return _envelope(options, onRecent?.call() ?? const <String>[]);
    }
    if (options.path.endsWith('search.trending')) {
      return _envelope(options, trending ?? const <Map<String, dynamic>>[]);
    }
    if (options.path.endsWith('search.query')) {
      final data = options.data as Map;
      final result = onQuery?.call(data['q'] as String, data['page'] as int);
      return _envelope(
        options,
        result ?? {'items': <dynamic>[], 'page': 1, 'has_more': false},
      );
    }
    return _envelope(options, <dynamic>[]);
  };
}

SearchRepository _repo(
  FakeDioHandler handler, {
  List<RequestOptions>? requests,
}) {
  return SearchRepository(
    ApiClient(
      dio: buildFakeDio(handler, capturedRequests: requests),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    ),
  );
}

Widget _wrap(
  SearchRepository repo, {
  SessionStore? sessionStore,
  Map<String, WidgetBuilder> routes = const {},
}) {
  return wrapPage(
    const SearchPage(),
    routes: routes,
    providers: homeTestProviders(
      searchRepository: repo,
      sessionStore: sessionStore,
    ),
  );
}

Iterable<RequestOptions> _queryRequests(List<RequestOptions> requests) =>
    requests.where((r) => r.path.endsWith('search.query'));

void main() {
  testWidgets('rapid typing produces a single debounced query request', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final repo = _repo(
      _searchBackend(
        onQuery: (q, page) => _page(1, 2, page: 1, hasMore: false),
      ),
      requests: requests,
    );

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    // Four keystrokes in quick succession, each within the 350ms window.
    await tester.enterText(find.byType(TextField), 'm');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'mi');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'mil');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'milk');

    // Still inside the debounce window: nothing sent yet.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_queryRequests(requests), isEmpty);

    // Window elapses: exactly one request, for the final text.
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(_queryRequests(requests), hasLength(1));
    expect(_queryRequests(requests).single.data, {'q': 'milk', 'page': 1});
    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets('guest: no recent section and search.recent is never called', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final repo = _repo(
      _searchBackend(
        onRecent: () => ['milk'],
        trending: _items(1, 2),
      ),
      requests: requests,
    );
    final guest = buildGuestSessionStore();
    await guest.restore();

    await tester.pumpWidget(_wrap(repo, sessionStore: guest));
    await tester.pumpAndSettle();

    expect(find.text('Recent Searches'), findsNothing);
    expect(requests.where((r) => r.path.endsWith('search.recent')), isEmpty);
    // Trending still shows for guests.
    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets('authed: recent chips render and tapping one runs the query', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final repo = _repo(
      _searchBackend(
        onRecent: () => ['milk', 'bread'],
        onQuery: (q, page) => _page(1, 1, page: 1, hasMore: false),
      ),
      requests: requests,
    );

    await tester.pumpWidget(
      _wrap(repo, sessionStore: await buildAuthedSessionStore()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recent Searches'), findsOneWidget);
    expect(find.text('milk'), findsOneWidget);
    expect(find.text('bread'), findsOneWidget);

    await tester.tap(find.text('bread'));
    await tester.pumpAndSettle();

    expect(_queryRequests(requests).single.data, {'q': 'bread', 'page': 1});
    expect(find.text('Item 1'), findsOneWidget);
    // The chip's query text now fills the search field.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'bread',
    );
  });

  testWidgets('clear-all calls clear_recent and empties the section', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final repo = _repo(
      _searchBackend(onRecent: () => ['milk', 'bread']),
      requests: requests,
    );

    await tester.pumpWidget(
      _wrap(repo, sessionStore: await buildAuthedSessionStore()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Recent Searches'), findsOneWidget);

    await tester.tap(find.text('Clear All'));
    await tester.pumpAndSettle();

    expect(
      requests.where((r) => r.path.endsWith('search.clear_recent')),
      hasLength(1),
    );
    expect(find.text('Recent Searches'), findsNothing);
    expect(find.text('milk'), findsNothing);
    expect(find.text('bread'), findsNothing);
  });

  testWidgets('trending chips render item names and tapping one searches', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    final repo = _repo(
      _searchBackend(
        trending: [
          {'item_code': 'T-1', 'item_name': 'Honey'},
          {'item_code': 'T-2', 'item_name': 'Rice'},
        ],
        onQuery: (q, page) => _page(1, 2, page: 1, hasMore: false),
      ),
      requests: requests,
    );

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Honey'), findsOneWidget);
    expect(find.text('Rice'), findsOneWidget);
    // Chips only — trending never renders full product cards.
    expect(find.byType(ProductCard), findsNothing);

    await tester.tap(find.text('Honey'));
    await tester.pumpAndSettle();

    expect(_queryRequests(requests).single.data, {'q': 'Honey', 'page': 1});
    expect(find.text('Item 1'), findsOneWidget);
    expect(find.byType(ProductCard), findsNWidgets(2));
  });

  testWidgets('results render as ItemCards and tap opens /product', (
    tester,
  ) async {
    final repo = _repo(
      _searchBackend(onQuery: (q, page) => _page(1, 2, page: 1, hasMore: false)),
    );

    await tester.pumpWidget(
      _wrap(
        repo,
        routes: {
          '/product': (_) => const Scaffold(body: Text('product-detail')),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'milk');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(ProductCard), findsNWidgets(2));
    await tester.tap(find.text('Item 1'));
    await tester.pumpAndSettle();

    expect(find.text('product-detail'), findsOneWidget);
  });

  testWidgets('shows the empty-results state', (tester) async {
    final repo = _repo(
      _searchBackend(
        onQuery: (q, page) => {
          'items': <dynamic>[],
          'page': 1,
          'has_more': false,
        },
      ),
    );

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('No results for "zzz"'), findsOneWidget);
  });

  testWidgets('query failure shows retry which re-runs the search', (
    tester,
  ) async {
    var queryCalls = 0;
    final repo = _repo((options) {
      if (options.path.endsWith('search.query')) {
        queryCalls++;
        if (queryCalls == 1) {
          return Response(
            requestOptions: options,
            statusCode: 500,
            data: {'message': 'boom'},
          );
        }
        return _envelope(options, _page(1, 1, page: 1, hasMore: false));
      }
      return _envelope(options, <dynamic>[]);
    });

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'milk');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
  });

  testWidgets('scrolling near the bottom loads the next results page', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final requests = <RequestOptions>[];
    final repo = _repo(
      _searchBackend(
        onQuery: (q, page) => page == 1
            ? _page(1, 20, page: 1, hasMore: true)
            : _page(21, 4, page: 2, hasMore: false),
      ),
      requests: requests,
    );

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'milk');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(_queryRequests(requests), hasLength(1));
    expect(find.text('Item 21'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
    await tester.pumpAndSettle();

    expect(_queryRequests(requests), hasLength(2));
    expect(_queryRequests(requests).last.data, {'q': 'milk', 'page': 2});
    expect(find.text('Item 21'), findsOneWidget);

    // has_more=false on page 2: no further fetches.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -8000));
    await tester.pumpAndSettle();
    expect(_queryRequests(requests), hasLength(2));
  });

  testWidgets('auto-loads the next page when results underfill the viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final requests = <RequestOptions>[];
    final repo = _repo(
      _searchBackend(
        onQuery: (q, page) => page == 1
            ? _page(1, 2, page: 1, hasMore: true)
            : _page(3, 2, page: 2, hasMore: false),
      ),
      requests: requests,
    );

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'milk');
    await tester.pump(const Duration(milliseconds: 400));
    // No drag: the viewport-fill fallback must fetch page 2 on its own.
    await tester.pumpAndSettle();

    expect(_queryRequests(requests), hasLength(2));
    expect(find.text('Item 3'), findsOneWidget);
    expect(find.text('Item 4'), findsOneWidget);
  });

  testWidgets('recent list is refetched after a search completes', (
    tester,
  ) async {
    final requests = <RequestOptions>[];
    var recentCalls = 0;
    final repo = _repo(
      _searchBackend(
        onRecent: () {
          recentCalls++;
          return recentCalls == 1 ? ['old'] : ['milk', 'old'];
        },
        onQuery: (q, page) => _page(1, 1, page: 1, hasMore: false),
      ),
      requests: requests,
    );

    await tester.pumpWidget(
      _wrap(repo, sessionStore: await buildAuthedSessionStore()),
    );
    await tester.pumpAndSettle();
    expect(recentCalls, 1);

    await tester.enterText(find.byType(TextField), 'milk');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // Backend logged the search server-side — the page refetched the list.
    expect(recentCalls, 2);

    // Clearing the field returns to the idle state with the fresh list.
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Recent Searches'), findsOneWidget);
    expect(find.text('milk'), findsOneWidget);
    expect(find.text('old'), findsOneWidget);
  });
}
