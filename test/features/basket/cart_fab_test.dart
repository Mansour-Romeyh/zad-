import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/features/basket/widgets/cart_fab.dart';
import 'package:zad/models/product.dart';

import '../../helpers.dart';

const _product = Product(
  id: 'ITEM-1',
  nameEn: 'Canned Beans',
  nameAr: 'فاصولياء معلبة',
  unitEn: 'pc',
  unitAr: 'قطعة',
  price: 3000,
  imagePath: '',
  itemCode: 'ITEM-1',
  pricePerUom: 3000,
  uom: 'pc',
);

Future<CartStore> _cart({required bool withItem}) async {
  // A guest cart keeps its lines locally (SharedPreferences) — no auth/network
  // needed to seed it for these tests.
  final store = CartStore(
    repository: buildFakeCartRepository(),
    session: buildGuestSessionStore(),
  );
  if (withItem) await store.add(_product, qty: 1);
  return store;
}

Widget _host(CartStore cart) => wrapPage(
  const Scaffold(
    floatingActionButton: CartFab(),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    body: SizedBox.expand(),
  ),
  providers: [ChangeNotifierProvider<CartStore>.value(value: cart)],
  routes: {'/basket': (_) => const Scaffold(body: Text('BASKET_MARKER'))},
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('is hidden while the cart is empty', (tester) async {
    await tester.pumpWidget(_host(await _cart(withItem: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cartFab')), findsNothing);
  });

  testWidgets('appears once an item is added, showing the basket label', (tester) async {
    await tester.pumpWidget(_host(await _cart(withItem: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cartFab')), findsOneWidget);
    expect(find.text('Basket'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // count pill
  });

  testWidgets('tapping it opens the basket route', (tester) async {
    await tester.pumpWidget(_host(await _cart(withItem: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cartFab')));
    await tester.pumpAndSettle();

    expect(find.text('BASKET_MARKER'), findsOneWidget);
  });

  testWidgets('cartFabClearanceOf reserves space only when the cart has items', (tester) async {
    Future<double> clearanceFor(CartStore cart) async {
      late double value;
      await tester.pumpWidget(
        wrapPage(
          Builder(
            builder: (context) {
              value = cartFabClearanceOf(context);
              return const SizedBox();
            },
          ),
          providers: [ChangeNotifierProvider<CartStore>.value(value: cart)],
        ),
      );
      await tester.pumpAndSettle();
      return value;
    }

    expect(await clearanceFor(await _cart(withItem: false)), 0);
    expect(await clearanceFor(await _cart(withItem: true)), kCartFabClearance);
  });
}
