import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/app.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/l10n/app_localizations.dart';

import 'helpers.dart';

// `ZadApp` wires the real `TokenStore` (over `flutter_secure_storage`), so
// booting the full app in a widget test touches its platform channel. There
// is no real platform plugin registered under `flutter test`, so without a
// mock handler the very first `read()` call would hang forever (not throw —
// verified empirically) instead of resolving to "nothing saved". Mock it to
// behave like a fresh install with no saved session.
const _secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      switch (call.method) {
        case 'read':
          return null;
        case 'readAll':
          return <String, String>{};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  testWidgets('ZadApp boots to splash and reaches home for returning user',
      (tester) async {
    SharedPreferences.setMockInitialValues({kOnboardingDoneKey: true});
    await tester.pumpWidget(const ZadApp());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.supportedLocales, contains(const Locale('ar')));
    // Arabic-first market: the app boots in Arabic regardless of the device
    // language; an explicit profile → language choice overrides it.
    expect(app.locale, const Locale('ar'));
    expect(
      app.routes!.keys,
      containsAll(
        ['/auth/login', '/auth/register', '/auth/reset', '/categories', '/best-deals'],
      ),
    );
    // Bundled full-screen splash artwork (no backend config override).
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == 'assets/images/splash.jpg',
      ),
      findsOneWidget,
    );
    await tester.pump(kSplashDuration);
    await tester.pumpAndSettle();
    expect(find.text('ابحث'), findsOneWidget); // home search hint

    final context = tester.element(find.byType(MaterialApp));
    expect(context.read<SessionStore>().status, SessionStatus.guest);
  });

  testWidgets('Arabic strings resolve', (tester) async {
    await tester.pumpWidget(wrapPage(
      Builder(builder: (c) => Text(AppLocalizations.of(c).skip)),
      locale: const Locale('ar'),
    ));
    expect(find.text('تخطي'), findsOneWidget);
  });
}
