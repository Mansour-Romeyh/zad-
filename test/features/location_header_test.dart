import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/stores/address_store.dart';
import 'package:zad/features/home/widgets/location_header.dart';

import '../helpers.dart';

const _workRow = {
  'name': 'ADDR-2',
  'label': 'Work',
  'address_line': 'Office 4, Karrada St',
  'city': 'Baghdad',
  'lat': 33.31,
  'lng': 44.37,
  'is_default': 1,
};

void main() {
  Widget page({required List providers}) => wrapPage(
        const Scaffold(body: LocationHeader()),
        routes: {
          '/addresses': (_) => const Scaffold(body: Text('ADDRESSES_PAGE')),
          '/auth/login': (_) => const Scaffold(body: Text('LOGIN_PAGE')),
        },
        providers: List.from(providers),
      );

  testWidgets('guest sees the generic placeholder; tap opens the login sheet, not the address book', (tester) async {
    await tester.pumpWidget(page(providers: homeTestProviders()));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Baghdad'), findsOneWidget);

    await tester.tap(find.byKey(const Key('locationHeaderTap')));
    await tester.pumpAndSettle();

    expect(find.text('Log in to continue'), findsOneWidget); // LoginRequiredSheet
    expect(find.text('ADDRESSES_PAGE'), findsNothing);
  });

  testWidgets('authed shows the default address and taps through to /addresses', (tester) async {
    final session = await buildAuthedSessionStore();
    final store = AddressStore(
      repository: buildFakeAddressRepository(initialAddresses: const [_workRow]),
      session: session,
    );
    await tester.runAsync(store.restore);

    await tester.pumpWidget(
      page(
        providers: homeTestProviders(sessionStore: session, addressStore: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget); // label as the title
    expect(find.text('Office 4, Karrada St, Baghdad'), findsOneWidget);

    await tester.tap(find.byKey(const Key('locationHeaderTap')));
    await tester.pumpAndSettle();

    expect(find.text('ADDRESSES_PAGE'), findsOneWidget); // no login sheet
  });

  testWidgets('authed with no default address prompts to select one', (tester) async {
    final session = await buildAuthedSessionStore();

    await tester.pumpWidget(
      page(providers: homeTestProviders(sessionStore: session)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Select your delivery address'), findsOneWidget);
    expect(find.text('Baghdad'), findsNothing);

    await tester.tap(find.byKey(const Key('locationHeaderTap')));
    await tester.pumpAndSettle();

    expect(find.text('ADDRESSES_PAGE'), findsOneWidget);
  });
}
