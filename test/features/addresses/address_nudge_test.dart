import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/stores/address_store.dart';
import 'package:zad/features/addresses/add_address_nudge_sheet.dart';
import 'package:zad/features/addresses/address_form_page.dart';
import 'package:zad/features/home/home_page.dart';

import '../../helpers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<AddressStore> pumpHome(
    WidgetTester tester, {
    required bool authed,
    List<Map<String, dynamic>> rows = const [],
  }) async {
    final session =
        authed ? await buildAuthedSessionStore() : buildGuestSessionStore();
    final store = AddressStore(
      repository: buildFakeAddressRepository(initialAddresses: rows),
      session: session,
    );
    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(sessionStore: session, addressStore: store),
      ),
    );
    await tester.pumpAndSettle();
    return store;
  }

  testWidgets('an authed session with no addresses gets the nudge once, skippable', (tester) async {
    final store = await pumpHome(tester, authed: true);
    // Not hydrated yet — no nudge (the store has not confirmed "zero
    // addresses" with the server).
    expect(find.byType(AddAddressNudgeSheet), findsNothing);

    // The boot hydrate (splash calls restore()) completes while home is
    // showing — the listener fires the sheet.
    await tester.runAsync(store.restore);
    await tester.pumpAndSettle();
    expect(find.byType(AddAddressNudgeSheet), findsOneWidget);
    expect(find.text('Add your delivery address'), findsOneWidget);

    // Skippable.
    await tester.tap(find.byKey(const Key('nudgeSkipButton')));
    await tester.pumpAndSettle();
    expect(find.byType(AddAddressNudgeSheet), findsNothing);

    // Once per session: a later hydrate with still-zero addresses stays
    // silent.
    await tester.runAsync(store.refresh);
    await tester.pumpAndSettle();
    expect(find.byType(AddAddressNudgeSheet), findsNothing);
  });

  testWidgets('the nudge CTA goes straight into the address form', (tester) async {
    final store = await pumpHome(tester, authed: true);
    await tester.runAsync(store.restore);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('nudgeAddAddressButton')));
    await tester.pumpAndSettle();

    expect(find.byType(AddAddressNudgeSheet), findsNothing);
    expect(find.byType(AddressFormPage), findsOneWidget);
  });

  testWidgets('no nudge when the user already has addresses', (tester) async {
    final store = await pumpHome(
      tester,
      authed: true,
      rows: const [
        {
          'name': 'ADDR-1',
          'label': 'Home',
          'address_line': 'House 12',
          'city': 'Baghdad',
          'lat': 33.31,
          'lng': 44.37,
          'is_default': 1,
        },
      ],
    );
    await tester.runAsync(store.restore);
    await tester.pumpAndSettle();

    expect(find.byType(AddAddressNudgeSheet), findsNothing);
  });

  testWidgets('no nudge for guests', (tester) async {
    final store = await pumpHome(tester, authed: false);
    await tester.runAsync(store.restore); // guest no-op
    await tester.pumpAndSettle();

    expect(find.byType(AddAddressNudgeSheet), findsNothing);
  });
}
