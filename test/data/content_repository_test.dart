import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/content_repository.dart';

import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) {
  return Response(requestOptions: options, statusCode: 200, data: {'message': message});
}

ApiClient _client(Dio dio) =>
    ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local');

void main() {
  group('ContentRepository', () {
    test('getOnboarding calls content.get_onboarding via GET and maps slides', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, [
          {'title': 'Welcome', 'subtitle': 'Get started', 'image': '/files/o1.png', 'sequence': 1},
        ]),
        capturedRequests: requests,
      );
      final repo = ContentRepository(_client(dio));

      final slides = await repo.getOnboarding();

      expect(requests.single.method, 'GET');
      expect(requests.single.path, '/api/method/grocery.api.content.get_onboarding');
      expect(slides.single.title, 'Welcome');
      expect(slides.single.imageUrl, 'http://test.local/files/o1.png');
    });

    test('getAppConfig calls content.get_app_config via GET and maps config', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, {
          'splash_image': '/files/splash.png',
          'splash_bg_color': '#5AC268',
          'splash_duration_sec': 2,
          'app_min_version': '1.0.0',
          'maintenance_mode': false,
        }),
        capturedRequests: requests,
      );
      final repo = ContentRepository(_client(dio));

      final config = await repo.getAppConfig();

      expect(requests.single.path, '/api/method/grocery.api.content.get_app_config');
      expect(config.splashDurationSec, 2);
      expect(config.splashImage, 'http://test.local/files/splash.png');
    });

    test('getBanners calls home.get_banners via GET and maps banners', () async {
      final requests = <RequestOptions>[];
      final dio = buildFakeDio(
        (options) => _envelope(options, [
          {'image': '/files/b1.png', 'title': 'Sale', 'link_type': 'category', 'link_value': 'Dairy'},
        ]),
        capturedRequests: requests,
      );
      final repo = ContentRepository(_client(dio));

      final banners = await repo.getBanners();

      expect(requests.single.method, 'GET');
      expect(requests.single.path, '/api/method/grocery.api.home.get_banners');
      expect(banners.single.title, 'Sale');
      expect(banners.single.imageUrl, 'http://test.local/files/b1.png');
    });
  });
}
