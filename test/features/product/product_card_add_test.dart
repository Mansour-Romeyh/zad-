import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/features/home/widgets/cart_fly.dart';
import 'package:zad/features/home/widgets/product_card.dart';
import 'package:zad/models/product.dart';

import '../../helpers.dart';

/// The (+) button on the item card must add straight to the basket without
/// opening the detail page, and give add feedback: a fly-to-basket animation
/// inside the Home shell, or an "Added" toast when no basket icon is on screen
/// (pushed routes) or when reduce-motion is on.
void main() {
  Product weightProduct() => Product.fromJson(const {
    'item_code': 'WEIGHT-1',
    'item_name': 'Fresh Tomatoes',
    'price_per_uom': 2500,
    'uom': 'Kg',
    'sold_by_weight': true,
    'weight_step_g': 250,
    'min_g': 750,
    'max_g': 5000,
    'in_stock': true,
  });

  Product unitProduct() => Product.fromJson(const {
    'item_code': 'UNIT-1',
    'item_name': 'Canned Beans',
    'price_per_uom': 3000,
    'uom': 'pc',
    'sold_by_weight': false,
    'in_stock': true,
  });

  Product oosProduct() => Product.fromJson(const {
    'item_code': 'OOS-1',
    'item_name': 'Sold Out Soup',
    'price_per_uom': 1500,
    'uom': 'pc',
    'sold_by_weight': false,
    'in_stock': false,
  });

  /// Records fly() requests instead of animating, so add-feedback is
  /// assertable without driving an overlay animation.
  final flights = <Offset>[];
  CartFlyController recordingController() => _RecordingFlyController(flights);

  Future<CartStore> pumpCard(
    WidgetTester tester,
    Product product, {
    CartFlyController? flyController,
    bool disableAnimations = false,
    CartStore? cart,
  }) async {
    flights.clear();
    cart ??= CartStore(repository: buildFakeCartRepository());
    Widget card = SizedBox(width: 180, child: ProductCard(product: product));
    if (flyController != null) {
      card = CartFlyScope(controller: flyController, child: card);
    }
    await tester.pumpWidget(
      wrapPage(
        MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Scaffold(
            body: Align(alignment: Alignment.topCenter, child: card),
          ),
        ),
        routes: {
          '/product': (_) => const Scaffold(body: Text('DETAIL PAGE')),
        },
        providers: homeTestProviders(
          cartStore: cart,
          sessionStore: await buildAuthedSessionStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cart;
  }

  Future<void> settleAdd(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(); // let the async add complete and _celebrateAdd run
    await tester.pump(); // let a queued SnackBar build into the tree
  }

  testWidgets('(+) on a weight item adds its minimum weight and flies', (
    tester,
  ) async {
    final controller = recordingController();
    addTearDown(controller.dispose);
    final cart = await pumpCard(tester, weightProduct(), flyController: controller);

    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);

    expect(find.text('DETAIL PAGE'), findsNothing);
    expect(cart.count, 1);
    expect(cart.items.single.itemCode, 'WEIGHT-1');
    expect(cart.items.single.qty, 0.75); // min_g 750 -> 0.75 kg
    expect(flights, hasLength(1)); // flew, no toast
  });

  testWidgets('(+) on a unit item adds one unit and flies', (tester) async {
    final controller = recordingController();
    addTearDown(controller.dispose);
    final cart = await pumpCard(tester, unitProduct(), flyController: controller);

    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);

    expect(find.text('DETAIL PAGE'), findsNothing);
    expect(cart.count, 1);
    expect(cart.items.single.itemCode, 'UNIT-1');
    expect(cart.items.single.qty, 1);
    expect(flights, hasLength(1));
  });

  testWidgets('(+) with no CartFlyScope adds and shows the Added toast', (
    tester,
  ) async {
    final cart = await pumpCard(tester, unitProduct()); // no fly controller

    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);

    expect(find.text('DETAIL PAGE'), findsNothing);
    expect(cart.count, 1);
    expect(find.text('Added to basket'), findsOneWidget);

    // Let the 1s SnackBar timer fire so the test leaves no pending timer.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('(+) with reduce-motion adds and toasts instead of flying', (
    tester,
  ) async {
    final controller = recordingController();
    addTearDown(controller.dispose);
    final cart = await pumpCard(
      tester,
      unitProduct(),
      flyController: controller,
      disableAnimations: true,
    );

    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);

    expect(cart.count, 1);
    expect(flights, isEmpty); // did NOT fly
    expect(find.text('Added to basket'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
  });

  testWidgets('unit item: (+) morphs into a stepper that steps and removes', (
    tester,
  ) async {
    final cart = await pumpCard(tester, unitProduct());

    // Not in cart: a compact (+), no stepper value.
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byKey(const Key('cardStepperValue')), findsNothing);

    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);

    // Morphed: stepper at qty 1, the plain (+) is gone.
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byKey(const Key('cardStepperValue')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(cart.count, 1);

    // (+) steps up to 2.
    await tester.tap(find.byKey(const Key('cardStepperIncrement')));
    await settleAdd(tester);
    expect(find.text('2'), findsOneWidget);
    expect(cart.items.single.qty, 2);

    // (−) steps back to 1.
    await tester.tap(find.byKey(const Key('cardStepperDecrement')));
    await settleAdd(tester);
    expect(find.text('1'), findsOneWidget);

    // (−) at the minimum removes the line and collapses to (+).
    await tester.tap(find.byKey(const Key('cardStepperDecrement')));
    await settleAdd(tester);
    expect(cart.count, 0);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byKey(const Key('cardStepperValue')), findsNothing);
  });

  testWidgets('tapping the stepper never opens the detail page', (tester) async {
    await pumpCard(tester, unitProduct());
    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);

    await tester.tap(find.byKey(const Key('cardStepperIncrement')));
    await settleAdd(tester);
    expect(find.text('DETAIL PAGE'), findsNothing);

    // But tapping the name still opens the detail page.
    await tester.tap(find.text('Canned Beans'));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL PAGE'), findsOneWidget);
  });

  testWidgets('weight item: stepper shows g/kg and steps by weight_step_g', (
    tester,
  ) async {
    final cart = await pumpCard(tester, weightProduct());

    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester);
    expect(find.text('750 g'), findsOneWidget); // min_g 750 -> 0.75 kg

    await tester.tap(find.byKey(const Key('cardStepperIncrement')));
    await settleAdd(tester);
    expect(find.text('1 kg'), findsOneWidget); // 750 + 250 = 1000 g
    expect(cart.items.single.qty, 1.0);
  });

  testWidgets(
    'out-of-stock in-cart item: stepper (+) is disabled, (-) stays active',
    (tester) async {
      // The whole card is drawn under a grayscale overlay when out of stock,
      // but that overlay does not block taps — so the stepper's own gating
      // is what must stop adding MORE of an item that can no longer be
      // fulfilled, while still letting the shopper reduce/remove it.
      final cart = CartStore(repository: buildFakeCartRepository());
      // Seed directly (its own (+) is disabled) — inside runAsync so the
      // guest-cart persist (real async I/O) completes instead of deadlocking
      // the fake-async test zone.
      await tester.runAsync(() => cart.add(oosProduct()));
      await pumpCard(tester, oosProduct(), cart: cart);

      expect(find.byKey(const Key('cardStepperValue')), findsOneWidget);

      final increment = tester.widget<IconButton>(
        find.byKey(const Key('cardStepperIncrement')),
      );
      expect(increment.onPressed, isNull);

      final decrement = tester.widget<IconButton>(
        find.byKey(const Key('cardStepperDecrement')),
      );
      expect(decrement.onPressed, isNotNull);
    },
  );

  testWidgets(
    'authed: stepper renders a pre-seeded server line and steps optimistically',
    (tester) async {
      final cart = CartStore(
        repository: buildFakeCartRepository(),
        session: await buildAuthedSessionStore(),
        syncDebounce: Duration.zero,
      );
      // Seed a server line: the add awaits the fake repo (real async I/O),
      // so it must run outside the fake-async test zone to avoid the
      // FakeAsync deadlock.
      await tester.runAsync(() => cart.add(unitProduct()));

      await pumpCard(tester, unitProduct(), cart: cart);

      // Pre-populated straight away: the fake repo echoes the posted qty
      // back as a server line, so `lineFor` finds it without any tap.
      expect(find.byKey(const Key('cardStepperValue')), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cardStepperIncrement')));
      // The optimistic overlay repaints synchronously — assert it before the
      // debounced server sync even fires.
      await tester.pump();
      expect(find.text('2'), findsOneWidget);

      // Explicitly elapse the fake clock by the (zero) debounce so the
      // pending sync Timer fires (plain tester.pump() does not advance the
      // fake clock), then let the fake repo's response settle.
      await tester.pump(Duration.zero);
      await settleAdd(tester);

      expect(find.text('2'), findsOneWidget);
      expect(cart.items.single.qty, 2); // optimistic overlay drove it
    },
  );

  testWidgets('weight item: (+) disables once the stepper reaches max_g', (
    tester,
  ) async {
    final cart = await pumpCard(tester, weightProduct());

    await tester.tap(find.byIcon(Icons.add));
    await settleAdd(tester); // 750 g (min_g)

    // 750 g -> 5000 g (max_g) in steps of 250 g: 17 taps.
    for (var i = 0; i < 17; i++) {
      await tester.tap(find.byKey(const Key('cardStepperIncrement')));
      await settleAdd(tester);
    }

    expect(cart.items.single.qty, 5.0); // 5000 g
    final increment = tester.widget<IconButton>(
      find.byKey(const Key('cardStepperIncrement')),
    );
    expect(increment.onPressed, isNull);
  });

  testWidgets(
    'weight item: (-) at the minimum removes the line and collapses to (+)',
    (tester) async {
      final cart = await pumpCard(tester, weightProduct());

      await tester.tap(find.byIcon(Icons.add));
      await settleAdd(tester); // 750 g == min_g

      await tester.tap(find.byKey(const Key('cardStepperDecrement')));
      await settleAdd(tester);

      expect(cart.count, 0);
      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.byKey(const Key('cardStepperValue')), findsNothing);
    },
  );
}

class _RecordingFlyController extends CartFlyController {
  _RecordingFlyController(this.flights);
  final List<Offset> flights;

  @override
  void fly({
    required Offset from,
    ImageProvider? image,
    required OverlayState overlay,
  }) {
    flights.add(from);
  }
}
