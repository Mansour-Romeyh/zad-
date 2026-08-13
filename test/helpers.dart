import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:nested/nested.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/audio/order_feedback_service.dart';
import 'package:zad/core/location/location_service.dart';
import 'package:zad/core/services/url_opener.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/address_store.dart';
import 'package:zad/core/stores/app_config_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/core/stores/notifications_store.dart';
import 'package:zad/core/stores/settings_store.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/data/address_repository.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/data/cart_repository.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/data/notifications_repository.dart';
import 'package:zad/data/order_repository.dart';
import 'package:zad/data/search_repository.dart';
import 'package:zad/data/wishlist_repository.dart';
import 'package:zad/l10n/app_localizations.dart';

import 'support/fake_dio.dart';
import 'support/fake_location_service.dart';
import 'support/fake_secure_storage.dart';

/// Wraps [child] in a [MaterialApp] configured like the real app shell
/// (theme, l10n, routes). Pass [providers] to make store types (e.g.
/// `SessionStore`) available via `context.read`/`context.watch` — omitted
/// by default so existing screen tests that don't touch provider state
/// keep working unchanged.
Widget wrapPage(
  Widget child, {
  Locale locale = const Locale('en'),
  Map<String, WidgetBuilder> routes = const {},
  List<SingleChildWidget> providers = const [],
}) {
  final app = MaterialApp(
    locale: locale,
    theme: zadTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    routes: routes,
    home: child,
  );
  if (providers.isEmpty) return app;
  return MultiProvider(providers: providers, child: app);
}

/// A guest [SessionStore] backed by in-memory fakes (no platform channels,
/// no network) — the default session state for most widget tests.
SessionStore buildGuestSessionStore() {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  return SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: Dio(), tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
}

/// An already-authed [SessionStore]: seeds a fake secure storage with saved
/// credentials, then restores from it — no network call, no login flow.
Future<SessionStore> buildAuthedSessionStore({
  String user = 'test@app.local',
  String? fullName,
  String? phone,
}) async {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  await tokenStore.save(apiKey: 'test-key', apiSecret: 'test-secret', user: user, fullName: fullName, phone: phone);
  final store = SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: Dio(), tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
  await store.restore();
  return store;
}

/// A [CartRepository] backed by a minimal in-memory-ish fake server:
/// `add_item`/`update_item` echo back a single line built from whatever
/// `item_code`/`qty`/`row` was posted, so widget tests can assert "the tap
/// reached `CartStore.add`/`updateQty` with the right item" without
/// depending on `cart_store_test.dart`'s deeper server-sync coverage. Every
/// other `cart.*` call returns an empty cart.
CartRepository buildFakeCartRepository() {
  final dio = buildFakeDio((options) {
    if (options.path.endsWith('cart.add_item') || options.path.endsWith('cart.update_item')) {
      final data = options.data as Map<String, dynamic>;
      final row = data['row'] as String? ?? 'row-${data['item_code']}';
      final itemCode = data['item_code'] as String? ?? row.replaceFirst('row-', '');
      return Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'message': {
            'items': [
              {
                'name': row,
                'item_code': itemCode,
                'qty': data['qty'],
                'uom': data['uom'],
                'rate': 0,
                'amount': 0,
                'item_name': itemCode,
              },
            ],
            'totals': {'net_total': 0, 'grand_total': 0},
          },
        },
      );
    }
    return Response(
      requestOptions: options,
      statusCode: 200,
      data: {
        'message': {'items': <dynamic>[], 'totals': {'net_total': 0, 'grand_total': 0}},
      },
    );
  });
  return CartRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

/// A [WishlistRepository] backed by a minimal fake server: `wishlist.list`
/// returns [items] (ItemCard JSON maps), `add`/`remove` answer `{ok: true}`
/// — so widget tests can assert "the heart tap reached the store/server"
/// without depending on `favourites_store_test.dart`'s deeper sync
/// coverage. Pass [capturedRequests] to observe which calls were made.
WishlistRepository buildFakeWishlistRepository({
  List<Map<String, dynamic>> items = const [],
  List<RequestOptions>? capturedRequests,
}) {
  final dio = buildFakeDio(
    (options) {
      if (options.path.endsWith('wishlist.list')) {
        return Response(requestOptions: options, statusCode: 200, data: {'message': items});
      }
      return Response(
        requestOptions: options,
        statusCode: 200,
        data: {
          'message': {'ok': true},
        },
      );
    },
    capturedRequests: capturedRequests,
  );
  return WishlistRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

/// Default zone info a fake `address.create`/`address.update` embeds in its
/// response (`{zone: {...}}`), mirroring the backend's `_zone_info`.
const kFakeZoneInfo = {
  'zone': {'zone_name': 'Central Baghdad', 'warehouse': 'Main Store - GR'},
};

/// An [AddressRepository] backed by a small stateful fake server that
/// mirrors `address.py`'s behaviour: `list` returns the rows default-first
/// (then newest first), `create` assigns `ADDR-n` names, `create(is_default
/// =1)`/`set_default` clear every other default (exclusivity), `delete`
/// removes, and `create`/`update` responses embed [zoneInfo] (pass
/// `{'outside_coverage': true}` to simulate an uncovered point).
/// `zone.resolve` answers [resolveResponse]. Pass [capturedRequests] to
/// observe endpoints/payloads.
AddressRepository buildFakeAddressRepository({
  List<Map<String, dynamic>> initialAddresses = const [],
  Map<String, dynamic> zoneInfo = kFakeZoneInfo,
  Map<String, dynamic> resolveResponse = const {
    'warehouse': 'Main Store - GR',
    'zone_name': 'Central Baghdad',
  },
  List<RequestOptions>? capturedRequests,
}) {
  final rows = [
    for (final row in initialAddresses) Map<String, dynamic>.of(row),
  ];
  var counter = 0;

  void clearOtherDefaults(String exceptName) {
    for (final row in rows) {
      if (row['name'] != exceptName) row['is_default'] = 0;
    }
  }

  final dio = buildFakeDio(
    (options) {
      Response<dynamic> envelope(dynamic message) => Response(
            requestOptions: options,
            statusCode: 200,
            data: {'message': message},
          );

      if (options.path.endsWith('address.list')) {
        final sorted = [...rows]..sort((a, b) {
            final aDefault = (a['is_default'] ?? 0) == 1 ? 1 : 0;
            final bDefault = (b['is_default'] ?? 0) == 1 ? 1 : 0;
            return bDefault.compareTo(aDefault);
          });
        return envelope(sorted);
      }
      if (options.path.endsWith('address.create')) {
        final data = options.data as Map<String, dynamic>;
        final row = <String, dynamic>{
          'name': 'ADDR-${++counter}',
          'label': data['label'],
          'address_line': data['address_line'],
          'city': data['city'],
          'lat': data['lat'],
          'lng': data['lng'],
          'is_default': data['is_default'] ?? 0,
        };
        rows.insert(0, row); // creation desc — newest first
        if (row['is_default'] == 1) clearOtherDefaults(row['name'] as String);
        return envelope({...row, ...zoneInfo});
      }
      if (options.path.endsWith('address.update')) {
        final data = options.data as Map<String, dynamic>;
        final row = rows.firstWhere((r) => r['name'] == data['name']);
        for (final field in ['label', 'address_line', 'city', 'lat', 'lng', 'is_default']) {
          if (data.containsKey(field)) row[field] = data[field];
        }
        if (row['is_default'] == 1) clearOtherDefaults(row['name'] as String);
        return envelope({...row, ...zoneInfo});
      }
      if (options.path.endsWith('address.delete')) {
        final data = options.data as Map<String, dynamic>;
        rows.removeWhere((r) => r['name'] == data['name']);
        return envelope({'ok': true});
      }
      if (options.path.endsWith('address.set_default')) {
        final data = options.data as Map<String, dynamic>;
        final row = rows.firstWhere((r) => r['name'] == data['name']);
        row['is_default'] = 1;
        clearOtherDefaults(row['name'] as String);
        return envelope({'ok': true});
      }
      if (options.path.endsWith('zone.resolve')) {
        return envelope(resolveResponse);
      }
      return envelope({'ok': true});
    },
    capturedRequests: capturedRequests,
  );
  return AddressRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

/// An [OrderRepository] backed by a fake server with sane defaults —
/// `place_order` answers `{order: SAL-ORD-2026-00001, status: Pending
/// Assignment}`, `my_orders` an empty first page, `detail` a minimal empty
/// order, `changes` an empty feed. Pass [overrides] to answer specific
/// endpoints yourself (return `null` to fall through to the defaults) and
/// [capturedRequests] to observe endpoints/payloads.
OrderRepository buildFakeOrderRepository({
  Response<dynamic>? Function(RequestOptions options)? overrides,
  List<RequestOptions>? capturedRequests,
}) {
  final dio = buildFakeDio(
    (options) {
      final overridden = overrides?.call(options);
      if (overridden != null) return overridden;

      Response<dynamic> envelope(dynamic message) => Response(
            requestOptions: options,
            statusCode: 200,
            data: {'message': message},
          );

      if (options.path.endsWith('order.place_order')) {
        return envelope({'order': 'SAL-ORD-2026-00001', 'status': 'Pending Assignment'});
      }
      if (options.path.endsWith('order.my_orders')) {
        return envelope({'items': <dynamic>[], 'page': 1, 'has_more': false});
      }
      if (options.path.endsWith('order.detail')) {
        return envelope({
          'name': options.queryParameters['name'] ?? 'SAL-ORD-2026-00001',
          'date': '2026-07-13',
          'status': 'Pending Assignment',
          'zone': 'Central Baghdad',
          'items': <dynamic>[],
          'totals': {'net_total': 0, 'grand_total': 0, 'currency': 'IQD'},
        });
      }
      if (options.path.endsWith('order.changes')) {
        return envelope({'changes': <dynamic>[]});
      }
      return envelope({'ok': true});
    },
    capturedRequests: capturedRequests,
  );
  return OrderRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

/// A [NotificationsRepository] backed by a fake server with sane defaults —
/// `notifications.list` answers one empty first page, `unread_count`
/// answers [unread], `mark_read` answers `{ok: true}`. Pass [overrides] to
/// answer specific endpoints yourself (return `null` to fall through) and
/// [capturedRequests] to observe endpoints/payloads.
NotificationsRepository buildFakeNotificationsRepository({
  int unread = 0,
  Response<dynamic>? Function(RequestOptions options)? overrides,
  List<RequestOptions>? capturedRequests,
}) {
  final dio = buildFakeDio(
    (options) {
      final overridden = overrides?.call(options);
      if (overridden != null) return overridden;

      Response<dynamic> envelope(dynamic message) => Response(
            requestOptions: options,
            statusCode: 200,
            data: {'message': message},
          );

      if (options.path.endsWith('notifications.list')) {
        return envelope({'items': <dynamic>[], 'page': 1, 'has_more': false});
      }
      if (options.path.endsWith('notifications.unread_count')) {
        return envelope({'count': unread});
      }
      return envelope({'ok': true});
    },
    capturedRequests: capturedRequests,
  );
  return NotificationsRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

/// A [ContentRepository] backed by a fake server: `get_app_config` answers
/// [appConfig] (or fails with 500 when [failConfig]), `get_onboarding`
/// answers [onboarding], `get_page` answers [pages] keyed by slug (404
/// when the slug is missing), `get_banners` an empty list. Pass
/// [capturedRequests] to observe endpoints/payloads.
ContentRepository buildFakeContentRepository({
  Map<String, dynamic> appConfig = const {},
  bool failConfig = false,
  List<Map<String, dynamic>> onboarding = const [],
  Map<String, Map<String, dynamic>> pages = const {},
  List<RequestOptions>? capturedRequests,
}) {
  final dio = buildFakeDio(
    (options) {
      Response<dynamic> envelope(dynamic message, {int status = 200}) =>
          Response(
            requestOptions: options,
            statusCode: status,
            data: {'message': message},
          );

      if (options.path.endsWith('content.get_app_config')) {
        if (failConfig) return envelope({'message': 'down'}, status: 500);
        return envelope(appConfig);
      }
      if (options.path.endsWith('content.get_onboarding')) {
        return envelope(onboarding);
      }
      if (options.path.endsWith('content.get_page')) {
        final slug = (options.data as Map<String, dynamic>?)?['slug'] as String?;
        final page = slug == null ? null : pages[slug];
        if (page == null) return envelope({'message': 'not found'}, status: 404);
        return envelope(page);
      }
      return envelope(<dynamic>[]); // banners
    },
    capturedRequests: capturedRequests,
  );
  return ContentRepository(
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
  );
}

/// A [UrlOpener] fake that records every URL passed to [open] and answers
/// with the settable [result] — no platform channel involved.
class FakeUrlOpener implements UrlOpener {
  final List<String> opened = [];
  bool result = true;

  @override
  Future<bool> open(String url) async {
    opened.add(url);
    return result;
  }
}

/// Provider list for Home-related widget tests. Defaults every section to
/// an empty-but-successful fetch and fresh, guest/in-memory stores, so
/// `wrapPage(const HomePage(), providers: homeTestProviders())` "just
/// works" — pass overrides to control an individual section's data,
/// failure, or store behaviour per test.
List<SingleChildWidget> homeTestProviders({
  CatalogRepository? catalogRepository,
  ContentRepository? contentRepository,
  SearchRepository? searchRepository,
  SessionStore? sessionStore,
  FavouritesStore? favouritesStore,
  CartStore? cartStore,
  AddressRepository? addressRepository,
  AddressStore? addressStore,
  LocationService? locationService,
  OrderRepository? orderRepository,
  NotificationsRepository? notificationsRepository,
  NotificationsStore? notificationsStore,
  AppConfigStore? appConfigStore,
  UrlOpener? urlOpener,
  SettingsStore? settingsStore,
  OrderFeedbackService? orderFeedbackService,
}) {
  ApiClient emptySuccessClient() => ApiClient(
        dio: buildFakeDio(
          (options) => Response(requestOptions: options, statusCode: 200, data: {'message': <dynamic>[]}),
        ),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      );

  final resolvedSession = sessionStore ?? buildGuestSessionStore();
  final resolvedAddressRepository =
      addressRepository ?? buildFakeAddressRepository();
  final resolvedNotificationsRepository =
      notificationsRepository ?? buildFakeNotificationsRepository();

  return [
    // Mirrors app.dart's Provider<ApiClient> so widgets that read it directly
    // (e.g. ProfileTab's policy-URL fallback) resolve in tests too.
    Provider<ApiClient>.value(value: emptySuccessClient()),
    Provider<CatalogRepository>.value(value: catalogRepository ?? CatalogRepository(emptySuccessClient())),
    Provider<ContentRepository>.value(value: contentRepository ?? ContentRepository(emptySuccessClient())),
    Provider<SearchRepository>.value(value: searchRepository ?? SearchRepository(emptySuccessClient())),
    ChangeNotifierProvider<SessionStore>.value(value: resolvedSession),
    ChangeNotifierProvider<FavouritesStore>.value(
      value: favouritesStore ??
          FavouritesStore(repository: buildFakeWishlistRepository(), session: resolvedSession),
    ),
    ChangeNotifierProvider<CartStore>.value(
      value: cartStore ?? CartStore(repository: buildFakeCartRepository(), session: resolvedSession),
    ),
    Provider<AddressRepository>.value(value: resolvedAddressRepository),
    // Deliberately NOT hydrated by default (nobody calls restore/refresh),
    // so an authed test session never pops the no-address nudge sheet over
    // whatever the test is actually exercising.
    ChangeNotifierProvider<AddressStore>.value(
      value: addressStore ??
          AddressStore(repository: resolvedAddressRepository, session: resolvedSession),
    ),
    Provider<LocationService>.value(value: locationService ?? FakeLocationService()),
    Provider<UrlOpener>.value(value: urlOpener ?? FakeUrlOpener()),
    Provider<OrderRepository>.value(value: orderRepository ?? buildFakeOrderRepository()),
    Provider<NotificationsRepository>.value(
        value: resolvedNotificationsRepository),
    // Deliberately NOT hydrated by default (nobody calls restore/refresh),
    // so the badge starts at 0 unless a test hydrates its own store.
    ChangeNotifierProvider<NotificationsStore>.value(
      value: notificationsStore ??
          NotificationsStore(
            repository: resolvedNotificationsRepository,
            session: resolvedSession,
          ),
    ),
    // Deliberately NOT loaded by default — config stays at the bundled
    // defaults unless a test loads its own store.
    ChangeNotifierProvider<AppConfigStore>.value(
      value: appConfigStore ??
          AppConfigStore(repository: buildFakeContentRepository()),
    ),
    ChangeNotifierProvider<SettingsStore>.value(
      value: settingsStore ?? SettingsStore(),
    ),
    Provider<OrderFeedbackService>.value(
      value: orderFeedbackService ?? const NoopOrderFeedbackService(),
    ),
  ];
}
