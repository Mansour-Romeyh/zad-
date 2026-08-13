import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/features/home/widgets/cart_fly.dart';
import 'package:zad/features/home/widgets/zad_bottom_nav.dart';

import '../../helpers.dart';

void main() {
  testWidgets('basket icon registers the fly target and bounces on landing', (
    tester,
  ) async {
    final controller = CartFlyController();
    addTearDown(controller.dispose);
    final cart = CartStore(repository: buildFakeCartRepository());

    await tester.pumpWidget(
      wrapPage(
        CartFlyScope(
          controller: controller,
          child: Scaffold(
            bottomNavigationBar: ZadBottomNav(activeIndex: 0, onTap: (_) {}),
          ),
        ),
        providers: homeTestProviders(cartStore: cart),
      ),
    );
    await tester.pump();

    // The basket icon attached the fly target key.
    expect(controller.basketKey.currentContext, isNotNull);

    // Find the exact ScaleTransition wrapping the basket icon (via the key it
    // wraps), not any other ScaleTransition in the tree.
    final basketScaleFinder = find.ancestor(
      of: find.byKey(controller.basketKey),
      matching: find.byType(ScaleTransition),
    );
    expect(basketScaleFinder, findsOneWidget);
    double basketScale() =>
        tester.widget<ScaleTransition>(basketScaleFinder).scale.value;

    // Idle: no bounce yet.
    expect(basketScale(), 1.0);

    // A landing must actually drive the bounce: the scale rises above 1.0
    // partway through the animation. If the landings->bounce wiring were
    // removed, the scale would stay at 1.0 and this assertion would fail.
    (controller.landings as ValueNotifier<int>).value++;
    await tester.pump(); // start the animation
    await tester.pump(const Duration(milliseconds: 80)); // into the up-phase
    expect(basketScale(), greaterThan(1.0));

    // Then it settles back to rest.
    await tester.pumpAndSettle();
    expect(basketScale(), 1.0);
  });
}
