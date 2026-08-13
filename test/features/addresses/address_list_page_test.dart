import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/address_store.dart';
import 'package:zad/data/address_repository.dart';
import 'package:zad/features/addresses/address_form_page.dart';
import 'package:zad/features/addresses/address_list_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Map<String, dynamic> _row(
  String name, {
  String label = 'Home',
  String line = 'House 12, Al-Mansour',
  int isDefault = 0,
}) =>
    {
      'name': name,
      'label': label,
      'address_line': line,
      'city': 'Baghdad',
      'lat': 33.31,
      'lng': 44.37,
      'is_default': isDefault,
    };

Future<AddressStore> _pumpListPage(
  WidgetTester tester, {
  List<Map<String, dynamic>> rows = const [],
  SessionStore? session,
  AddressRepository? repository,
  List<RequestOptions>? capturedRequests,
}) async {
  final resolvedSession = session ?? await buildAuthedSessionStore();
  final repo = repository ??
      buildFakeAddressRepository(
        initialAddresses: rows,
        capturedRequests: capturedRequests,
      );
  final store = AddressStore(repository: repo, session: resolvedSession);
  await tester.pumpWidget(
    wrapPage(
      const AddressListPage(),
      providers: homeTestProviders(
        sessionStore: resolvedSession,
        addressRepository: repo,
        addressStore: store,
      ),
    ),
  );
  // The page refreshes post-frame; settle so the list hydrates.
  await tester.pumpAndSettle();
  return store;
}

void main() {
  testWidgets('renders address cards default-first with the default badge', (tester) async {
    await _pumpListPage(tester, rows: [
      _row('ADDR-1', line: 'House 12'),
      _row('ADDR-2', label: 'Work', line: 'Office 4', isDefault: 1),
    ]);

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Office 4, Baghdad'), findsOneWidget);
    expect(find.text('House 12, Baghdad'), findsOneWidget);
    // Only the default row carries the badge; the other row offers
    // set-default instead.
    expect(find.byKey(const Key('defaultBadge-ADDR-2')), findsOneWidget);
    expect(find.byKey(const Key('defaultBadge-ADDR-1')), findsNothing);
    expect(find.byKey(const Key('setDefault-ADDR-1')), findsOneWidget);
    expect(find.byKey(const Key('setDefault-ADDR-2')), findsNothing);
  });

  testWidgets('empty state shows the prompt and the Add CTA opens the form', (tester) async {
    await _pumpListPage(tester);

    expect(find.text('No addresses yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('addAddressButton')));
    await tester.pumpAndSettle();

    expect(find.byType(AddressFormPage), findsOneWidget);
    expect(find.text('New Address'), findsOneWidget);
  });

  testWidgets('set-default posts and the refreshed list keeps exactly one default', (tester) async {
    final requests = <RequestOptions>[];
    await _pumpListPage(
      tester,
      rows: [
        _row('ADDR-2', label: 'Work', isDefault: 1),
        _row('ADDR-1'),
      ],
      capturedRequests: requests,
    );

    await tester.tap(find.byKey(const Key('setDefault-ADDR-1')));
    await tester.pumpAndSettle();

    final setDefaultCalls = requests.where((r) => r.path.endsWith('address.set_default'));
    expect(setDefaultCalls.single.data, {'name': 'ADDR-1'});
    // Exclusivity after the list refresh: the badge moved, the old default
    // now offers set-default.
    expect(find.byKey(const Key('defaultBadge-ADDR-1')), findsOneWidget);
    expect(find.byKey(const Key('defaultBadge-ADDR-2')), findsNothing);
    expect(find.byKey(const Key('setDefault-ADDR-2')), findsOneWidget);
    expect(find.byKey(const Key('setDefault-ADDR-1')), findsNothing);
  });

  testWidgets('delete asks for confirmation — cancel keeps the address', (tester) async {
    final requests = <RequestOptions>[];
    await _pumpListPage(
      tester,
      rows: [_row('ADDR-1', isDefault: 1)],
      capturedRequests: requests,
    );

    await tester.tap(find.byKey(const Key('deleteAddress-ADDR-1')));
    await tester.pumpAndSettle();
    expect(find.text('Delete address?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('zadDialogSecondary')));
    await tester.pumpAndSettle();

    expect(requests.where((r) => r.path.endsWith('address.delete')), isEmpty);
    expect(find.text('House 12, Al-Mansour, Baghdad'), findsOneWidget);
  });

  testWidgets('delete confirm removes the card', (tester) async {
    final requests = <RequestOptions>[];
    await _pumpListPage(
      tester,
      rows: [
        _row('ADDR-2', label: 'Work', line: 'Office 4', isDefault: 1),
        _row('ADDR-1'),
      ],
      capturedRequests: requests,
    );

    await tester.tap(find.byKey(const Key('deleteAddress-ADDR-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zadDialogPrimary')));
    await tester.pumpAndSettle();

    final deletes = requests.where((r) => r.path.endsWith('address.delete'));
    expect(deletes.single.data, {'name': 'ADDR-1'});
    expect(find.text('House 12, Al-Mansour, Baghdad'), findsNothing);
    expect(find.text('Office 4, Baghdad'), findsOneWidget);
  });

  testWidgets('edit opens the form prefilled with the address', (tester) async {
    await _pumpListPage(tester, rows: [_row('ADDR-1', isDefault: 1)]);

    await tester.tap(find.byKey(const Key('editAddress-ADDR-1')));
    await tester.pumpAndSettle();

    expect(find.text('Edit Address'), findsOneWidget);
    expect(find.text('House 12, Al-Mansour'), findsOneWidget); // line prefilled
    expect(find.text('Baghdad'), findsOneWidget); // city prefilled
  });

  testWidgets('a guest gets the login prompt, no list call, no add button', (tester) async {
    final requests = <RequestOptions>[];
    final session = buildGuestSessionStore();
    await _pumpListPage(tester, session: session, capturedRequests: requests);

    expect(find.text('Log in to continue'), findsOneWidget);
    expect(find.byKey(const Key('addAddressButton')), findsNothing);
    expect(requests, isEmpty); // AddressStore.refresh no-ops for guests
  });

  testWidgets('a failed hydrate shows the retry prompt and retry recovers', (tester) async {
    var fail = true;
    final repo = AddressRepository(
      ApiClient(
        dio: buildFakeDio((options) {
          if (fail && options.path.endsWith('address.list')) {
            return Response(
              requestOptions: options,
              statusCode: 500,
              data: {'message': 'boom'},
            );
          }
          return Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'message': [_row('ADDR-1', isDefault: 1)],
            },
          );
        }),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      ),
    );
    await _pumpListPage(tester, repository: repo);

    expect(find.text('Something went wrong'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('House 12, Al-Mansour, Baghdad'), findsOneWidget);
  });
}
