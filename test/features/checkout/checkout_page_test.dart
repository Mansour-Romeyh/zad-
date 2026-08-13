import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/audio/order_feedback_service.dart';
import 'package:zad/core/stores/address_store.dart';
import 'package:zad/core/stores/app_config_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/stores/settings_store.dart';
import 'package:zad/data/address_repository.dart';
import 'package:zad/data/cart_repository.dart';
import 'package:zad/features/auth/widgets/zad_primary_button.dart';
import 'package:zad/features/checkout/checkout_page.dart';
import 'package:zad/features/checkout/order_success_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_order_feedback_service.dart';
import '../../support/fake_secure_storage.dart';

const _cartLines = [
  {
    'name': 'row-1',
    'item_code': 'ITEM-1',
    'item_name': 'Fresh Tomatoes',
    'qty': 0.5,
    'uom': 'Kg',
    'rate': 1500,
    'amount': 750,
    'sold_by_weight': true,
    'weight_step_g': 500,
    'in_stock': true,
  },
  {
    'name': 'row-2',
    'item_code': 'ITEM-2',
    'item_name': 'Milk',
    'qty': 2,
    'uom': 'Nos',
    'rate': 2000,
    'amount': 4000,
    'in_stock': true,
  },
];

const _addresses = [
  {
    'name': 'ADDR-1',
    'label': 'Home',
    'address_line': 'House 12, Al-Mansour',
    'city': 'Baghdad',
    'lat': 33.31,
    'lng': 44.37,
    'is_default': 1,
  },
  {
    'name': 'ADDR-2',
    'label': 'Work',
    'address_line': 'Office 4, Karrada St',
    'city': 'Baghdad',
    'lat': 0.0,
    'lng': 0.0,
    'is_default': 0,
  },
];

/// A [CartRepository] whose every `cart.*` call answers [_cartLines] —
/// enough for the summary and for observing the post-order `cart.get`.
CartRepository _cartRepository({List<RequestOptions>? capturedRequests}) {
  final dio = buildFakeDio(
    (options) => Response(
      requestOptions: options,
      statusCode: 200,
      data: {
        'message': {
          'items': _cartLines,
          'totals': {'net_total': 4750, 'grand_total': 4750},
        },
      },
    ),
    capturedRequests: capturedRequests,
  );
  return CartRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

/// An [AppConfigStore] hydrated with [appConfig] via a fake network fetch.
Future<AppConfigStore> _loadedConfigStore(
  WidgetTester tester,
  Map<String, dynamic> appConfig,
) async {
  final store = AppConfigStore(
    repository: buildFakeContentRepository(appConfig: appConfig),
  );
  await tester.runAsync(store.load);
  return store;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Builds the standard authed checkout fixture: a hydrated cart with two
  /// lines, an address book with a default, and (optionally) a custom
  /// order-repository behaviour.
  Future<Widget> buildCheckout(
    WidgetTester tester, {
    List<Map<String, dynamic>> addresses = _addresses,
    Response<dynamic>? Function(RequestOptions options)? orderOverrides,
    List<RequestOptions>? orderRequests,
    List<RequestOptions>? cartRequests,
    Map<String, WidgetBuilder> routes = const {},
    AppConfigStore? appConfigStore,
    DateTime Function()? clock,
    OrderFeedbackService? orderFeedbackService,
    SettingsStore? settingsStore,
  }) async {
    final session = await buildAuthedSessionStore();
    final cart = CartStore(repository: _cartRepository(capturedRequests: cartRequests), session: session);
    await tester.runAsync(cart.restore);
    final addressStore = AddressStore(
      repository: buildFakeAddressRepository(initialAddresses: addresses),
      session: session,
    );
    await tester.runAsync(addressStore.restore);
    return wrapPage(
      CheckoutPage(clock: clock ?? DateTime.now),
      routes: routes,
      providers: homeTestProviders(
        sessionStore: session,
        cartStore: cart,
        addressStore: addressStore,
        appConfigStore: appConfigStore,
        orderFeedbackService: orderFeedbackService,
        settingsStore: settingsStore,
        orderRepository: buildFakeOrderRepository(
          overrides: orderOverrides,
          capturedRequests: orderRequests,
        ),
      ),
    );
  }

  Iterable<RequestOptions> placeOrderRequests(List<RequestOptions> requests) =>
      requests.where((r) => r.path.endsWith('order.place_order'));

  /// Confirm an order through the new 30s hold: tap Place Order to open the
  /// confirm overlay, then "Send now" to fire immediately (skipping the
  /// auto-send countdown). Settles the place_order call + any navigation.
  Future<void> placeOrderNow(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('placeOrderButton')));
    await tester.pump(); // build the confirm overlay
    await tester.tap(find.byKey(const Key('confirmSendNowButton')));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'renders the default-preselected address, summary lines, COD and totals',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await buildCheckout(tester));
    await tester.pumpAndSettle();

    // Default address preselected, the other selectable.
    expect(
      find.descendant(
        of: find.byKey(const Key('addressOption-ADDR-1')),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('addressOption-ADDR-2')),
        matching: find.byIcon(Icons.radio_button_off),
      ),
      findsOneWidget,
    );

    // Summary lines + totals from the CartStore.
    expect(find.text('Fresh Tomatoes'), findsOneWidget);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('IQD 750'), findsOneWidget);
    expect(find.text('IQD 4,000'), findsOneWidget);
    expect(find.text('IQD 4,750'), findsNWidgets(2)); // subtotal + total

    // Fixed COD payment method.
    expect(find.text('Cash on Delivery'), findsOneWidget);

    // Tapping the other address moves the selection.
    await tester.tap(find.byKey(const Key('addressOption-ADDR-2')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const Key('addressOption-ADDR-2')),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'place order posts the selected address with a uuid key, refreshes the '
      'cart and shows the success page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final orderRequests = <RequestOptions>[];
    final cartRequests = <RequestOptions>[];
    await tester.pumpWidget(
      await buildCheckout(tester, orderRequests: orderRequests, cartRequests: cartRequests),
    );
    await tester.pumpAndSettle();
    final cartGetsBefore =
        cartRequests.where((r) => r.path.endsWith('cart.get')).length;

    await placeOrderNow(tester);

    final placed = placeOrderRequests(orderRequests).single;
    final data = placed.data as Map<String, dynamic>;
    expect(data['address'], 'ADDR-1'); // the preselected default
    final key = data['idempotency_key'] as String;
    expect(key, hasLength(36)); // uuid v4
    expect(key.split('-'), hasLength(5));

    // Success page with the order number + Pending Assignment chip.
    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(find.text('Order number: SAL-ORD-2026-00001'), findsOneWidget);
    expect(find.byKey(const Key('orderStatusChip-Pending Assignment')), findsOneWidget);

    // The server closed the Quotation — the cart was re-pulled.
    final cartGetsAfter =
        cartRequests.where((r) => r.path.endsWith('cart.get')).length;
    expect(cartGetsAfter, cartGetsBefore + 1);
  });

  testWidgets('plays order-placed feedback once on success when enabled',
      (tester) async {
    final feedback = FakeOrderFeedbackService();
    await tester.pumpWidget(
      await buildCheckout(tester, orderFeedbackService: feedback),
    );
    await placeOrderNow(tester);

    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(feedback.playOrderPlacedCount, 1);
  });

  testWidgets('does not play feedback when the setting is disabled',
      (tester) async {
    final feedback = FakeOrderFeedbackService();
    final settings = SettingsStore();
    await tester.runAsync(() => settings.setOrderSoundEnabled(false));
    await tester.pumpWidget(
      await buildCheckout(
        tester,
        orderFeedbackService: feedback,
        settingsStore: settings,
      ),
    );
    await placeOrderNow(tester);

    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(feedback.playOrderPlacedCount, 0);
  });

  testWidgets('order still confirms when feedback throws', (tester) async {
    final feedback = FakeOrderFeedbackService(throwOnPlay: true);
    await tester.pumpWidget(
      await buildCheckout(tester, orderFeedbackService: feedback),
    );
    await placeOrderNow(tester);

    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(feedback.playOrderPlacedCount, 1);
  });

  testWidgets('a failed attempt retries with the SAME idempotency key',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final orderRequests = <RequestOptions>[];
    var placeCalls = 0;
    await tester.pumpWidget(
      await buildCheckout(
        tester,
        orderRequests: orderRequests,
        orderOverrides: (options) {
          if (!options.path.endsWith('order.place_order')) return null;
          placeCalls++;
          if (placeCalls == 1) {
            return Response(
              requestOptions: options,
              statusCode: 500,
              data: {'message': 'Server exploded'},
            );
          }
          return null; // second attempt succeeds via the default handler
        },
      ),
    );
    await tester.pumpAndSettle();

    await placeOrderNow(tester);
    // Friendly-errors contract: raw server strings never reach the user — a
    // 500 surfaces the generic message (userErrorMessage → errorGeneric).
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget, // SnackBar
    );
    expect(find.byType(OrderSuccessPage), findsNothing);

    // Let the SnackBar expire so it no longer covers the CTA.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await placeOrderNow(tester);
    expect(find.byType(OrderSuccessPage), findsOneWidget);

    final keys = placeOrderRequests(orderRequests)
        .map((r) => (r.data as Map<String, dynamic>)['idempotency_key'])
        .toList();
    expect(keys, hasLength(2));
    expect(keys.first, keys.last); // held constant across the retry
  });

  testWidgets('retrying after the 409 dialog reuses the SAME idempotency key',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final orderRequests = <RequestOptions>[];
    var placeCalls = 0;
    await tester.pumpWidget(
      await buildCheckout(
        tester,
        orderRequests: orderRequests,
        orderOverrides: (options) {
          if (!options.path.endsWith('order.place_order')) return null;
          placeCalls++;
          if (placeCalls == 1) {
            return Response(
              requestOptions: options,
              statusCode: 409,
              data: {
                'message': 'These items are not available: ITEM-1',
                'items': ['ITEM-1'],
              },
            );
          }
          return null; // second attempt succeeds via the default handler
        },
      ),
    );
    await tester.pumpAndSettle();

    await placeOrderNow(tester);
    expect(find.text('Some items are unavailable'), findsOneWidget);

    await tester.tap(find.byKey(const Key('outOfStockCancelButton')));
    await tester.pumpAndSettle();

    await placeOrderNow(tester);
    expect(find.byType(OrderSuccessPage), findsOneWidget);

    final keys = placeOrderRequests(orderRequests)
        .map((r) => (r.data as Map<String, dynamic>)['idempotency_key'])
        .toList();
    expect(keys, hasLength(2));
    expect(keys.first, keys.last); // one attempt = one key, 409 included
  });

  testWidgets('a double-tap on Send now issues exactly one place_order',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final orderRequests = <RequestOptions>[];
    await tester.pumpWidget(
      await buildCheckout(tester, orderRequests: orderRequests),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('placeOrderButton')));
    await tester.pump(); // confirm overlay

    // Two taps before any rebuild can tear down the overlay — the
    // re-entrancy guard, not the loading state, must absorb the second.
    await tester.tap(find.byKey(const Key('confirmSendNowButton')));
    await tester.tap(find.byKey(const Key('confirmSendNowButton')),
        warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(OrderSuccessPage), findsOneWidget);
    expect(placeOrderRequests(orderRequests), hasLength(1));
  });

  testWidgets(
      'a failed address hydrate shows an inline error with retry that recovers',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await buildAuthedSessionStore();
    final cart = CartStore(repository: _cartRepository(), session: session);
    await tester.runAsync(cart.restore);

    var listCalls = 0;
    final addressDio = buildFakeDio((options) {
      if (options.path.endsWith('address.list')) {
        listCalls++;
        // Call 1 = store restore, call 2 = the page's own initState
        // refresh — both must fail for the error row to be reachable.
        if (listCalls <= 2) {
          return Response(
            requestOptions: options,
            statusCode: 500,
            data: {'message': 'boom'},
          );
        }
        return Response(
          requestOptions: options,
          statusCode: 200,
          data: {'message': _addresses},
        );
      }
      return Response(
        requestOptions: options,
        statusCode: 200,
        data: {'message': {'ok': true}},
      );
    });
    final addressStore = AddressStore(
      repository: AddressRepository(
        ApiClient(
          dio: addressDio,
          tokenStore: TokenStore(storage: FakeSecureStorage()),
          baseUrl: 'http://test.local',
        ),
      ),
      session: session,
    );
    await tester.runAsync(addressStore.restore); // hydrate fails

    await tester.pumpWidget(
      wrapPage(
        const CheckoutPage(),
        providers: homeTestProviders(
          sessionStore: session,
          cartStore: cart,
          addressStore: addressStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Inline error row instead of a silently empty section; the page (and
    // its manage-addresses escape hatch) stays usable.
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.byKey(const Key('addressSectionRetryButton')), findsOneWidget);
    expect(find.byKey(const Key('manageAddressesButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('addressSectionRetryButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('addressOption-ADDR-1')), findsOneWidget);
    expect(find.byKey(const Key('addressSectionRetryButton')), findsNothing);
  });

  testWidgets('409 shows the out-of-stock dialog naming the items; '
      'تحديث السلة refreshes the cart', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final cartRequests = <RequestOptions>[];
    await tester.pumpWidget(
      await buildCheckout(
        tester,
        cartRequests: cartRequests,
        orderOverrides: (options) {
          if (!options.path.endsWith('order.place_order')) return null;
          return Response(
            requestOptions: options,
            statusCode: 409,
            data: {
              'message': 'These items are not available: ITEM-1',
              'items': ['ITEM-1', 'ITEM-X'],
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();
    final cartGetsBefore =
        cartRequests.where((r) => r.path.endsWith('cart.get')).length;

    await placeOrderNow(tester);

    expect(find.text('Some items are unavailable'), findsOneWidget);
    // Known cart line resolved to its display name; unknown code verbatim.
    expect(find.text('• Fresh Tomatoes'), findsOneWidget);
    expect(find.text('• ITEM-X'), findsOneWidget);

    await tester.tap(find.byKey(const Key('zadDialogPrimary')));
    await tester.pumpAndSettle();

    expect(find.text('Some items are unavailable'), findsNothing);
    final cartGetsAfter =
        cartRequests.where((r) => r.path.endsWith('cart.get')).length;
    expect(cartGetsAfter, cartGetsBefore + 1);
  });

  testWidgets('417 shows the outside-coverage dialog deep-linking to /addresses',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      await buildCheckout(
        tester,
        routes: {
          '/addresses': (_) => const Scaffold(body: Text('ADDRESSES_MARKER')),
        },
        orderOverrides: (options) {
          if (!options.path.endsWith('order.place_order')) return null;
          return Response(
            requestOptions: options,
            statusCode: 417,
            data: {
              'exc_type': 'OutsideCoverageError',
              'message': 'This address is outside our delivery coverage area.',
            },
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await placeOrderNow(tester);

    expect(find.text('Outside delivery coverage'), findsOneWidget);
    // Copy directs to a different address OR setting the location pin.
    expect(
      find.textContaining('Choose a different address'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('zadDialogPrimary')));
    await tester.pumpAndSettle();
    expect(find.text('ADDRESSES_MARKER'), findsOneWidget);
  });

  testWidgets('guests get a login prompt and no order call', (tester) async {
    final orderRequests = <RequestOptions>[];
    final session = buildGuestSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const CheckoutPage(),
        providers: homeTestProviders(
          sessionStore: session,
          orderRepository: buildFakeOrderRepository(capturedRequests: orderRequests),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Log in to continue'), findsOneWidget);
    expect(find.byKey(const Key('placeOrderButton')), findsNothing);
    expect(orderRequests, isEmpty);
  });

  testWidgets('no saved addresses: prompt shown and the CTA is disabled',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(await buildCheckout(tester, addresses: const []));
    await tester.pumpAndSettle();

    expect(
      find.text('No delivery address yet — add one to place your order.'),
      findsOneWidget,
    );
    final button = tester.widget<ElevatedButton>(
      find.descendant(
        of: find.byKey(const Key('placeOrderButton')),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull);

    // The manage-addresses link is the way out.
    expect(find.byKey(const Key('manageAddressesButton')), findsOneWidget);
  });

  group('store working hours', () {
    const hoursConfig = {
      'store_open_time': '09:00:00',
      'store_close_time': '23:00:00',
    };

    testWidgets('closed window shows notice and disables Place Order',
        (tester) async {
      final orderRequests = <RequestOptions>[];
      final page = await buildCheckout(
        tester,
        appConfigStore: await _loadedConfigStore(tester, hoursConfig),
        clock: () => DateTime(2026, 7, 17, 23, 30),
        orderRequests: orderRequests,
      );
      await tester.pumpWidget(page);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('storeClosedNotice')), findsOneWidget);
      final button = tester.widget<ZadPrimaryButton>(
        find.byKey(const Key('placeOrderButton')),
      );
      expect(button.onPressed, isNull);
      expect(orderRequests, isEmpty);
    });

    testWidgets('open window keeps checkout unchanged', (tester) async {
      final page = await buildCheckout(
        tester,
        appConfigStore: await _loadedConfigStore(tester, hoursConfig),
        clock: () => DateTime(2026, 7, 17, 12),
      );
      await tester.pumpWidget(page);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('storeClosedNotice')), findsNothing);
      final button = tester.widget<ZadPrimaryButton>(
        find.byKey(const Key('placeOrderButton')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('server 425 flips checkout to the closed state',
        (tester) async {
      // App thinks the store is open (no hours in config) — the server
      // disagrees (clock skew / stale config): 425 must surface the same
      // closed UI instead of a raw error.
      final page = await buildCheckout(
        tester,
        orderOverrides: (options) =>
            options.path.endsWith('order.place_order')
                ? Response(
                    requestOptions: options,
                    statusCode: 425,
                    data: {'message': 'store_closed'},
                  )
                : null,
      );
      await tester.pumpWidget(page);
      await tester.pumpAndSettle();

      await placeOrderNow(tester);

      expect(find.byKey(const Key('storeClosedNotice')), findsOneWidget);
      final button = tester.widget<ZadPrimaryButton>(
        find.byKey(const Key('placeOrderButton')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('delivery fee', () {
    testWidgets('shows the delivery fee line and adds it to the total',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final configStore = await _loadedConfigStore(
        tester,
        {'delivery_fee': 2000, 'free_delivery_over': 25000},
      );
      await tester
          .pumpWidget(await buildCheckout(tester, appConfigStore: configStore));
      await tester.pumpAndSettle();

      expect(find.text('Delivery'), findsOneWidget);
      expect(find.text('IQD 2,000'), findsOneWidget); // fee line
      expect(find.text('IQD 4,750'), findsOneWidget); // subtotal
      expect(find.text('IQD 6,750'), findsOneWidget); // subtotal + fee
    });

    testWidgets('shows Free when the basket clears the free-delivery threshold',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final configStore = await _loadedConfigStore(
        tester,
        {'delivery_fee': 2000, 'free_delivery_over': 1000}, // 4750 >= 1000 → free
      );
      await tester
          .pumpWidget(await buildCheckout(tester, appConfigStore: configStore));
      await tester.pumpAndSettle();

      expect(find.text('Delivery'), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('IQD 4,750'), findsNWidgets(2)); // subtotal + total
    });
  });

  group('confirm hold (30s cancel window)', () {
    testWidgets('Place Order opens the confirm hold and sends nothing yet',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final orderRequests = <RequestOptions>[];
      await tester
          .pumpWidget(await buildCheckout(tester, orderRequests: orderRequests));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('placeOrderButton')));
      await tester.pump();

      expect(find.byKey(const Key('confirmCountdownOverlay')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('confirmCountdownSeconds'))).data,
        '30',
      );
      // The order has NOT reached the server during the hold.
      expect(placeOrderRequests(orderRequests), isEmpty);

      // Cancel to stop the running timer before the test ends.
      await tester.tap(find.byKey(const Key('confirmCancelButton')));
      await tester.pumpAndSettle();
    });

    testWidgets('Cancel & edit discards the hold — no order, back on checkout',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final orderRequests = <RequestOptions>[];
      await tester
          .pumpWidget(await buildCheckout(tester, orderRequests: orderRequests));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('placeOrderButton')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('confirmCancelButton')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('confirmCountdownOverlay')), findsNothing);
      expect(find.byKey(const Key('placeOrderButton')), findsOneWidget);
      expect(find.byType(OrderSuccessPage), findsNothing);
      expect(placeOrderRequests(orderRequests), isEmpty);
    });

    testWidgets('the hold ticks down and auto-sends when it reaches zero',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final orderRequests = <RequestOptions>[];
      await tester
          .pumpWidget(await buildCheckout(tester, orderRequests: orderRequests));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('placeOrderButton')));
      await tester.pump();

      // One second in, the ring shows 29 and still nothing is sent.
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.widget<Text>(find.byKey(const Key('confirmCountdownSeconds'))).data,
        '29',
      );
      expect(placeOrderRequests(orderRequests), isEmpty);

      // Let the rest of the window elapse — the order auto-sends.
      await tester.pump(const Duration(seconds: 29));
      await tester.pumpAndSettle();

      expect(placeOrderRequests(orderRequests), hasLength(1));
      expect(find.byType(OrderSuccessPage), findsOneWidget);
    });
  });
}
