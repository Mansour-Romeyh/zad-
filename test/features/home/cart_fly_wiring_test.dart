import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/cart_fly.dart';

import '../../helpers.dart';

void main() {
  testWidgets('Home shell provides a CartFlyScope with a live basket target', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          sessionStore: await buildAuthedSessionStore(),
        ),
      ),
    );
    // Settle the shell so the bottom-nav basket icon lays out and the fake
    // catalog/content loads (and their fake-Dio timers) drain — a single
    // pump would leave a pending Timer at teardown.
    await tester.pumpAndSettle();

    final scope = tester.widget<CartFlyScope>(find.byType(CartFlyScope));
    expect(scope.controller.basketKey.currentContext, isNotNull);
  });
}
