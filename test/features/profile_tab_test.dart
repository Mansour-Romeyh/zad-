import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/app_config_store.dart';
import 'package:zad/core/stores/locale_store.dart';
import 'package:zad/core/stores/settings_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/features/profile/change_password_page.dart';
import 'package:zad/features/profile/profile_tab.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

/// An authed [SessionStore] backed by a fake `Dio` whose
/// `grocery.api.auth.delete_account` answers 200 — so
/// `SessionStore.deleteAccount()` succeeds and drops the store to guest
/// (mirrors `session_store_test.dart`'s `deleteAccount` coverage, but wired
/// through a real widget tree).
Future<SessionStore> _authedSessionWithWorkingDeleteAccount() async {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  await tokenStore.save(
    apiKey: 'test-key',
    apiSecret: 'test-secret',
    user: 'jane@app.local',
    fullName: 'Jane Doe',
  );
  final dio = buildFakeDio(
    (options) => Response(
      requestOptions: options,
      statusCode: 200,
      data: {
        'message': {'status': 'scheduled', 'purge_after': '2026-08-19'},
      },
    ),
  );
  final store = SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: dio, tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
  await store.restore();
  return store;
}

void main() {
  testWidgets('guest sees a login prompt', (tester) async {
    final store = buildGuestSessionStore();
    await store.restore();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store),
        routes: {
          '/auth/login': (_) => const Scaffold(body: Text('LOGIN_MARKER')),
        },
      ),
    );

    expect(find.text('Log in to view your profile'), findsOneWidget);
    expect(find.text('Hello, Jane Doe'), findsNothing);

    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('LOGIN_MARKER'), findsOneWidget);
  });

  testWidgets('authed user sees the name/phone card and the full menu', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await buildAuthedSessionStore(
        fullName: 'Jane Doe', phone: '+9647700000001');
    final configStore = AppConfigStore(
      repository: buildFakeContentRepository(
        appConfig: const {
          'terms_url': 'https://zad.micronext.net/terms',
          'privacy_url': 'https://zad.micronext.net/privacy-policy',
        },
      ),
    );
    await tester.runAsync(configStore.load);
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(
          sessionStore: store,
          appConfigStore: configStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Hello, Jane Doe'), findsOneWidget);
    expect(find.text('+9647700000001'), findsOneWidget);
    expect(find.byKey(const Key('profileMenuAddresses')), findsOneWidget);
    expect(find.byKey(const Key('profileMenuOrders')), findsOneWidget);
    expect(find.byKey(const Key('profileMenuChangePassword')), findsOneWidget);
    expect(find.byKey(const Key('profileMenuTerms')), findsOneWidget);
    expect(find.byKey(const Key('profileMenuPrivacy')), findsOneWidget);
    expect(find.byKey(const Key('profileMenuSupport')), findsOneWidget);
    expect(find.byKey(const Key('profileMenuLogout')), findsOneWidget);
  });

  testWidgets('menu navigates: addresses and orders routes', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store),
        routes: {
          '/addresses': (_) => const Scaffold(body: Text('ADDRESSES_MARKER')),
          '/orders': (_) => const Scaffold(body: Text('ORDERS_MARKER')),
        },
      ),
    );

    await tester.tap(find.byKey(const Key('profileMenuAddresses')));
    await tester.pumpAndSettle();
    expect(find.text('ADDRESSES_MARKER'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileMenuOrders')));
    await tester.pumpAndSettle();
    expect(find.text('ORDERS_MARKER'), findsOneWidget);
  });

  testWidgets('change password opens ChangePasswordPage', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store),
      ),
    );

    await tester.tap(find.byKey(const Key('profileMenuChangePassword')));
    await tester.pumpAndSettle();
    expect(find.byType(ChangePasswordPage), findsOneWidget);
  });

  testWidgets('terms tile opens the configured terms URL', (tester) async {
    final store = await buildAuthedSessionStore();
    final opener = FakeUrlOpener();
    final configStore = AppConfigStore(
      repository: buildFakeContentRepository(
        appConfig: const {
          'terms_url': 'https://zad.micronext.net/terms',
          'privacy_url': 'https://zad.micronext.net/privacy-policy',
        },
      ),
    );
    await tester.runAsync(configStore.load);
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(
          sessionStore: store,
          urlOpener: opener,
          appConfigStore: configStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileMenuTerms')));
    await tester.pumpAndSettle();
    expect(opener.opened, contains('https://zad.micronext.net/terms'));
  });

  testWidgets('terms & privacy tiles show even when no URLs are configured', (tester) async {
    final store = await buildAuthedSessionStore();
    // Config carries no terms_url / privacy_url — the tiles must still appear
    // (store compliance requires these links to always be reachable).
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profileMenuTerms')), findsOneWidget);
    expect(find.byKey(const Key('profileMenuPrivacy')), findsOneWidget);
  });

  testWidgets('terms/privacy fall back to the backend policy pages when unconfigured', (tester) async {
    final store = await buildAuthedSessionStore();
    final opener = FakeUrlOpener();
    // No configured URLs -> tiles open <backend base>/terms and
    // /privacy-policy (test ApiClient baseUrl is http://test.local).
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store, urlOpener: opener),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('profileMenuTerms')));
    await tester.pumpAndSettle();
    expect(opener.opened, contains('http://test.local/terms'));

    await tester.tap(find.byKey(const Key('profileMenuPrivacy')));
    await tester.pumpAndSettle();
    expect(opener.opened, contains('http://test.local/privacy-policy'));
  });

  testWidgets('support dialog shows the app-config phone and copies it', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final copied = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copied.add(call);
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final store = await buildAuthedSessionStore();
    final configStore = AppConfigStore(
      repository: buildFakeContentRepository(
        appConfig: const {'support_phone': '+9647700000000'},
      ),
    );
    await tester.runAsync(configStore.load);

    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(
          sessionStore: store,
          appConfigStore: configStore,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('profileMenuSupport')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supportPhoneText')), findsOneWidget);
    expect(find.text('+9647700000000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('supportCopyButton')));
    await tester.pumpAndSettle();

    expect(copied, hasLength(1));
    expect((copied.single.arguments as Map)['text'], '+9647700000000');
    expect(find.text('Phone number copied'), findsOneWidget); // SnackBar
  });

  testWidgets('support dialog Call and WhatsApp buttons launch tel: and wa.me', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = await buildAuthedSessionStore();
    final opener = FakeUrlOpener();
    final configStore = AppConfigStore(
      repository: buildFakeContentRepository(
        appConfig: const {'support_phone': '+9647700000000'},
      ),
    );
    await tester.runAsync(configStore.load);

    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(
          sessionStore: store,
          urlOpener: opener,
          appConfigStore: configStore,
        ),
      ),
    );

    // Open the support dialog and dial via the Call button — `tel:` keeps the +.
    await tester.tap(find.byKey(const Key('profileMenuSupport')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('supportCallButton')), findsOneWidget);
    expect(find.byKey(const Key('supportWhatsappButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('supportCallButton')));
    await tester.pumpAndSettle();
    expect(opener.opened, contains('tel:+9647700000000'));

    // Reopen and open WhatsApp — wa.me needs digits only (the + is stripped).
    await tester.tap(find.byKey(const Key('profileMenuSupport')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('supportWhatsappButton')));
    await tester.pumpAndSettle();
    expect(opener.opened, contains('https://wa.me/9647700000000'));
  });

  testWidgets('support dialog without a configured phone shows the unavailable notice', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store),
      ),
    );

    await tester.tap(find.byKey(const Key('profileMenuSupport')));
    await tester.pumpAndSettle();

    expect(find.text('Support contact is currently unavailable'), findsOneWidget);
    expect(find.byKey(const Key('supportCopyButton')), findsNothing);
    // No phone → no Call / WhatsApp actions either.
    expect(find.byKey(const Key('supportCallButton')), findsNothing);
    expect(find.byKey(const Key('supportWhatsappButton')), findsNothing);
  });

  testWidgets('logout asks for confirmation; cancel keeps the session', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await buildAuthedSessionStore(fullName: 'Jane Doe');
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store),
      ),
    );

    await tester.tap(find.byKey(const Key('profileMenuLogout')));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('zadDialogSecondary')));
    await tester.pumpAndSettle();
    expect(store.isAuthed, isTrue);
    expect(find.text('Hello, Jane Doe'), findsOneWidget);
  });

  testWidgets('logout confirm logs out and drops to the guest prompt', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await buildAuthedSessionStore(fullName: 'Jane Doe');
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store),
      ),
    );

    await tester.tap(find.byKey(const Key('profileMenuLogout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zadDialogPrimary')));
    await tester.pumpAndSettle();

    expect(store.isAuthed, isFalse);
    expect(find.text('Log in to view your profile'), findsOneWidget);
  });

  testWidgets('delete account: confirm gated by checkbox, then logs out', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await _authedSessionWithWorkingDeleteAccount();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('profileMenuDeleteAccount')),
    );
    await tester.tap(find.byKey(const Key('profileMenuDeleteAccount')));
    await tester.pumpAndSettle();

    // Confirm button gated until the checkbox is ticked: tapping it first
    // is a no-op — the dialog stays open and no deletion happens.
    await tester.tap(find.byKey(const Key('zadDialogPrimary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('deleteAccountCheckbox')), findsOneWidget);
    expect(store.isAuthed, isTrue);

    await tester.tap(find.byKey(const Key('deleteAccountCheckbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zadDialogPrimary')));
    await tester.pumpAndSettle();

    expect(store.isAuthed, isFalse);
    expect(
      find.text('Your account is scheduled for deletion'),
      findsOneWidget,
    ); // SnackBar
  });

  testWidgets('language dialog switches the app language and persists it',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = await buildAuthedSessionStore(
        fullName: 'Jane Doe', phone: '+9647700000001');
    final localeStore = LocaleStore();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: [
          ...homeTestProviders(sessionStore: store),
          ChangeNotifierProvider<LocaleStore>.value(value: localeStore),
        ],
      ),
    );

    expect(localeStore.locale, const Locale('ar'),
        reason: 'Arabic is the default before any explicit choice');

    await tester.ensureVisible(find.byKey(const Key('profileMenuLanguage')));
    await tester.tap(find.byKey(const Key('profileMenuLanguage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('languageOptionAr')), findsOneWidget);

    await tester.tap(find.byKey(const Key('languageOptionEn')));
    await tester.pumpAndSettle();

    expect(localeStore.locale, const Locale('en'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kLocaleCacheKey), 'en');
  });

  testWidgets('guest prompt offers the language dialog too', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = buildGuestSessionStore();
    await store.restore();
    final localeStore = LocaleStore();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: [
          ...homeTestProviders(sessionStore: store),
          ChangeNotifierProvider<LocaleStore>.value(value: localeStore),
        ],
      ),
    );

    await tester.tap(find.byKey(const Key('guestLanguageButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('languageOptionEn')));
    await tester.pumpAndSettle();

    expect(localeStore.locale, const Locale('en'));
  });

  testWidgets('order-sound switch flips SettingsStore', (tester) async {
    final settings = SettingsStore(); // defaults enabled = true
    final store = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store, settingsStore: settings),
      ),
    );
    await tester.pumpAndSettle();

    // Tap the switch itself (the tile key's center is the label, which has no
    // tap handler — only the trailing Switch flips the setting).
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('profileOrderSoundToggle')),
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();
    expect(settings.orderSoundEnabled, isFalse);
  });
}
