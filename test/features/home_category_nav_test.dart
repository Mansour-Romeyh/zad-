import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/home/home_page.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

ApiClient _client() => ApiClient(
  dio: buildFakeDio((options) {
    if (options.path.endsWith('get_categories')) {
      return _envelope(options, [
        {'name': 'cat-1', 'label': 'Fruits', 'item_count': 3},
      ]);
    }
    return _envelope(options, <dynamic>[]);
  }),
  tokenStore: TokenStore(storage: FakeSecureStorage()),
  baseUrl: 'http://test.local',
);

void main() {
  testWidgets('tapping a home category tile opens the category browser', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = _client();
    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
        routes: {
          '/categories': (_) => const Scaffold(body: Text('BROWSER_MARKER')),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Fruits')); // the category tile label
    await tester.pumpAndSettle();

    expect(find.text('BROWSER_MARKER'), findsOneWidget);
  });
}
