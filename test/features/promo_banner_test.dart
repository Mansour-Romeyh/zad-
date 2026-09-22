import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/services/url_opener.dart';
import 'package:zad/features/category/category_browser_page.dart';
import 'package:zad/features/home/widgets/promo_banner.dart';
import 'package:zad/features/product/banner_items_page.dart';
import 'package:zad/l10n/app_localizations.dart';
import 'package:zad/models/app_banner.dart';

import '../helpers.dart';

/// Builds [PromoBanner] with [count] image-less banners (each renders the
/// bundled placeholder, so no network is touched) inside a bare app shell.
Widget _bannerApp(int count) => MaterialApp(
      home: Scaffold(
        body: PromoBanner(
          banners: [
            for (var i = 0; i < count; i++)
              AppBannerModel(imageUrl: null, title: 'Banner $i'),
          ],
        ),
      ),
    );

/// Reads the live page offset of the carousel's [PageView] controller.
double _currentPage(WidgetTester tester) =>
    tester.widget<PageView>(find.byType(PageView)).controller!.page!;

void main() {
  testWidgets('a single banner renders a static card with no PageView', (
    tester,
  ) async {
    await tester.pumpWidget(_bannerApp(1));
    await tester.pump();

    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('multiple banners auto-advance one page every 5 seconds', (
    tester,
  ) async {
    await tester.pumpWidget(_bannerApp(3));
    await tester.pump();

    final startPage = _currentPage(tester);

    // Nothing moves before the 5s interval elapses.
    await tester.pump(const Duration(seconds: 4));
    expect(_currentPage(tester), startPage);

    // The timer fires at 5s and kicks off the slide; let it settle.
    await tester.pump(const Duration(seconds: 1)); // fires the periodic timer
    await tester.pump(const Duration(milliseconds: 500)); // finishes the anim
    expect(_currentPage(tester), moreOrLessEquals(startPage + 1, epsilon: 0.01));

    // A second interval advances one more page — it keeps looping.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_currentPage(tester), moreOrLessEquals(startPage + 2, epsilon: 0.01));

    // Dispose the tree so the periodic timer is cancelled before teardown.
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // A single banner with the given link, mounted with route stubs that echo
  // their pushed arguments as Text, plus a Provider<UrlOpener> for URL taps.
  Widget linkedBannerApp(AppBannerModel banner, {UrlOpener? opener}) {
    Widget stub(String label) => Builder(
          builder: (context) {
            final args = ModalRoute.of(context)!.settings.arguments;
            final detail = switch (args) {
              CategoryBrowserArgs a => a.initialGroupId,
              BannerItemsArgs a => '${a.title}|${a.itemCodes.join(",")}',
              _ => args?.toString(),
            };
            return Scaffold(body: Text('$label:$detail'));
          },
        );
    return Provider<UrlOpener>.value(
      value: opener ?? FakeUrlOpener(),
      child: MaterialApp(
        // AppLocalizations.of(context) is used on the URL-error path
        // (_BannerCard._dispatch), so this stub app needs the same
        // delegates/locales the real app registers in app.dart.
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: PromoBanner(banners: [banner])),
        routes: {
          '/product': (_) => stub('product'),
          '/categories': (_) => stub('categories'),
          '/banner-items': (_) => stub('banner-items'),
        },
      ),
    );
  }

  testWidgets('tapping an Item banner routes to /product with the item code', (
    tester,
  ) async {
    await tester.pumpWidget(linkedBannerApp(
      const AppBannerModel(title: 'B', linkType: 'Item', linkValue: 'ITEM-1'),
    ));
    await tester.pump();

    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(find.text('product:ITEM-1'), findsOneWidget);
  });

  testWidgets('tapping an Item Group banner routes to /categories with the id', (
    tester,
  ) async {
    await tester.pumpWidget(linkedBannerApp(
      const AppBannerModel(
          title: 'B', linkType: 'Item Group', linkValue: 'Products'),
    ));
    await tester.pump();

    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(find.text('categories:Products'), findsOneWidget);
  });

  testWidgets(
      'tapping an Items banner routes to /banner-items with codes and title',
      (tester) async {
    await tester.pumpWidget(linkedBannerApp(
      const AppBannerModel(
        title: 'Ramadan Picks',
        linkType: 'Items',
        linkItems: ['A', 'B', 'C'],
      ),
    ));
    await tester.pump();

    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(find.text('banner-items:Ramadan Picks|A,B,C'), findsOneWidget);
  });

  testWidgets('tapping a URL banner hands the url to UrlOpener', (tester) async {
    final opener = FakeUrlOpener();
    await tester.pumpWidget(linkedBannerApp(
      const AppBannerModel(
          title: 'B', linkType: 'URL', linkValue: 'https://zad.example'),
      opener: opener,
    ));
    await tester.pump();

    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(opener.opened, ['https://zad.example']);
  });

  testWidgets('a URL that fails to open shows an error snackbar', (tester) async {
    final opener = FakeUrlOpener()..result = false;
    await tester.pumpWidget(linkedBannerApp(
      const AppBannerModel(
          title: 'B', linkType: 'URL', linkValue: 'https://zad.example'),
      opener: opener,
    ));
    await tester.pump();

    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong'), findsOneWidget);
  });

  testWidgets('an unlinked banner is not tappable (no GestureDetector added)', (
    tester,
  ) async {
    await tester.pumpWidget(linkedBannerApp(
      const AppBannerModel(title: 'B', linkType: 'None', linkValue: null),
    ));
    await tester.pump();

    // No route stub content ever appears; nothing to assert beyond a clean tap.
    await tester.tap(find.byType(PromoBanner));
    await tester.pumpAndSettle();

    expect(find.text('product:null'), findsNothing);
    expect(find.text('categories:null'), findsNothing);
  });
}
