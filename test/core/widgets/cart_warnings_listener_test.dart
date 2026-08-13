import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/core/widgets/cart_warnings_listener.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/data/cart_repository.dart';
import 'package:zad/l10n/app_localizations.dart';
import 'package:zad/models/product.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

const _product = Product(
  id: 'ITEM-1',
  nameEn: 'Milk',
  nameAr: 'حليب',
  unitEn: 'pc',
  unitAr: 'قطعة',
  price: 1500,
  imagePath: '',
  itemCode: 'ITEM-1',
  pricePerUom: 1500,
  uom: 'pc',
);

/// A repository whose `add_item` responds with a soft stock warning.
CartRepository _warningRepository() {
  final dio = buildFakeDio((options) {
    final isAdd = options.path.endsWith('cart.add_item');
    return Response(
      requestOptions: options,
      statusCode: 200,
      data: {
        'message': {
          'items': isAdd
              ? [
                  {'name': 'row-1', 'item_code': 'ITEM-1', 'qty': 1, 'rate': 1500, 'amount': 1500},
                ]
              : <dynamic>[],
          'totals': {'net_total': 1500, 'grand_total': 1500},
          if (isAdd) 'warnings': ['Only 2 left of ITEM-1'],
        },
      },
    );
  });
  return CartRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

/// A repository whose `add_item` responds with TWO soft stock warnings in
/// the same snapshot, so CartStore.warnings emits both in one event.
CartRepository _twoWarningsRepository() {
  final dio = buildFakeDio((options) {
    final isAdd = options.path.endsWith('cart.add_item');
    return Response(
      requestOptions: options,
      statusCode: 200,
      data: {
        'message': {
          'items': isAdd
              ? [
                  {'name': 'row-1', 'item_code': 'ITEM-1', 'qty': 1, 'rate': 1500, 'amount': 1500},
                ]
              : <dynamic>[],
          'totals': {'net_total': 1500, 'grand_total': 1500},
          if (isAdd) 'warnings': ['Only 2 left of ITEM-1', 'Only 1 left of ITEM-2'],
        },
      },
    );
  });
  return CartRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'a warning-bearing add on a page pushed over the shell shows exactly ONE snackbar',
      (tester) async {
    final session = await buildAuthedSessionStore();
    final cart = CartStore(repository: _warningRepository(), session: session);
    await tester.runAsync(cart.restore);

    // Mirrors app.dart's wiring: the ONE CartWarningsListener sits in
    // MaterialApp.builder — below the root ScaffoldMessenger, above the
    // Navigator — and no page carries its own subscription.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionStore>.value(value: session),
          ChangeNotifierProvider<CartStore>.value(value: cart),
        ],
        child: MaterialApp(
          theme: zadTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              CartWarningsListener(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    // The "detail page" pushed over the shell: were pages
                    // subscribing individually, both this route and the one
                    // below it would each show the warning.
                    builder: (_) => Scaffold(
                      body: Builder(
                        builder: (context) => ElevatedButton(
                          onPressed: () => context.read<CartStore>().add(_product),
                          child: const Text('add'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('open detail'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open detail'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    expect(find.text('Only 2 left of ITEM-1'), findsOneWidget); // exactly one
  });

  testWidgets('two warnings emitted in one event both stay visible (not just the last)',
      (tester) async {
    final session = await buildAuthedSessionStore();
    final cart = CartStore(repository: _twoWarningsRepository(), session: session);
    await tester.runAsync(cart.restore);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionStore>.value(value: session),
          ChangeNotifierProvider<CartStore>.value(value: cart),
        ],
        child: MaterialApp(
          theme: zadTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              CartWarningsListener(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => context.read<CartStore>().add(_product),
                child: const Text('add'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('add'));
    // showZadSnack floats in with a ~250ms transition; pump past it without
    // pumpAndSettle (the snackbar's own timer would keep it dirty for its
    // full display duration).
    await tester.pump(const Duration(milliseconds: 300));

    // Both warnings must be visible — the pre-fix looping `_show` clears
    // the first snackbar the instant the second one is shown, so only the
    // last warning ever survives.
    expect(find.textContaining('Only 2 left of ITEM-1'), findsOneWidget);
    expect(find.textContaining('Only 1 left of ITEM-2'), findsOneWidget);
  });

  testWidgets('the sync-failed sentinel renders as localized text, not the marker', (tester) async {
    // Guest session whose login() succeeds against a fake dio, so a real
    // guest→authed transition fires the store's merge-on-login.
    final tokenStore = TokenStore(storage: FakeSecureStorage());
    final loginDio = buildFakeDio(
      (options) => Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'message': {
            'api_key': 'k',
            'api_secret': 's',
            'profile': {'user': 'jane@app.local'},
          },
        },
      ),
    );
    final session = SessionStore(
      authRepository: AuthRepository(
        ApiClient(dio: loginDio, tokenStore: tokenStore, baseUrl: 'http://test.local'),
      ),
      tokenStore: tokenStore,
    );

    // Repository whose cart.merge always fails → the store emits the
    // kCartSyncFailedWarning sentinel.
    final failDio = buildFakeDio((options) {
      if (options.path.endsWith('cart.merge')) {
        return Response(requestOptions: options, statusCode: 500, data: {'message': 'boom'});
      }
      return Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'message': {'items': <dynamic>[], 'totals': {'net_total': 0, 'grand_total': 0}},
        },
      );
    });
    final cart = CartStore(
      repository: CartRepository(
        ApiClient(dio: failDio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
      ),
      session: session,
    );
    await tester.runAsync(() async {
      await session.restore();
      await cart.restore();
      await cart.add(_product); // guest line, so login triggers a merge
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SessionStore>.value(value: session),
          ChangeNotifierProvider<CartStore>.value(value: cart),
        ],
        child: MaterialApp(
          theme: zadTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              CartWarningsListener(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    await tester.runAsync(() async {
      await session.login(phone: '+9647701234567', password: 'p@ss');
      await cart.sessionSyncDone; // merge fails; sentinel emitted
      await Future<void>.delayed(Duration.zero); // deliver the stream event
    });
    await tester.pump();

    expect(find.text("Couldn't sync your basket — will retry."), findsOneWidget);
    expect(find.text(kCartSyncFailedWarning), findsNothing); // marker never shown raw
  });
}
