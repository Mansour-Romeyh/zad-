import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/address_store.dart';
import 'package:zad/core/stores/app_config_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/data/cart_repository.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/data/search_repository.dart';
import 'package:zad/features/addresses/address_form_page.dart';
import 'package:zad/features/addresses/address_list_page.dart';
import 'package:zad/features/auth/login_page.dart';
import 'package:zad/features/auth/register_page.dart';
import 'package:zad/features/auth/reset_password_page.dart';
import 'package:zad/features/basket/basket_page.dart';
import 'package:zad/features/category/category_browser_page.dart';
import 'package:zad/features/checkout/checkout_page.dart';
import 'package:zad/features/favourites/favourites_tab.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/notifications/notifications_page.dart';
import 'package:zad/features/onboarding/onboarding_page.dart';
import 'package:zad/features/orders/orders_page.dart';
import 'package:zad/features/profile/profile_tab.dart';
import 'package:zad/features/product/product_detail_page.dart';
import 'package:zad/features/search/search_page.dart';
import 'package:zad/models/product.dart';

import 'helpers.dart';
import 'support/fake_dio.dart';
import 'support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

SessionStore _guestSession() {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  return SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: Dio(), tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('home renders RTL in Arabic without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) {
          return _envelope(options, [
            {'name': 'veg', 'label': 'خضروات وفواكه', 'item_count': 5},
          ]);
        }
        if (options.path.endsWith('get_best_items')) {
          // Paged envelope — the real backend contract for list endpoints.
          return _envelope(options, {
            'items': [
              {
                'item_code': 'ITEM-1',
                'item_name': 'طماطم طازجة',
                'price_per_uom': 1500,
                'uom': 'كغم',
                'in_stock': true,
              },
            ],
            'page': 1,
            'has_more': false,
          });
        }
        return _envelope(options, <dynamic>[]); // banners
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        locale: const Locale('ar'),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تسوق حسب الفئة'), findsOneWidget);
    expect(find.text('خضروات وفواكه'), findsOneWidget);
    expect(find.text('طماطم طازجة'), findsOneWidget);
    final context = tester.element(find.byType(HomePage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding renders RTL in Arabic without overflow',
      (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const OnboardingPage(),
        locale: const Locale('ar'),
        providers: [
          Provider<ContentRepository>.value(value: buildFakeContentRepository()),
        ],
      ),
    );
    // Let the (empty) get_onboarding fetch settle so its timeout timer is
    // cancelled before teardown.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('اشترِ مقاضيك بسهولة معنا'), findsOneWidget);
    expect(find.text('تخطي'), findsOneWidget);
    final context = tester.element(find.byType(OnboardingPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login renders RTL in Arabic without overflow', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const LoginPage(),
        locale: const Locale('ar'),
        providers: [ChangeNotifierProvider<SessionStore>.value(value: _guestSession())],
      ),
    );
    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('+964'), findsOneWidget);
    final context = tester.element(find.byType(LoginPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('register renders RTL in Arabic without overflow', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const RegisterPage(),
        locale: const Locale('ar'),
        providers: [ChangeNotifierProvider<SessionStore>.value(value: _guestSession())],
      ),
    );
    expect(find.text('إنشاء حساب جديد'), findsOneWidget);
    final context = tester.element(find.byType(RegisterPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset password renders RTL in Arabic without overflow', (tester) async {
    await tester.pumpWidget(
      wrapPage(
        const ResetPasswordPage(),
        locale: const Locale('ar'),
        providers: [ChangeNotifierProvider<SessionStore>.value(value: _guestSession())],
      ),
    );
    expect(find.text('إعادة تعيين كلمة المرور'), findsWidgets);
    final context = tester.element(find.byType(ResetPasswordPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category page renders RTL in Arabic without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('get_categories')) {
          return _envelope(options, [
            {'name': 'veg', 'label': 'خضار', 'item_count': 3},
          ]);
        }
        // items_by_category returns the paged envelope.
        return _envelope(options, {
          'items': [
            {
              'item_code': 'ITEM-1',
              'item_name': 'طماطم طازجة',
              'price_per_uom': 1500,
              'uom': 'كغم',
              'in_stock': true,
            },
          ],
          'page': 1,
          'has_more': false,
        });
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    await tester.pumpWidget(
      wrapPage(
        const CategoryBrowserPage(),
        locale: const Locale('ar'),
        providers: homeTestProviders(catalogRepository: CatalogRepository(client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('طماطم طازجة'), findsOneWidget);
    final context = tester.element(find.byType(CategoryBrowserPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product detail page renders RTL in Arabic without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = ApiClient(
      dio: buildFakeDio(
        (options) => _envelope(options, {
          'item_code': 'ITEM-1',
          'item_name': 'طماطم طازجة',
          'price_per_uom': 1500,
          'uom': 'كغم',
          'sold_by_weight': true,
          'weight_step_g': 500,
          'min_g': 500,
          'max_g': 5000,
          'in_stock': true,
        }),
      ),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    await tester.pumpWidget(
      wrapPage(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProductDetailPage(),
                settings: const RouteSettings(arguments: 'ITEM-1'),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        locale: const Locale('ar'),
        providers: homeTestProviders(catalogRepository: CatalogRepository(client)),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('طماطم طازجة'), findsOneWidget);
    final context = tester.element(find.byType(ProductDetailPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search page renders RTL in Arabic without overflow', (tester) async {
    final client = ApiClient(
      dio: buildFakeDio((options) {
        if (options.path.endsWith('search.trending')) {
          return _envelope(options, [
            {'item_code': 'ITEM-1', 'item_name': 'طماطم طازجة'},
          ]);
        }
        return _envelope(options, <dynamic>[]);
      }),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    await tester.pumpWidget(
      wrapPage(
        const SearchPage(),
        locale: const Locale('ar'),
        providers: homeTestProviders(searchRepository: SearchRepository(client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('الرائج'), findsOneWidget);
    expect(find.text('طماطم طازجة'), findsOneWidget);
    final context = tester.element(find.byType(SearchPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('basket page renders RTL in Arabic without overflow', (tester) async {
    const product = Product(
      id: 'ITEM-1',
      nameEn: 'Fresh Tomatoes',
      nameAr: 'طماطم طازجة',
      unitEn: 'Kg',
      unitAr: 'كغم',
      price: 1500,
      imagePath: '',
      itemCode: 'ITEM-1',
      pricePerUom: 1500,
      uom: 'كغم',
      soldByWeight: true,
      weightStepG: 500,
      minG: 500,
      maxG: 5000,
    );
    final client = ApiClient(
      dio: buildFakeDio((options) => _envelope(options, <dynamic>[])),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    final cart = CartStore(repository: CartRepository(client), session: _guestSession());
    await cart.add(product, qtyKg: 0.5);

    await tester.pumpWidget(
      wrapPage(
        Scaffold(body: BasketPage(onShopNow: () {})),
        locale: const Locale('ar'),
        providers: homeTestProviders(cartStore: cart),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('طماطم طازجة'), findsOneWidget);
    expect(find.text('السلة'), findsOneWidget);
    final context = tester.element(find.byType(BasketPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('address list renders RTL in Arabic without overflow', (tester) async {
    final session = await buildAuthedSessionStore();
    final store = AddressStore(
      repository: buildFakeAddressRepository(
        initialAddresses: const [
          {
            'name': 'ADDR-1',
            'label': 'Home',
            'address_line': 'شارع فلسطين، بناية ١٢',
            'city': 'بغداد',
            'lat': 33.31,
            'lng': 44.37,
            'is_default': 1,
          },
        ],
      ),
      session: session,
    );
    await tester.runAsync(store.restore);

    await tester.pumpWidget(
      wrapPage(
        const AddressListPage(),
        locale: const Locale('ar'),
        providers: homeTestProviders(sessionStore: session, addressStore: store),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('عناويني'), findsOneWidget);
    expect(find.text('منزل'), findsOneWidget);
    expect(find.text('إضافة عنوان'), findsOneWidget);
    final context = tester.element(find.byType(AddressListPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('address form renders RTL in Arabic without overflow', (tester) async {
    final session = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const AddressFormPage(),
        locale: const Locale('ar'),
        providers: homeTestProviders(sessionStore: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('عنوان جديد'), findsOneWidget);
    expect(find.text('منزل'), findsOneWidget); // label chips
    expect(find.text('عمل'), findsOneWidget);
    expect(find.text('أخرى'), findsOneWidget);
    expect(find.text('استخدام موقعي الحالي'), findsOneWidget);
    expect(find.text('حفظ'), findsOneWidget);
    final context = tester.element(find.byType(AddressFormPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('favourites tab renders RTL in Arabic without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await buildAuthedSessionStore();
    final favourites = FavouritesStore(
      repository: buildFakeWishlistRepository(
        items: [
          {
            'item_code': 'ITEM-1',
            'item_name': 'طماطم طازجة',
            'price_per_uom': 1500,
            'uom': 'كغم',
            'in_stock': true,
            'is_favourite': true,
          },
        ],
      ),
      session: session,
    );
    await tester.runAsync(favourites.restore);

    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: FavouritesTab()),
        locale: const Locale('ar'),
        providers: homeTestProviders(favouritesStore: favourites, sessionStore: session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('المفضلة'), findsOneWidget);
    expect(find.text('طماطم طازجة'), findsOneWidget);
    final context = tester.element(find.byType(FavouritesTab));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkout renders RTL in Arabic without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await buildAuthedSessionStore();
    final cartClient = ApiClient(
      dio: buildFakeDio(
        (options) => _envelope(options, {
          'items': [
            {
              'name': 'row-1',
              'item_code': 'ITEM-1',
              'item_name': 'طماطم طازجة',
              'qty': 1,
              'uom': 'كغم',
              'rate': 1500,
              'amount': 1500,
              'in_stock': true,
            },
          ],
          'totals': {'net_total': 1500, 'grand_total': 1500},
        }),
      ),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    );
    final cart = CartStore(repository: CartRepository(cartClient), session: session);
    await tester.runAsync(cart.restore);
    final addressStore = AddressStore(
      repository: buildFakeAddressRepository(
        initialAddresses: const [
          {
            'name': 'ADDR-1',
            'label': 'Home',
            'address_line': 'شارع فلسطين، بناية ١٢',
            'city': 'بغداد',
            'lat': 33.31,
            'lng': 44.37,
            'is_default': 1,
          },
        ],
      ),
      session: session,
    );
    await tester.runAsync(addressStore.restore);

    await tester.pumpWidget(
      wrapPage(
        const CheckoutPage(),
        locale: const Locale('ar'),
        providers: homeTestProviders(
          sessionStore: session,
          cartStore: cart,
          addressStore: addressStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('إتمام الطلب'), findsOneWidget);
    expect(find.text('طماطم طازجة'), findsOneWidget);
    expect(find.text('الدفع عند الاستلام'), findsOneWidget);
    expect(find.text('تأكيد الطلب'), findsOneWidget);
    final context = tester.element(find.byType(CheckoutPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile tab renders RTL in Arabic without overflow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = await buildAuthedSessionStore(
        fullName: 'جين', phone: '+9647700000001');
    final configStore = AppConfigStore(
      repository: buildFakeContentRepository(
        appConfig: const {
          'terms_url': 'https://zad.micronext.net/terms',
          'privacy_url': 'https://zad.micronext.net/privacy-policy',
        },
      ),
    );
    await tester.runAsync(configStore.load);
    await tester.pumpWidget(
      wrapPage(
        const Scaffold(body: ProfileTab()),
        locale: const Locale('ar'),
        providers: homeTestProviders(
          sessionStore: session,
          appConfigStore: configStore,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مرحباً، جين'), findsOneWidget);
    expect(find.text('عناويني'), findsOneWidget);
    expect(find.text('طلباتي'), findsOneWidget);
    expect(find.text('تغيير كلمة المرور'), findsOneWidget);
    expect(find.text('الشروط والأحكام'), findsOneWidget);
    expect(find.text('سياسة الخصوصية'), findsOneWidget);
    expect(find.text('الدعم'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);
    final context = tester.element(find.byType(ProfileTab));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notifications page renders RTL in Arabic without overflow', (tester) async {
    final session = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const NotificationsPage(),
        locale: const Locale('ar'),
        providers: homeTestProviders(
          sessionStore: session,
          notificationsRepository: buildFakeNotificationsRepository(
            overrides: (options) {
              if (!options.path.endsWith('notifications.list')) return null;
              return _envelope(options, {
                'items': [
                  {
                    'name': 'NL-1',
                    'title': 'تم استلام طلبك',
                    'body': '<p>سيتم تجهيزه قريباً</p>',
                    'read': false,
                    'creation': '2026-07-13 10:30:00.000000',
                  },
                ],
                'page': 1,
                'has_more': false,
              });
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('الإشعارات'), findsOneWidget);
    expect(find.text('تم استلام طلبك'), findsOneWidget);
    expect(find.text('سيتم تجهيزه قريباً'), findsOneWidget);
    final context = tester.element(find.byType(NotificationsPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });

  testWidgets('orders list renders RTL in Arabic without overflow', (tester) async {
    final session = await buildAuthedSessionStore();
    await tester.pumpWidget(
      wrapPage(
        const OrdersPage(),
        locale: const Locale('ar'),
        providers: homeTestProviders(
          sessionStore: session,
          orderRepository: buildFakeOrderRepository(
            overrides: (options) {
              if (!options.path.endsWith('order.my_orders')) return null;
              return _envelope(options, {
                'items': [
                  {
                    'name': 'SAL-ORD-2026-00001',
                    'date': '2026-07-13',
                    'status': 'Delivered',
                    'grand_total': 4750,
                    'item_count': 2,
                  },
                ],
                'page': 1,
                'has_more': false,
              });
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('طلباتي'), findsOneWidget);
    expect(find.text('تم التوصيل'), findsOneWidget);
    final context = tester.element(find.byType(OrdersPage));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}
