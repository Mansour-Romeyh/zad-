import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/stores/settings_store.dart';
import 'package:zad/features/profile/profile_tab.dart';

import '../helpers.dart';

void main() {
  testWidgets('debug coords', (tester) async {
    final settings = SettingsStore();
    final store = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        providers: homeTestProviders(sessionStore: store, settingsStore: settings),
      ),
    );
    await tester.pumpAndSettle();
    final tileCenter = tester.getCenter(find.byKey(const Key('profileOrderSoundToggle')));
    final switchCenter = tester.getCenter(find.byType(Switch));
    // ignore: avoid_print
    print('tileCenter=$tileCenter switchCenter=$switchCenter');
  });
}
