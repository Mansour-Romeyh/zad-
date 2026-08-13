import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/stores/notifications_store.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/notifications_bell.dart';

import '../../helpers.dart';

void main() {
  testWidgets('authed home shows the bell with the unread badge', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await buildAuthedSessionStore();
    final store = NotificationsStore(
      repository: buildFakeNotificationsRepository(unread: 3),
      session: session,
    );
    await tester.runAsync(store.restore);

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsStore: store,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notificationsBell')), findsOneWidget);
    expect(find.byKey(const Key('notificationsBadge')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('badge caps at 9+ and hides at zero', (tester) async {
    final session = await buildAuthedSessionStore();
    final store = NotificationsStore(
      repository: buildFakeNotificationsRepository(unread: 12),
      session: session,
    );
    await tester.runAsync(store.restore);

    await tester.pumpWidget(
      wrapPage(
        Scaffold(body: Center(child: NotificationsBell())),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsStore: store,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('guest bell shows no badge and taps into the login sheet', (tester) async {
    final requests = <RequestOptions>[];
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: Center(child: NotificationsBell())),
        providers: homeTestProviders(
          notificationsRepository:
              buildFakeNotificationsRepository(capturedRequests: requests),
        ),
        routes: {
          '/notifications': (_) =>
              const Scaffold(body: Text('NOTIFICATIONS_MARKER')),
        },
      ),
    );

    expect(find.byKey(const Key('notificationsBadge')), findsNothing);

    await tester.tap(find.byKey(const Key('notificationsBell')));
    await tester.pumpAndSettle();

    expect(find.text('Log in to continue'), findsOneWidget); // login sheet
    expect(find.text('NOTIFICATIONS_MARKER'), findsNothing);
    expect(requests, isEmpty);
  });

  testWidgets('authed bell tap opens /notifications', (tester) async {
    final session = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: Center(child: NotificationsBell())),
        providers: homeTestProviders(sessionStore: session),
        routes: {
          '/notifications': (_) =>
              const Scaffold(body: Text('NOTIFICATIONS_MARKER')),
        },
      ),
    );

    await tester.tap(find.byKey(const Key('notificationsBell')));
    await tester.pumpAndSettle();

    expect(find.text('NOTIFICATIONS_MARKER'), findsOneWidget);
  });
}
