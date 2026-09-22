import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/stores/cart_store.dart';
import 'package:zad/core/stores/favourites_store.dart';
import 'package:zad/data/catalog_repository.dart';
import 'package:zad/features/product/banner_items_page.dart';
import 'package:zad/l10n/app_localizations.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

Map<String, dynamic> _item(String code, String name) => {
      'item_code': code,
      'item_name': name,
      'image': null,
      'price_per_uom': 1500,
      'uom': '1 kg',
      'in_stock': true,
    };

CatalogRepository _repoWith(Response<dynamic> Function(RequestOptions) handler) {
  return CatalogRepository(
    ApiClient(
      dio: buildFakeDio(handler),
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    ),
  );
}

// Mounts BannerItemsPage behind a route so ModalRoute.arguments carries the
// BannerItemsArgs (codes + title) the page reads.
Widget _app(CatalogRepository repo, BannerItemsArgs args) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      onGenerateRoute: (_) => MaterialPageRoute(
        settings: RouteSettings(arguments: args),
        builder: (_) => MultiProvider(
          providers: [
            Provider<CatalogRepository>.value(value: repo),
            ChangeNotifierProvider<FavouritesStore>(
              create: (_) =>
                  FavouritesStore(repository: buildFakeWishlistRepository()),
            ),
            ChangeNotifierProvider<CartStore>(
              create: (_) => CartStore(
                repository: buildFakeCartRepository(),
                session: buildGuestSessionStore(),
              ),
            ),
          ],
          child: const BannerItemsPage(),
        ),
      ),
    );

void main() {
  testWidgets('requests the selected codes and renders them under the banner title',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    List<String>? requested;
    final repo = _repoWith((options) {
      requested = ((options.data as Map<String, dynamic>)['item_codes'] as List)
          .cast<String>();
      return _envelope(options, {
        'items': [_item('ITEM-2', 'Beta'), _item('ITEM-1', 'Alpha')],
        'page': 1,
        'has_more': false,
      });
    });

    await tester.pumpWidget(
      _app(repo, const BannerItemsArgs(['ITEM-2', 'ITEM-1'], 'Ramadan Picks')),
    );
    await tester.pumpAndSettle();

    // The banner's own title heads the screen.
    expect(find.text('Ramadan Picks'), findsOneWidget);
    // Exactly the selected codes were requested, in the given order.
    expect(requested, ['ITEM-2', 'ITEM-1']);
    // Both selected products render.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('an empty result shows the banner empty message', (tester) async {
    final repo = _repoWith(
      (options) => _envelope(options, {
        'items': <dynamic>[],
        'page': 1,
        'has_more': false,
      }),
    );

    await tester.pumpWidget(
      _app(repo, const BannerItemsArgs(['GONE'], 'Picks')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text("These items aren't available right now"),
      findsOneWidget,
    );
  });
}
