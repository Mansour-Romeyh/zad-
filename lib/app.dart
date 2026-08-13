import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api/api_client.dart';
import 'core/api/token_store.dart';
import 'core/audio/order_feedback_service.dart';
import 'core/location/location_service.dart';
import 'core/push/push_registrar.dart';
import 'core/push/push_service.dart';
import 'core/services/url_opener.dart';
import 'core/session/session_store.dart';
import 'core/stores/address_store.dart';
import 'core/stores/app_config_store.dart';
import 'core/stores/cart_store.dart';
import 'core/stores/favourites_store.dart';
import 'core/stores/locale_store.dart';
import 'core/stores/settings_store.dart';
import 'core/stores/notifications_store.dart';
import 'core/theme.dart';
import 'core/widgets/cart_warnings_listener.dart';
import 'data/address_repository.dart';
import 'data/auth_repository.dart';
import 'data/cart_repository.dart';
import 'data/catalog_repository.dart';
import 'data/content_repository.dart';
import 'data/notifications_repository.dart';
import 'data/order_repository.dart';
import 'data/profile_repository.dart';
import 'data/search_repository.dart';
import 'data/wishlist_repository.dart';
import 'features/addresses/address_list_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/auth/reset_password_page.dart';
import 'features/category/category_browser_page.dart';
import 'features/checkout/checkout_page.dart';
import 'features/home/home_page.dart';
import 'features/notifications/notifications_page.dart';
import 'features/orders/orders_page.dart';
import 'features/home/widgets/zad_bottom_nav.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/product/best_deals_page.dart';
import 'features/product/product_detail_page.dart';
import 'features/search/search_page.dart';
import 'features/splash/maintenance_page.dart';
import 'features/splash/splash_page.dart';
import 'l10n/app_localizations.dart';

class ZadApp extends StatelessWidget {
  const ZadApp({this.pushService, super.key});

  /// Push platform for this build — FCM when `main()` booted Firebase,
  /// null (treated as noop) in tests and pushless builds.
  final PushService? pushService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<TokenStore>(create: (_) => TokenStore()),
        Provider<ApiClient>(
          create: (context) =>
              ApiClient(tokenStore: context.read<TokenStore>()),
        ),
        Provider<AuthRepository>(
          create: (context) => AuthRepository(context.read<ApiClient>()),
        ),
        Provider<CatalogRepository>(
          create: (context) => CatalogRepository(context.read<ApiClient>()),
        ),
        Provider<ContentRepository>(
          create: (context) => ContentRepository(context.read<ApiClient>()),
        ),
        Provider<SearchRepository>(
          create: (context) => SearchRepository(context.read<ApiClient>()),
        ),
        Provider<CartRepository>(
          create: (context) => CartRepository(context.read<ApiClient>()),
        ),
        Provider<WishlistRepository>(
          create: (context) => WishlistRepository(context.read<ApiClient>()),
        ),
        Provider<AddressRepository>(
          create: (context) => AddressRepository(context.read<ApiClient>()),
        ),
        Provider<OrderRepository>(
          create: (context) => OrderRepository(context.read<ApiClient>()),
        ),
        Provider<ProfileRepository>(
          create: (context) => ProfileRepository(context.read<ApiClient>()),
        ),
        Provider<NotificationsRepository>(
          create: (context) =>
              NotificationsRepository(context.read<ApiClient>()),
        ),
        // App language — Arabic by default (Arabic-first market), an
        // explicit choice from profile → language is persisted across runs.
        ChangeNotifierProvider<LocaleStore>(
          create: (_) => LocaleStore()..load(),
        ),
        // Persisted user preferences (order-placed confirmation sound). Loaded
        // at boot like LocaleStore; default ON.
        ChangeNotifierProvider<SettingsStore>(
          create: (_) => SettingsStore()..load(),
        ),
        // Injectable seam over `audioplayers` (order-placed pip + haptic).
        // Package-freeze exception; only AudioOrderFeedbackService imports the
        // plugin, tests swap in a fake.
        Provider<OrderFeedbackService>(
          create: (_) => AudioOrderFeedbackService(),
        ),
        // Boot-time config (PRD F2/D1.1): splash look, maintenance gate,
        // support phone. Guest-accessible — no session dependency.
        ChangeNotifierProvider<AppConfigStore>(
          create: (context) =>
              AppConfigStore(repository: context.read<ContentRepository>()),
        ),
        // Injectable seam over platform location (PRD F4 "use my current
        // location") — screens read the interface, so tests swap in a fake
        // and never touch the geolocator platform channel.
        Provider<LocationService>(
          create: (_) => const GeolocatorLocationService(),
        ),
        // Injectable seam over `url_launcher` (Terms/Privacy links etc.) —
        // screens read the interface, so tests swap in a fake and never
        // touch the platform channel.
        Provider<UrlOpener>(create: (_) => const DefaultUrlOpener()),
        ChangeNotifierProvider<SessionStore>(
          create: (context) {
            final store = SessionStore(
              authRepository: context.read<AuthRepository>(),
              tokenStore: context.read<TokenStore>(),
            );
            // 401 from any API call drops the whole app back to guest, not
            // just the screen that happened to make the failing request.
            context.read<ApiClient>().onUnauthenticated = store.forceLogout;
            return store;
          },
        ),
        // Not lazy: must listen from boot so a restored session (or the
        // first login) registers this device's FCM token with the backend.
        Provider<PushRegistrar>(
          lazy: false,
          create: (context) => PushRegistrar(
            pushService: pushService ?? const NoopPushService(),
            profileRepository: context.read<ProfileRepository>(),
            sessionStore: context.read<SessionStore>(),
          )..start(),
          dispose: (_, registrar) => registrar.dispose(),
        ),
        // Depends on SessionStore (above) to hydrate on login and clear on
        // logout (PRD F8 wishlist sync).
        ChangeNotifierProvider<FavouritesStore>(
          create: (context) => FavouritesStore(
            repository: context.read<WishlistRepository>(),
            session: context.read<SessionStore>(),
          ),
        ),
        // Depends on SessionStore (above) to react to login/logout
        // transitions (PRD J2 guest-cart merge on login).
        ChangeNotifierProvider<CartStore>(
          create: (context) => CartStore(
            repository: context.read<CartRepository>(),
            session: context.read<SessionStore>(),
          ),
        ),
        // Depends on SessionStore (above) to hydrate on login and clear on
        // logout (PRD F4 address book + A3 first-login nudge).
        ChangeNotifierProvider<AddressStore>(
          create: (context) => AddressStore(
            repository: context.read<AddressRepository>(),
            session: context.read<SessionStore>(),
          ),
        ),
        // Depends on SessionStore (above) to hydrate the unread badge on
        // login and clear it on logout (PRD F2 notifications).
        ChangeNotifierProvider<NotificationsStore>(
          create: (context) => NotificationsStore(
            repository: context.read<NotificationsRepository>(),
            session: context.read<SessionStore>(),
          ),
        ),
      ],
      child: Consumer<LocaleStore>(
        builder: (context, localeStore, child) => MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          theme: zadTheme(),
          locale: localeStore.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The ONE app-level subscription that turns CartStore.warnings into
          // SnackBars — sits below the root ScaffoldMessenger and above the
          // Navigator, so a warning shows exactly once on whatever screen is
          // on top. Pages must not add their own warnings subscriptions.
          builder: (context, child) =>
              CartWarningsListener(child: child ?? const SizedBox.shrink()),
          initialRoute: '/',
          routes: {
            '/': (_) => const SplashPage(),
            '/onboarding': (_) => const OnboardingPage(),
            '/home': (_) => const HomePage(),
            '/auth/login': (_) => const LoginPage(),
            '/auth/register': (_) => const RegisterPage(),
            '/auth/reset': (_) => const ResetPasswordPage(),
            '/categories': (_) => const CategoryBrowserPage(),
            '/best-deals': (_) => const BestDealsPage(),
            '/product': (_) => const ProductDetailPage(),
            '/search': (_) => const SearchPage(),
            '/basket': (_) => const HomePage(initialIndex: kBasketNavIndex),
            '/addresses': (_) => const AddressListPage(),
            '/checkout': (_) => const CheckoutPage(),
            '/orders': (_) => const OrdersPage(),
            '/notifications': (_) => const NotificationsPage(),
            '/maintenance': (_) => const MaintenancePage(),
          },
        ),
      ),
    );
  }
}
