import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/core/stores/app_config_store.dart';
import 'package:zad/data/content_repository.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

const _configJson = {
  'splash_image': '/files/splash.png',
  'splash_bg_color': '#EFF9F0',
  'splash_duration_sec': 2,
  'app_min_version': '1.0.0',
  'maintenance_mode': false,
  'support_phone': '+9647700000000',
};

ContentRepository _networkErrorRepository() => ContentRepository(
      ApiClient(
        dio: buildNetworkErrorDio(),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppConfigStore.load', () {
    test('a successful fetch applies the config and caches it as last-good', () async {
      final store = AppConfigStore(
        repository: buildFakeContentRepository(appConfig: _configJson),
      );

      await store.load();

      expect(store.loaded, isTrue);
      expect(store.config.splashBgColor, '#EFF9F0');
      expect(store.config.splashDurationSec, 2);
      expect(store.config.supportPhone, '+9647700000000');
      expect(store.config.splashImage, 'http://test.local/files/splash.png');
      expect(store.maintenanceMode, isFalse);

      final prefs = await SharedPreferences.getInstance();
      final cached =
          jsonDecode(prefs.getString(kAppConfigCacheKey)!) as Map<String, dynamic>;
      expect(cached['support_phone'], '+9647700000000');
      expect(cached['splash_image'], 'http://test.local/files/splash.png');
    });

    test('a failed fetch falls back to the cached last-good config', () async {
      SharedPreferences.setMockInitialValues({
        kAppConfigCacheKey: jsonEncode({
          'splash_bg_color': '#123456',
          'splash_duration_sec': 4,
          'maintenance_mode': false,
          'support_phone': '+9647711111111',
        }),
      });
      final store = AppConfigStore(repository: _networkErrorRepository());

      await store.load();

      expect(store.loaded, isTrue);
      expect(store.config.splashBgColor, '#123456');
      expect(store.config.splashDurationSec, 4);
      expect(store.config.supportPhone, '+9647711111111');
    });

    test('a failed fetch with no cache lands on the bundled defaults', () async {
      final store = AppConfigStore(repository: _networkErrorRepository());

      await store.load();

      expect(store.loaded, isTrue);
      expect(store.config.splashBgColor, isNull);
      expect(store.config.splashDurationSec, isNull);
      expect(store.maintenanceMode, isFalse);
    });

    test('a corrupt cache reads as no cache (bundled defaults)', () async {
      SharedPreferences.setMockInitialValues({kAppConfigCacheKey: 'not json'});
      final store = AppConfigStore(repository: _networkErrorRepository());

      await store.load();

      expect(store.loaded, isTrue);
      expect(store.config.splashBgColor, isNull);
    });

    test('a hung fetch is bounded by fetchTimeout (falls back)', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            // Never resolves — only the store's timeout can end this.
          },
        ),
      );
      final store = AppConfigStore(
        repository: ContentRepository(
          ApiClient(
            dio: dio,
            tokenStore: TokenStore(storage: FakeSecureStorage()),
            baseUrl: 'http://test.local',
          ),
        ),
        fetchTimeout: const Duration(milliseconds: 50),
      );

      await store.load(); // must resolve despite the hung request

      expect(store.loaded, isTrue);
      expect(store.config.splashBgColor, isNull); // bundled defaults
    });
  });

  group('AppConfigStore.refresh (maintenance retry)', () {
    test('only a successful fresh fetch changes state', () async {
      // Boot fetched maintenance=true.
      final store = AppConfigStore(
        repository: buildFakeContentRepository(
          appConfig: {..._configJson, 'maintenance_mode': true},
        ),
      );
      await store.load();
      expect(store.maintenanceMode, isTrue);

      // Retry against a dead network: the gate must stay up.
      final offlineStore = AppConfigStore(repository: _networkErrorRepository());
      await offlineStore.load(); // cached maintenance=true from the boot above
      expect(offlineStore.maintenanceMode, isTrue,
          reason: 'last-good cache carries the maintenance flag');
      expect(await offlineStore.refresh(), isFalse);
      expect(offlineStore.maintenanceMode, isTrue);

      // Retry against a recovered backend clears it.
      final recovered = AppConfigStore(
        repository: buildFakeContentRepository(appConfig: _configJson),
      );
      await recovered.load();
      expect(await recovered.refresh(), isTrue);
      expect(recovered.maintenanceMode, isFalse);
    });
  });
}
