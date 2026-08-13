import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/location/location_service.dart';
import 'package:zad/core/stores/address_store.dart';
import 'package:zad/data/address_repository.dart';
import 'package:zad/features/addresses/address_form_page.dart';

import '../../helpers.dart';
import '../../support/fake_location_service.dart';

/// Pumps a host page with an "open" button that pushes the form, so the
/// form's pop-on-save has a route to return to.
Future<void> _pumpForm(
  WidgetTester tester, {
  AddressModel? existing,
  AddressRepository? repository,
  LocationService? locationService,
  List<RequestOptions>? capturedRequests,
  List<Map<String, dynamic>> initialRows = const [],
}) async {
  final session = await buildAuthedSessionStore();
  final repo = repository ??
      buildFakeAddressRepository(
        initialAddresses: initialRows,
        capturedRequests: capturedRequests,
      );
  final store = AddressStore(repository: repo, session: session);
  // Hydrate like the real app does at splash/login: an un-hydrated store
  // deliberately refuses the auto-default flag on create. runAsync — the
  // fake dio's timers never fire under the test's FakeAsync zone.
  await tester.runAsync(store.restore);
  await tester.pumpWidget(
    wrapPage(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => AddressFormPage(existing: existing),
                ),
              ),
              child: const Text('open form'),
            ),
          ),
        ),
      ),
      providers: homeTestProviders(
        sessionStore: session,
        addressRepository: repo,
        addressStore: store,
        locationService: locationService,
      ),
    ),
  );
  await tester.tap(find.text('open form'));
  await tester.pumpAndSettle();
}

Iterable<RequestOptions> _calls(List<RequestOptions> requests, String suffix) =>
    requests.where((r) => r.path.endsWith(suffix));

void main() {
  testWidgets('address line and city are optional — empty fields still save', (tester) async {
    final requests = <RequestOptions>[];
    await _pumpForm(tester, capturedRequests: requests);

    // Leave both text fields blank and save straight away.
    await tester.tap(find.byKey(const Key('saveAddressButton')));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsNothing);
    final create = _calls(requests, 'address.create').single;
    expect(create.data, {
      'label': 'Home', // default label chip
      'address_line': '', // left empty
      'city': '', // left empty
      'lat': 0, // no location captured
      'lng': 0,
      'is_default': 1, // first address becomes the default
    });
    expect(find.byType(AddressFormPage), findsNothing); // popped after save
  });

  testWidgets('saving sends the selected label chip as the server value', (tester) async {
    final requests = <RequestOptions>[];
    await _pumpForm(tester, capturedRequests: requests);

    await tester.tap(find.byKey(const Key('labelChip-Work')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('addressLineField')), 'Office 4, Karrada');
    await tester.enterText(find.byKey(const Key('addressCityField')), 'Baghdad');
    await tester.tap(find.byKey(const Key('saveAddressButton')));
    await tester.pumpAndSettle();

    final create = _calls(requests, 'address.create').single;
    expect(create.data, {
      'label': 'Work',
      'address_line': 'Office 4, Karrada',
      'city': 'Baghdad',
      'lat': 0, // no location captured — manual entry
      'lng': 0,
      'is_default': 1, // first address becomes the default
    });
    expect(find.byType(AddressFormPage), findsNothing); // popped after save
    expect(find.text('Address saved'), findsOneWidget); // plain confirmation
  });

  testWidgets('"use my current location" captures coordinates and shows the coverage banner', (tester) async {
    final requests = <RequestOptions>[];
    final location = FakeLocationService(
      location: const DeviceLocation(lat: 33.5, lng: 44.5),
    );
    await _pumpForm(tester, capturedRequests: requests, locationService: location);

    await tester.tap(find.byKey(const Key('useCurrentLocationButton')));
    await tester.pumpAndSettle();

    expect(location.callCount, 1);
    expect(find.text('Location captured'), findsOneWidget);
    // Instant zone feedback from zone.resolve.
    final resolve = _calls(requests, 'zone.resolve').single;
    expect(resolve.queryParameters, {'lat': 33.5, 'lng': 44.5});
    expect(find.byKey(const Key('zoneBanner')), findsOneWidget);
    expect(find.text('Within delivery zone: Central Baghdad'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('addressLineField')), 'House 12');
    await tester.enterText(find.byKey(const Key('addressCityField')), 'Baghdad');
    await tester.tap(find.byKey(const Key('saveAddressButton')));
    await tester.pumpAndSettle();

    final create = _calls(requests, 'address.create').single;
    expect(create.data['lat'], 33.5);
    expect(create.data['lng'], 44.5);
    // Save surfaces the server's zone result for the captured point.
    expect(find.text('Within delivery zone: Central Baghdad'), findsOneWidget);
  });

  testWidgets('an outside-coverage point warns but the address still saves', (tester) async {
    final requests = <RequestOptions>[];
    final repo = buildFakeAddressRepository(
      zoneInfo: const {'outside_coverage': true},
      resolveResponse: const {'outside_coverage': true},
      capturedRequests: requests,
    );
    await _pumpForm(tester, repository: repo);

    await tester.tap(find.byKey(const Key('useCurrentLocationButton')));
    await tester.pumpAndSettle();

    // Inline banner right after the capture.
    expect(find.byKey(const Key('zoneBanner')), findsOneWidget);
    expect(
      find.textContaining('outside our delivery coverage'),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('addressLineField')), 'Far house');
    await tester.enterText(find.byKey(const Key('addressCityField')), 'Basra');
    await tester.tap(find.byKey(const Key('saveAddressButton')));
    await tester.pumpAndSettle();

    // Saved anyway (PRD E5 — checkout blocks later, not the address book).
    expect(_calls(requests, 'address.create'), hasLength(1));
    expect(find.byType(AddressFormPage), findsNothing); // popped — saved
    expect(
      find.textContaining('outside our delivery coverage'),
      findsOneWidget, // warning SnackBar after the save
    );
  });

  testWidgets('permission denied shows a message and manual entry still saves', (tester) async {
    final requests = <RequestOptions>[];
    final location = FakeLocationService(
      failure: LocationFailureReason.permissionDenied,
    );
    await _pumpForm(tester, capturedRequests: requests, locationService: location);

    await tester.tap(find.byKey(const Key('useCurrentLocationButton')));
    await tester.pumpAndSettle();

    expect(location.callCount, 1);
    expect(
      find.text('Location permission denied — you can enter the address manually.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('zoneBanner')), findsNothing);
    expect(_calls(requests, 'zone.resolve'), isEmpty);

    // Manual fallback stays fully usable.
    await tester.enterText(find.byKey(const Key('addressLineField')), 'House 12');
    await tester.enterText(find.byKey(const Key('addressCityField')), 'Baghdad');
    await tester.tap(find.byKey(const Key('saveAddressButton')));
    await tester.pumpAndSettle();

    final create = _calls(requests, 'address.create').single;
    expect(create.data['lat'], 0);
    expect(create.data['lng'], 0);
    expect(find.byType(AddressFormPage), findsNothing); // saved and popped
  });

  testWidgets('location service unavailable shows the generic fallback message', (tester) async {
    final location = FakeLocationService(
      failure: LocationFailureReason.serviceDisabled,
    );
    await _pumpForm(tester, locationService: location);

    await tester.tap(find.byKey(const Key('useCurrentLocationButton')));
    await tester.pumpAndSettle();

    expect(
      find.text("Couldn't get your location — you can enter the address manually."),
      findsOneWidget,
    );
  });

  testWidgets('edit mode prefills and posts an update with the address name', (tester) async {
    final requests = <RequestOptions>[];
    const existing = AddressModel(
      name: 'ADDR-9',
      label: 'Home',
      addressLine: 'Old line',
      city: 'Baghdad',
      lat: 33.31,
      lng: 44.37,
      isDefault: true,
    );
    await _pumpForm(
      tester,
      existing: existing,
      capturedRequests: requests,
      initialRows: const [
        {
          'name': 'ADDR-9',
          'label': 'Home',
          'address_line': 'Old line',
          'city': 'Baghdad',
          'lat': 33.31,
          'lng': 44.37,
          'is_default': 1,
        },
      ],
    );

    expect(find.text('Edit Address'), findsOneWidget);
    expect(find.text('Old line'), findsOneWidget);
    expect(find.text('Location captured'), findsOneWidget); // existing coords

    await tester.enterText(find.byKey(const Key('addressLineField')), 'New line');
    await tester.tap(find.byKey(const Key('labelChip-Other')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveAddressButton')));
    await tester.pumpAndSettle();

    final update = _calls(requests, 'address.update').single;
    expect(update.data['name'], 'ADDR-9');
    expect(update.data['label'], 'Other');
    expect(update.data['address_line'], 'New line');
    expect(update.data['lat'], 33.31); // kept coordinates
    expect(_calls(requests, 'address.create'), isEmpty);
    expect(find.byType(AddressFormPage), findsNothing);
  });
}
