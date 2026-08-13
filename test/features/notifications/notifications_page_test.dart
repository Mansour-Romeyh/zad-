import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/notifications_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/features/notifications/notifications_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

Map<String, dynamic> _notification(
  String name, {
  String? title,
  String body = '',
  bool read = false,
}) =>
    {
      'name': name,
      'title': title ?? 'Notification $name',
      'body': body,
      'read': read,
      'creation': '2026-07-13 10:30:00.000000',
    };

void main() {
  testWidgets('renders read and unread rows; unread carries the dot', (tester) async {
    final session = await buildAuthedSessionStore();
    final repo = buildFakeNotificationsRepository(
      unread: 1,
      overrides: (options) {
        if (!options.path.endsWith('notifications.list')) return null;
        return _envelope(options, {
          'items': [
            _notification('NL-2',
                title: 'تم تعديل طلبك', body: '<p>الطماطم: 1 → 0.5</p>'),
            _notification('NL-1', title: 'تم استلام طلبك', read: true),
          ],
          'page': 1,
          'has_more': false,
        });
      },
    );
    await tester.pumpWidget(
      wrapPage(
        const NotificationsPage(),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تم تعديل طلبك'), findsOneWidget);
    expect(find.text('الطماطم: 1 → 0.5'), findsOneWidget); // html stripped
    expect(find.text('تم استلام طلبك'), findsOneWidget);
    expect(find.byKey(const Key('unreadDot-NL-2')), findsOneWidget);
    expect(find.byKey(const Key('unreadDot-NL-1')), findsNothing);
  });

  testWidgets('tapping an unread row posts mark_read, flips the row and decrements the badge', (tester) async {
    final session = await buildAuthedSessionStore();
    final requests = <RequestOptions>[];
    final repo = buildFakeNotificationsRepository(
      unread: 2,
      capturedRequests: requests,
      overrides: (options) {
        if (!options.path.endsWith('notifications.list')) return null;
        return _envelope(options, {
          'items': [
            _notification('NL-2'),
            _notification('NL-1', read: true),
          ],
          'page': 1,
          'has_more': false,
        });
      },
    );
    final store = NotificationsStore(repository: repo, session: session);
    await tester.runAsync(store.restore);
    expect(store.unreadCount, 2);

    await tester.pumpWidget(
      wrapPage(
        const NotificationsPage(),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsRepository: repo,
          notificationsStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-NL-2')));
    await tester.pumpAndSettle();

    expect(
      requests.where((r) => r.path.endsWith('notifications.mark_read')).single.data,
      {'name': 'NL-2'},
    );
    expect(find.byKey(const Key('unreadDot-NL-2')), findsNothing); // row read
    expect(store.unreadCount, 1); // badge decremented

    // Tapping an already-read row is a no-op.
    await tester.tap(find.byKey(const Key('notification-NL-1')));
    await tester.pumpAndSettle();
    expect(
      requests.where((r) => r.path.endsWith('notifications.mark_read')),
      hasLength(1),
    );
  });

  testWidgets('a failed mark_read rolls the row back', (tester) async {
    final session = await buildAuthedSessionStore();
    final repo = buildFakeNotificationsRepository(
      unread: 1,
      overrides: (options) {
        if (options.path.endsWith('notifications.mark_read')) {
          return Response(
            requestOptions: options,
            statusCode: 500,
            data: {'message': 'boom'},
          );
        }
        if (!options.path.endsWith('notifications.list')) return null;
        return _envelope(options, {
          'items': [_notification('NL-2')],
          'page': 1,
          'has_more': false,
        });
      },
    );
    final store = NotificationsStore(repository: repo, session: session);
    await tester.runAsync(store.restore);

    await tester.pumpWidget(
      wrapPage(
        const NotificationsPage(),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsRepository: repo,
          notificationsStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notification-NL-2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('unreadDot-NL-2')), findsOneWidget); // rolled back
    expect(store.unreadCount, 1); // badge untouched
  });

  testWidgets('an underfilled first page auto-loads page 2 (envelope-driven)', (tester) async {
    final session = await buildAuthedSessionStore();
    final requests = <RequestOptions>[];
    final repo = buildFakeNotificationsRepository(
      capturedRequests: requests,
      overrides: (options) {
        if (!options.path.endsWith('notifications.list')) return null;
        final page = options.queryParameters['page'] as int? ?? 1;
        if (page == 1) {
          return _envelope(options, {
            'items': [_notification('NL-2')],
            'page': 1,
            'has_more': true,
          });
        }
        return _envelope(options, {
          'items': [_notification('NL-1', read: true)],
          'page': 2,
          'has_more': false,
        });
      },
    );
    await tester.pumpWidget(
      wrapPage(
        const NotificationsPage(),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      requests.where((r) => r.path.endsWith('notifications.list')),
      hasLength(2),
      reason: 'has_more=true with an unscrollable list must auto-load page 2',
    );
    expect(find.text('Notification NL-2'), findsOneWidget);
    expect(find.text('Notification NL-1'), findsOneWidget);
  });

  testWidgets(
      'a failed underfilled auto-load shows a retry button that recovers',
      (tester) async {
    final session = await buildAuthedSessionStore();
    var page2Calls = 0;
    final repo = buildFakeNotificationsRepository(
      overrides: (options) {
        if (!options.path.endsWith('notifications.list')) return null;
        final page = options.queryParameters['page'] as int? ?? 1;
        if (page == 1) {
          return _envelope(options, {
            'items': [_notification('NL-2')],
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
          'items': [_notification('NL-1', read: true)],
          'page': 2,
          'has_more': false,
        });
      },
    );
    await tester.pumpWidget(
      wrapPage(
        const NotificationsPage(),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The auto-load failed and the list cannot scroll — the tail slot
    // offers a retry instead of stranding the feed. Rows stay visible.
    expect(find.text('Notification NL-2'), findsOneWidget);
    expect(find.byKey(const Key('loadMoreRetryButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('loadMoreRetryButton')));
    await tester.pumpAndSettle();

    expect(find.text('Notification NL-1'), findsOneWidget);
    expect(find.byKey(const Key('loadMoreRetryButton')), findsNothing);
  });

  testWidgets('empty feed shows the empty state', (tester) async {
    final session = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const NotificationsPage(),
        providers: homeTestProviders(sessionStore: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No notifications yet'), findsOneWidget);
  });

  testWidgets('a failed first page shows retry, which recovers', (tester) async {
    final session = await buildAuthedSessionStore();
    var fail = true;
    final repo = buildFakeNotificationsRepository(
      overrides: (options) {
        if (!options.path.endsWith('notifications.list')) return null;
        if (fail) {
          return Response(
            requestOptions: options,
            statusCode: 500,
            data: {'message': 'boom'},
          );
        }
        return _envelope(options, {
          'items': [_notification('NL-1')],
          'page': 1,
          'has_more': false,
        });
      },
    );
    await tester.pumpWidget(
      wrapPage(
        const NotificationsPage(),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Notification NL-1'), findsOneWidget);
  });

  testWidgets('guest deep link gets the login prompt and makes zero calls', (tester) async {
    final requests = <RequestOptions>[];
    final repo = buildFakeNotificationsRepository(capturedRequests: requests);
    await tester.pumpWidget(
      wrapPage(
        const NotificationsPage(),
        providers: homeTestProviders(notificationsRepository: repo),
        routes: {
          '/auth/login': (_) => const Scaffold(body: Text('LOGIN_MARKER')),
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log in to continue'), findsOneWidget);
    expect(requests, isEmpty);

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('LOGIN_MARKER'), findsOneWidget);
  });

  testWidgets('logging in while the page is open loads the first page (no stranded skeleton)', (tester) async {
    final requests = <RequestOptions>[];
    final repo = buildFakeNotificationsRepository(
      capturedRequests: requests,
      overrides: (options) => options.path.endsWith('notifications.list')
          ? _envelope(options, {
              'items': [
                {
                  'name': 'NOTIF-1',
                  'title': 'وصل طلبك',
                  'body': 'تم استلام طلبك',
                  'read': 0,
                  'creation': '2026-07-13 10:00:00',
                }
              ],
              'page': 1,
              'has_more': false,
            })
          : null,
    );
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
        const NotificationsPage(),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Log in to continue'), findsOneWidget);

    await tester.runAsync(() => session.login(phone: '+9647701234567', password: 'p@ss'));
    await tester.pumpAndSettle();

    expect(requests.where((r) => r.path.endsWith('notifications.list')), hasLength(1),
        reason: 'the guest→authed transition must trigger the first-page load');
    expect(find.text('وصل طلبك'), findsOneWidget);
  });
}
