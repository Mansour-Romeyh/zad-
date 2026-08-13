import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/address_store.dart';
import 'package:zad/core/stores/app_config_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/core/stores/notifications_store.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/splash/maintenance_page.dart';
import 'package:zad/features/splash/splash_page.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Widget _app(
  SessionStore store, {
  ContentRepository? contentRepository,
  AppConfigStore? appConfigStore,
}) {
  final configStore = appConfigStore ??
      AppConfigStore(
        repository: contentRepository ?? buildFakeContentRepository(),
      );
  return wrapPage(
    const SplashPage(),
    providers: [
      ChangeNotifierProvider<SessionStore>.value(value: store),
      ChangeNotifierProvider<CartStore>.value(
        value: CartStore(repository: buildFakeCartRepository(), session: store),
      ),
      ChangeNotifierProvider<FavouritesStore>.value(
        value: FavouritesStore(repository: buildFakeWishlistRepository(), session: store),
      ),
      ChangeNotifierProvider<AddressStore>.value(
        value: AddressStore(repository: buildFakeAddressRepository(), session: store),
      ),
      ChangeNotifierProvider<NotificationsStore>.value(
        value: NotificationsStore(
          repository: buildFakeNotificationsRepository(),
          session: store,
        ),
      ),
      ChangeNotifierProvider<AppConfigStore>.value(value: configStore),
    ],
    routes: {
      '/onboarding': (_) => const Scaffold(body: Text('ONBOARDING_MARKER')),
      '/home': (_) => const Scaffold(body: Text('HOME_MARKER')),
      '/maintenance': (_) => const MaintenancePage(),
    },
  );
}

void main() {
  testWidgets('shows wordmark, first launch goes to onboarding',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(_app(buildGuestSessionStore()));
    expect(find.text('Zad'), findsOneWidget);
    await tester.pump(kSplashDuration);
    await tester.pumpAndSettle();
    expect(find.text('ONBOARDING_MARKER'), findsOneWidget);
  });

  testWidgets('returning user goes straight home', (tester) async {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    await tester.pumpWidget(_app(buildGuestSessionStore()));
    await tester.pump(kSplashDuration);
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
  });

  testWidgets('restores a saved session before routing home', (tester) async {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    final store = buildGuestSessionStore();
    await tester.pumpWidget(_app(store));
    expect(store.status, SessionStatus.guest); // not yet restored
    await tester.pump(kSplashDuration);
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
    expect(store.isLoading, isFalse);
  });

  testWidgets('config-driven duration and background color apply', (tester) async {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    await tester.pumpWidget(
      _app(
        buildGuestSessionStore(),
        contentRepository: buildFakeContentRepository(appConfig: const {
          'splash_bg_color': '#EFF9F0',
          'splash_duration_sec': 1, // shorter than the bundled 2.5s
          'maintenance_mode': false,
        }),
      ),
    );
    // Let load() resolve (the fake dio chain rides on zero-delay timers)
    // and the config-driven rebuild land.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFFEFF9F0));

    // The config's 1s — not the bundled 2.5s — drives the timer.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
  });

  testWidgets('an unparsable config color falls back to white', (tester) async {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    await tester.pumpWidget(
      _app(
        buildGuestSessionStore(),
        contentRepository: buildFakeContentRepository(appConfig: const {
          'splash_bg_color': 'lime-ish',
          'maintenance_mode': false,
        }),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, Colors.white);

    await tester.pump(kSplashDuration);
    await tester.pumpAndSettle();
  });

  testWidgets('a failed config fetch still boots on the bundled duration', (tester) async {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    await tester.pumpWidget(
      _app(
        buildGuestSessionStore(),
        contentRepository: buildFakeContentRepository(failConfig: true),
      ),
    );
    await tester.pump(kSplashDuration);
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
  });

  testWidgets('maintenance_mode=true blocks boot behind the maintenance screen; retry with a recovered backend continues', (tester) async {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    var maintenance = true;
    // A repository whose maintenance flag the test can flip between the
    // boot fetch and the maintenance-screen retries.
    final dio = buildFakeDio((options) {
      if (options.path.endsWith('content.get_app_config')) {
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: {
            'message': {'maintenance_mode': maintenance, 'splash_duration_sec': 1},
          },
        );
      }
      return Response(
          requestOptions: options, statusCode: 200, data: {'message': <dynamic>[]});
    });
    final store = AppConfigStore(
      repository: ContentRepository(
        ApiClient(
          dio: dio,
          tokenStore: TokenStore(storage: FakeSecureStorage()),
          baseUrl: 'http://test.local',
        ),
      ),
    );

    await tester.pumpWidget(_app(buildGuestSessionStore(), appConfigStore: store));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.text("We'll be back soon"), findsOneWidget);
    expect(find.byType(MaintenancePage), findsOneWidget);
    expect(find.text('HOME_MARKER'), findsNothing);

    // Retry while the backend still says maintenance: the gate stays up.
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.byType(MaintenancePage), findsOneWidget);

    // Backend recovers → retry re-runs the boot and reaches home.
    maintenance = false;
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 50)); // refresh → back to '/'
    await tester.pump(const Duration(milliseconds: 50)); // splash config load
    await tester.pump(const Duration(seconds: 1)); // config splash duration
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
  });
}
