import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/widgets/cart_warnings_listener.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/data/cart_repository.dart';
import 'package:zad/features/basket/basket_page.dart';
import 'package:zad/models/product.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

const _unitProduct = Product(
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

const _weightProduct = Product(
  id: 'ITEM-2',
  nameEn: 'Fresh Tomatoes',
  nameAr: 'طماطم طازجة',
  unitEn: 'Kg',
  unitAr: 'كغم',
  price: 2500,
  imagePath: '',
  itemCode: 'ITEM-2',
  pricePerUom: 2500,
  uom: 'Kg',
  soldByWeight: true,
  weightStepG: 500,
  minG: 500,
  maxG: 5000,
);

CartRepository _fakeRepository({List<String> warningsOnUpdate = const []}) {
  final dio = buildFakeDio((options) {
    if (options.path.endsWith('cart.add_item') || options.path.endsWith('cart.update_item')) {
      final data = options.data as Map<String, dynamic>;
      final isUpdate = options.path.endsWith('cart.update_item');
      final row = isUpdate ? data['row'] as String : 'row-${data['item_code']}';
      final onUpdateWithWarnings = isUpdate && warningsOnUpdate.isNotEmpty;
      return _envelope(options, {
        'items': [
          {
            'name': row,
            'item_code': 'ITEM-1',
            'qty': data['qty'],
            'rate': 1000,
            'amount': 1000,
            'item_name': 'Canned Beans',
          },
        ],
        'totals': {'net_total': 1000, 'grand_total': 1000},
        if (onUpdateWithWarnings) 'warnings': warningsOnUpdate,
      });
    }
    return _envelope(options, {
      'items': <dynamic>[],
      'totals': {'net_total': 0, 'grand_total': 0},
    });
  });
  return CartRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

SessionStore _guestSession() {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  return SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: Dio(), tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
}

Future<CartStore> _guestCartWith(List<(Product, double)> lines, {CartRepository? repository}) async {
  final store = CartStore(repository: repository ?? _fakeRepository(), session: _guestSession());
  for (final (product, qty) in lines) {
    if (product.soldByWeight) {
      await store.add(product, qtyKg: qty);
    } else {
      await store.add(product, qty: qty.toInt());
    }
  }
  return store;
}

Future<void> _pumpBasket(
  WidgetTester tester, {
  required CartStore cartStore,
  SessionStore? sessionStore,
  VoidCallback? onShopNow,
  Map<String, WidgetBuilder> routes = const {},
}) async {
  await tester.pumpWidget(
    wrapPage(
      // BasketPage has no Scaffold of its own — it's hosted inside
      // HomePage's — so a SnackBar-triggering test needs one here. The
      // CartWarningsListener wrapper mirrors app.dart's single app-level
      // warnings subscription (pages no longer subscribe themselves).
      CartWarningsListener(
        child: Scaffold(body: BasketPage(onShopNow: onShopNow ?? () {})),
      ),
      providers: [
        ChangeNotifierProvider<CartStore>.value(value: cartStore),
        ChangeNotifierProvider<SessionStore>.value(value: sessionStore ?? _guestSession()),
      ],
      routes: routes,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BasketPage — empty state', () {
    testWidgets('shows empty message and a shop-now CTA', (tester) async {
      var tapped = false;
      final cart = CartStore(repository: _fakeRepository(), session: _guestSession());

      await _pumpBasket(tester, cartStore: cart, onShopNow: () => tapped = true);

      expect(find.text('Your basket is empty'), findsOneWidget);
      await tester.tap(find.text('Shop Now'));
      await tester.pump();

      expect(tapped, isTrue);
    });
  });

  group('BasketPage — line items', () {
    testWidgets('renders name, unit, qty and line total', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 2)]);

      await _pumpBasket(tester, cartStore: cart);

      expect(find.text('Canned Beans'), findsOneWidget);
      expect(find.text('pc'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('IQD 6,000'), findsWidgets); // 3000 * 2
    });

    testWidgets('totals footer shows subtotal and total', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 2), (_weightProduct, 0.5)]);

      await _pumpBasket(tester, cartStore: cart);

      // 3000*2 + 2500*0.5 = 7250
      expect(find.text('IQD 7,250'), findsWidgets);
    });

    testWidgets('weight item shows a gram/kg qty label', (tester) async {
      final cart = await _guestCartWith([(_weightProduct, 0.5)]);

      await _pumpBasket(tester, cartStore: cart);

      expect(find.text('500 g'), findsOneWidget);
    });
  });

  group('BasketPage — qty stepper (PRD E1)', () {
    testWidgets('increments/decrements a unit item by 1', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 1)]);
      await _pumpBasket(tester, cartStore: cart);

      await tester.tap(find.byIcon(Iconsax.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget);
      expect(cart.items.single.qty, 2);
    });

    testWidgets('decrement is disabled at qty 1 for unit items', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 1)]);
      await _pumpBasket(tester, cartStore: cart);

      final button = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Iconsax.minus_cirlce), matching: find.byType(IconButton)),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('weight item steps by weight_step_g, clamped at min_g', (tester) async {
      final cart = await _guestCartWith([(_weightProduct, 0.5)]);
      await _pumpBasket(tester, cartStore: cart);

      final decrementButton = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Iconsax.minus_cirlce), matching: find.byType(IconButton)),
      );
      expect(decrementButton.onPressed, isNull); // already at min_g (500g)

      await tester.tap(find.byIcon(Iconsax.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('1 kg'), findsOneWidget);
      expect(cart.items.single.qty, 1.0);
    });
  });

  group('BasketPage — remove & clear', () {
    testWidgets('trash icon removes the line', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 1)]);
      await _pumpBasket(tester, cartStore: cart);

      await tester.tap(find.byKey(const Key('removeLine-ITEM-1')));
      await tester.pumpAndSettle();

      expect(cart.items, isEmpty);
      expect(find.text('Your basket is empty'), findsOneWidget);
    });

    testWidgets('swiping a line removes it', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 1)]);
      await _pumpBasket(tester, cartStore: cart);

      await tester.drag(find.text('Canned Beans'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(cart.items, isEmpty);
    });

    testWidgets('clear all shows a confirm dialog; cancel keeps items', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 1)]);
      await _pumpBasket(tester, cartStore: cart);

      await tester.tap(find.byKey(const Key('basketClearAllButton')));
      await tester.pumpAndSettle();

      expect(find.text('Clear basket?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('zadDialogSecondary')));
      await tester.pumpAndSettle();

      expect(cart.items, isNotEmpty);
    });

    testWidgets('clear all confirm empties the basket', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 1), (_weightProduct, 1)]);
      await _pumpBasket(tester, cartStore: cart);

      await tester.tap(find.byKey(const Key('basketClearAllButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zadDialogPrimary')));
      await tester.pumpAndSettle();

      expect(cart.items, isEmpty);
      expect(find.text('Your basket is empty'), findsOneWidget);
    });
  });

  group('BasketPage — checkout CTA', () {
    testWidgets('guest tap shows the login-required prompt and does not navigate', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 1)]);
      await _pumpBasket(
        tester,
        cartStore: cart,
        routes: {'/checkout': (_) => const Scaffold(body: Text('CHECKOUT_MARKER'))},
      );

      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();

      expect(find.text('Log in to continue'), findsOneWidget);
      expect(find.text('CHECKOUT_MARKER'), findsNothing);
    });

    testWidgets('authed tap navigates to /checkout', (tester) async {
      final cart = await _guestCartWith([(_unitProduct, 1)]);
      await _pumpBasket(
        tester,
        cartStore: cart,
        sessionStore: await buildAuthedSessionStore(),
        routes: {'/checkout': (_) => const Scaffold(body: Text('CHECKOUT_MARKER'))},
      );

      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();

      expect(find.text('CHECKOUT_MARKER'), findsOneWidget);
    });
  });

  group('BasketPage — server warnings', () {
    testWidgets('a soft stock warning from a mutation shows a snackbar', (tester) async {
      final repo = _fakeRepository(warningsOnUpdate: const ['Only 2 left of ITEM-1']);
      final session = await buildAuthedSessionStore();
      // updateQty must hit the server (authed mode) for warnings to exist.
      final authedCart = CartStore(repository: repo, session: session);
      // Real async I/O (even against a fake dio) awaited directly in a
      // `testWidgets` body — outside any `pump()` cycle — never resolves
      // under the test binding's fake clock; `runAsync` breaks out to a
      // real zone for it, same as any other genuine async setup work.
      await tester.runAsync(() async {
        await authedCart.restore();
        await authedCart.add(_unitProduct, qty: 1);
      });

      await _pumpBasket(tester, cartStore: authedCart, sessionStore: session);

      await tester.tap(find.byIcon(Iconsax.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('Only 2 left of ITEM-1'), findsOneWidget);
    });
  });

  group('BasketPage — failed mutations surface errors (do not crash)', () {
    /// An authed cart seeded with one line whose add succeeded, backed by a
    /// repository where every subsequent update_item/remove_item/clear
    /// fails with a 500 ("خطأ في الخادم").
    Future<(CartStore, SessionStore)> failingMutationsCart(WidgetTester tester) async {
      final dio = buildFakeDio((options) {
        if (options.path.endsWith('cart.update_item') ||
            options.path.endsWith('cart.remove_item') ||
            options.path.endsWith('cart.clear')) {
          return Response(
            requestOptions: options,
            statusCode: 500,
            data: {'message': 'خطأ في الخادم'},
          );
        }
        if (options.path.endsWith('cart.add_item')) {
          final data = options.data as Map<String, dynamic>;
          return _envelope(options, {
            'items': [
              {
                'name': 'row-1',
                'item_code': data['item_code'],
                'qty': data['qty'],
                'rate': 3000,
                'amount': 3000,
                'item_name': 'Canned Beans',
              },
            ],
            'totals': {'net_total': 3000, 'grand_total': 3000},
          });
        }
        return _envelope(options, {
          'items': <dynamic>[],
          'totals': {'net_total': 0, 'grand_total': 0},
        });
      });
      final repo = CartRepository(
        ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      );
      final session = await buildAuthedSessionStore();
      final cart = CartStore(repository: repo, session: session);
      await tester.runAsync(() async {
        await cart.restore();
        await cart.add(_unitProduct, qty: 1);
      });
      return (cart, session);
    }

    testWidgets('a failing qty update shows an error snackbar and keeps the qty', (tester) async {
      final (cart, session) = await failingMutationsCart(tester);
      await _pumpBasket(tester, cartStore: cart, sessionStore: session);

      await tester.tap(find.byIcon(Iconsax.add_circle));
      await tester.pumpAndSettle();

      expect(find.text('خطأ في الخادم'), findsOneWidget);
      expect(cart.items.single.qty, 1); // unchanged
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing trash-icon remove shows an error snackbar and keeps the line', (tester) async {
      final (cart, session) = await failingMutationsCart(tester);
      await _pumpBasket(tester, cartStore: cart, sessionStore: session);

      await tester.tap(find.byKey(const Key('removeLine-row-1')));
      await tester.pumpAndSettle();

      expect(find.text('خطأ في الخادم'), findsOneWidget);
      expect(cart.items, hasLength(1)); // line still present
      expect(find.text('Canned Beans'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing swipe-remove animates the row back and shows an error snackbar', (tester) async {
      final (cart, session) = await failingMutationsCart(tester);
      await _pumpBasket(tester, cartStore: cart, sessionStore: session);

      await tester.drag(find.text('Canned Beans'), const Offset(-500, 0));
      // Explicit timed pumps instead of pumpAndSettle: while confirmDismiss
      // awaits the (failing) server call no frame is scheduled, so
      // pumpAndSettle would return before the error resolves and the row
      // animates back.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text('خطأ في الخادم'), findsOneWidget);
      expect(cart.items, hasLength(1));
      // confirmDismiss returned false, so the row is resurrected — no
      // "dismissed Dismissible still in tree" assertion.
      expect(find.text('Canned Beans'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing clear-all shows an error snackbar and keeps the basket', (tester) async {
      final (cart, session) = await failingMutationsCart(tester);
      await _pumpBasket(tester, cartStore: cart, sessionStore: session);

      await tester.tap(find.byKey(const Key('basketClearAllButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zadDialogPrimary')));
      await tester.pumpAndSettle();

      expect(find.text('خطأ في الخادم'), findsOneWidget);
      expect(cart.items, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  });
}
