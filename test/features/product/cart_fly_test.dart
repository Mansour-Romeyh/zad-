import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/home/widgets/cart_fly.dart';

void main() {
  testWidgets('CartFlyScope.maybeOf resolves the controller inside, null outside', (
    tester,
  ) async {
    final controller = CartFlyController();
    addTearDown(controller.dispose);

    late CartFlyController? inside;
    late CartFlyController? outside;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            Builder(builder: (context) {
              outside = CartFlyScope.maybeOf(context);
              return const SizedBox();
            }),
            CartFlyScope(
              controller: controller,
              child: Builder(builder: (context) {
                inside = CartFlyScope.maybeOf(context);
                return const SizedBox();
              }),
            ),
          ],
        ),
      ),
    );

    expect(outside, isNull);
    expect(identical(inside, controller), isTrue);
  });

  test('landings starts at 0', () {
    final controller = CartFlyController();
    addTearDown(controller.dispose);
    expect(controller.landings.value, 0);
  });

  testWidgets('fly() inserts a thumbnail, then removes it and bumps landings', (
    tester,
  ) async {
    final controller = CartFlyController();
    addTearDown(controller.dispose);

    late OverlayState overlayState;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) {
                overlayState = Overlay.of(context);
                // The basket target, given a real size/position via the key.
                return Align(
                  alignment: Alignment.bottomRight,
                  child: SizedBox(
                    key: controller.basketKey,
                    width: 24,
                    height: 24,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );

    controller.fly(
      from: const Offset(20, 20),
      image: null, // icon fallback — no network in tests
      overlay: overlayState,
    );
    await tester.pump(); // insert the entry

    expect(find.byType(FlyingThumbForTest), findsOneWidget); // mid-flight

    await tester.pumpAndSettle(); // finish the ~500ms animation

    expect(find.byType(FlyingThumbForTest), findsNothing); // removed
    expect(controller.landings.value, 1); // bumped once
  });

  testWidgets('two overlapping flies each land and bump landings to 2', (
    tester,
  ) async {
    final controller = CartFlyController();
    addTearDown(controller.dispose);

    late OverlayState overlayState;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) {
                overlayState = Overlay.of(context);
                return Align(
                  alignment: Alignment.bottomRight,
                  child: SizedBox(
                    key: controller.basketKey,
                    width: 24,
                    height: 24,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );

    // Fire a second fly while the first is still mid-flight.
    controller.fly(from: const Offset(20, 20), image: null, overlay: overlayState);
    controller.fly(from: const Offset(40, 40), image: null, overlay: overlayState);
    await tester.pump();

    expect(find.byType(FlyingThumbForTest), findsNWidgets(2)); // both in flight

    await tester.pumpAndSettle();

    expect(find.byType(FlyingThumbForTest), findsNothing); // both removed
    expect(controller.landings.value, 2); // both landings counted
  });
}
