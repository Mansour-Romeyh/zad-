import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/home/home_page.dart';
import 'package:zad/features/home/widgets/category_grid.dart';
import 'package:zad/features/home/widgets/promo_banner.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

final _categoriesJson = List.generate(
  8,
  (i) => {'name': 'cat-$i', 'label': 'Category $i', 'item_count': i},
);

ApiClient _clientWith({required List<dynamic> categories, required List<dynamic> banners}) {
  return ApiClient(
    dio: buildFakeDio((options) {
      if (options.path.endsWith('get_categories')) return _envelope(options, categories);
      if (options.path.endsWith('home.get_banners')) return _envelope(options, banners);
      return _envelope(options, <dynamic>[]); // best items: unused here
    }),
    tokenStore: TokenStore(storage: FakeSecureStorage()),
    baseUrl: 'http://test.local',
  );
}

void main() {
  testWidgets('home shows the category grid and promo banner from backend data', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final client = _clientWith(
      categories: _categoriesJson,
      banners: [
        {'image': null, 'title': 'World Food Festival, Bring the world to your Kitchen!'},
      ],
    );

    await tester.pumpWidget(
      wrapPage(
        const HomePage(),
        providers: homeTestProviders(
          catalogRepository: CatalogRepository(client),
          contentRepository: ContentRepository(client),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Shop By Category'), findsOneWidget);
    expect(find.text('See All'), findsWidgets);
    for (var i = 0; i < 8; i++) {
      expect(find.text('Category $i'), findsOneWidget);
    }
    expect(find.byType(CategoryGrid), findsOneWidget);
    // The promo banner shows the image only — no overlaid headline, no
    // "Shop Now" CTA.
    expect(find.byType(PromoBanner), findsOneWidget);
    expect(
      find.text('World Food Festival, Bring the world to your Kitchen!'),
      findsNothing,
    );
    expect(find.text('Shop Now'), findsNothing);
  });
}
