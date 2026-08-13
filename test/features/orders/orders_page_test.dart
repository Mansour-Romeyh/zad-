import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/features/orders/order_detail_page.dart';
import 'package:zad/features/orders/orders_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

Map<String, dynamic> _order(String name, {String status = 'Pending Assignment'}) => {
      'name': name,
      'date': '2026-07-13',
      'status': status,
      'grand_total': 4750,
      'item_count': 2,
    };

void main() {
  testWidgets('renders order cards with number, date, count, total and chip',
      (tester) async {
    final session = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const OrdersPage(),
        providers: homeTestProviders(
          sessionStore: session,
          orderRepository: buildFakeOrderRepository(
            overrides: (options) {
              if (!options.path.endsWith('order.my_orders')) return null;
              return _envelope(options, {
                'items': [
                  _order('SAL-ORD-2026-00002', status: 'Out for Delivery'),
                  _order('SAL-ORD-2026-00001', status: 'Delivered'),
                ],
                'page': 1,
                'has_more': false,
              });
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orderCard-SAL-ORD-2026-00002')), findsOneWidget);
    expect(find.byKey(const Key('orderCard-SAL-ORD-2026-00001')), findsOneWidget);
    // Backend `2026-07-13` rendered through the locale's date format.
    expect(find.text('Jul 13, 2026'), findsNWidgets(2));
    expect(find.text('2 items'), findsNWidgets(2));
    expect(find.text('IQD 4,750'), findsNWidgets(2));
    expect(find.byKey(const Key('orderStatusChip-Out for Delivery')), findsOneWidget);
    expect(find.byKey(const Key('orderStatusChip-Delivered')), findsOneWidget);
    // Newest first — server order preserved.
    final first = tester.getTopLeft(find.byKey(const Key('orderCard-SAL-ORD-2026-00002')));
    final second = tester.getTopLeft(find.byKey(const Key('orderCard-SAL-ORD-2026-00001')));
    expect(first.dy, lessThan(second.dy));
  });

  testWidgets('auto-loads the next page while has_more and the list is short',
      (tester) async {
    final session = await buildAuthedSessionStore();
    final requests = <RequestOptions>[];
    await tester.pumpWidget(
      wrapPage(
        const OrdersPage(),
        providers: homeTestProviders(
          sessionStore: session,
          orderRepository: buildFakeOrderRepository(
            capturedRequests: requests,
            overrides: (options) {
              if (!options.path.endsWith('order.my_orders')) return null;
              final page = '${options.queryParameters['page']}';
              if (page == '1') {
                return _envelope(options, {
                  'items': [_order('SO-3'), _order('SO-2')],
                  'page': 1,
                  'has_more': true,
                });
              }
              return _envelope(options, {
                'items': [_order('SO-1')],
                'page': 2,
                'has_more': false,
              });
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orderCard-SO-3')), findsOneWidget);
    expect(find.byKey(const Key('orderCard-SO-1')), findsOneWidget);
    final pages = requests
        .where((r) => r.path.endsWith('order.my_orders'))
        .map((r) => '${r.queryParameters['page']}')
        .toList();
    expect(pages, ['1', '2']);
  });

  testWidgets(
      'a failed underfilled auto-load shows a retry button that recovers',
      (tester) async {
    final session = await buildAuthedSessionStore();
    var page2Calls = 0;
    await tester.pumpWidget(
      wrapPage(
        const OrdersPage(),
        providers: homeTestProviders(
          sessionStore: session,
          orderRepository: buildFakeOrderRepository(
            overrides: (options) {
              if (!options.path.endsWith('order.my_orders')) return null;
              final page = '${options.queryParameters['page']}';
              if (page == '1') {
                // One card + has_more: underfilled, so the dead-end guard
                // fires the page-2 fetch itself (no scroll tick exists).
                return _envelope(options, {
                  'items': [_order('SO-2')],
                  'page': 1,
                  'has_more': true,
                });
              }
              page2Calls++;
              if (page2Calls == 1) {
                return Response(
                  requestOptions: options,
                  statusCode: 500,
                  data: {'message': 'boom'},
                );
              }
              return _envelope(options, {
                'items': [_order('SO-1')],
                'page': 2,
                'has_more': false,
              });
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The auto-load failed and the list cannot scroll — without an
    // affordance this page would be stuck. Loaded cards stay visible.
    expect(find.byKey(const Key('orderCard-SO-2')), findsOneWidget);
    expect(find.byKey(const Key('loadMoreRetryButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('loadMoreRetryButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orderCard-SO-1')), findsOneWidget);
    expect(find.byKey(const Key('loadMoreRetryButton')), findsNothing);
  });

  testWidgets('empty book shows the empty state', (tester) async {
    final session = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const OrdersPage(),
        providers: homeTestProviders(sessionStore: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No orders yet'), findsOneWidget);
  });

  testWidgets('a failed first page shows retry, and retry recovers', (tester) async {
    final session = await buildAuthedSessionStore();
    var calls = 0;
    await tester.pumpWidget(
      wrapPage(
        const OrdersPage(),
        providers: homeTestProviders(
          sessionStore: session,
          orderRepository: buildFakeOrderRepository(
            overrides: (options) {
              if (!options.path.endsWith('order.my_orders')) return null;
              calls++;
              if (calls == 1) {
                return Response(
                  requestOptions: options,
                  statusCode: 500,
                  data: {'message': 'boom'},
                );
              }
              return _envelope(options, {
                'items': [_order('SO-1')],
                'page': 1,
                'has_more': false,
              });
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('orderCard-SO-1')), findsOneWidget);
  });

  testWidgets('guests get a login prompt and no my_orders call', (tester) async {
    final requests = <RequestOptions>[];
    await tester.pumpWidget(
      wrapPage(
        const OrdersPage(),
        providers: homeTestProviders(
          sessionStore: buildGuestSessionStore(),
          orderRepository: buildFakeOrderRepository(capturedRequests: requests),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log in to continue'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('logging in while the page is open loads the first page (no stranded skeleton)', (tester) async {
    final requests = <RequestOptions>[];
    final tokenStore = TokenStore(storage: FakeSecureStorage());
    final loginDio = buildFakeDio(
      (options) => _envelope(options, {
        'api_key': 'key789',
        'api_secret': 'secretabc',
        'profile': {'user': 'jane@app.local', 'full_name': 'Jane Doe'},
      }),
    );
    final session = SessionStore(
      authRepository: AuthRepository(
        ApiClient(dio: loginDio, tokenStore: tokenStore, baseUrl: 'http://test.local'),
      ),
      tokenStore: tokenStore,
    );
    await tester.pumpWidget(
      wrapPage(
        const OrdersPage(),
        providers: homeTestProviders(
          sessionStore: session,
          orderRepository: buildFakeOrderRepository(
            overrides: (options) => options.path.endsWith('order.my_orders')
                ? _envelope(options, {
                    'items': [_order('SAL-ORD-2026-00001')],
                    'page': 1,
                    'has_more': false,
                  })
                : null,
            capturedRequests: requests,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Log in to continue'), findsOneWidget);

    await tester.runAsync(() => session.login(phone: '+9647701234567', password: 'p@ss'));
    await tester.pumpAndSettle();

    expect(requests.where((r) => r.path.endsWith('order.my_orders')), hasLength(1),
        reason: 'the guest→authed transition must trigger the first-page load');
    expect(find.text('SAL-ORD-2026-00001'), findsOneWidget);
  });

  testWidgets('tapping a card opens the order detail page', (tester) async {
    final session = await buildAuthedSessionStore();
    final requests = <RequestOptions>[];
    await tester.pumpWidget(
      wrapPage(
        const OrdersPage(),
        providers: homeTestProviders(
          sessionStore: session,
          orderRepository: buildFakeOrderRepository(
            capturedRequests: requests,
            overrides: (options) {
              if (!options.path.endsWith('order.my_orders')) return null;
              return _envelope(options, {
                'items': [_order('SAL-ORD-2026-00007')],
                'page': 1,
                'has_more': false,
              });
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('orderCard-SAL-ORD-2026-00007')));
    await tester.pumpAndSettle();

    expect(find.byType(OrderDetailPage), findsOneWidget);
    final detailRequest =
        requests.where((r) => r.path.endsWith('order.detail')).single;
    expect(detailRequest.queryParameters['name'], 'SAL-ORD-2026-00007');
  });
}
