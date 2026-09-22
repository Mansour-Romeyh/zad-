import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/data/content_repository.dart';
import 'package:zad/features/onboarding/onboarding_page.dart';

import '../helpers.dart';
import '../support/fake_dio.dart';
import '../support/fake_secure_storage.dart';

Widget _app({ContentRepository? contentRepository}) => wrapPage(
      const OnboardingPage(),
      providers: [
        Provider<ContentRepository>.value(
          // Default: the API fails → the bundled 3 pages (the pre-Task-10
          // behaviour every legacy expectation below relies on).
          value: contentRepository ?? _failingContentRepository(),
        ),
      ],
      routes: {
        '/home': (_) => const Scaffold(body: Text('HOME_MARKER')),
      },
    );

ContentRepository _failingContentRepository() => ContentRepository(
      ApiClient(
        dio: buildNetworkErrorDio(),
        tokenStore: TokenStore(storage: FakeSecureStorage()),
        baseUrl: 'http://test.local',
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('FAB advances through all 3 pages then lands home',
      (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('Buy Groceries Easily with Us'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward).last); // FAB
    await tester.pumpAndSettle();
    expect(find.text('Fresh Products Every Day'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward).last);
    await tester.pumpAndSettle();
    expect(find.text('Best Deals, Fast Delivery'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_forward).last);
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kOnboardingDoneKey), isTrue);
  });

  testWidgets('swiping the image area changes the page dots/text',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.fling(find.byType(PageView), const Offset(-320, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text('Fresh Products Every Day'), findsOneWidget);
  });

  testWidgets('skip persists the flag and lands home', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('HOME_MARKER'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kOnboardingDoneKey), isTrue);
  });

  testWidgets('backend slides replace the bundled pages when the API answers',
      (tester) async {
    await tester.pumpWidget(
      _app(
        contentRepository: buildFakeContentRepository(onboarding: const [
          {'title': 'أهلاً بك في زاد', 'subtitle': 'مقاضيك بضغطة زر', 'image': '/files/s1.png', 'sequence': 1},
          {'title': 'توصيل خلال ساعة', 'subtitle': 'أينما كنت في بغداد', 'image': '/files/s2.png', 'sequence': 2},
        ]),
      ),
    );
    // Bundled copy renders immediately (no blank loading state)...
    expect(find.text('Buy Groceries Easily with Us'), findsOneWidget);

    // ...and the fetched slides take over once the API answers.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('أهلاً بك في زاد'), findsOneWidget);
    expect(find.text('مقاضيك بضغطة زر'), findsOneWidget);
    expect(find.text('Buy Groceries Easily with Us'), findsNothing);

    // Two remote slides → the FAB finishes after the second page. These slides
    // carry image URLs, so RemoteImage sits on its (perpetual) loading spinner
    // while the fake network never resolves — pumpAndSettle would time out on
    // it. Advance the page/route with bounded pumps instead.
    await tester.tap(find.byIcon(Icons.arrow_forward).last);
    await tester.pump(); // kick off the page transition
    await tester.pump(const Duration(milliseconds: 600)); // let it finish
    expect(find.text('توصيل خلال ساعة'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_forward).last);
    await tester.pump(); // kick off the replace-to-/home navigation
    await tester.pump(const Duration(milliseconds: 600)); // let the route settle
    expect(find.text('HOME_MARKER'), findsOneWidget);
  });

  testWidgets('an empty backend answer keeps the bundled pages', (tester) async {
    await tester.pumpWidget(
      _app(contentRepository: buildFakeContentRepository(onboarding: const [])),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Buy Groceries Easily with Us'), findsOneWidget);
  });

  testWidgets('API failure keeps the bundled 3 pages (fallback)', (tester) async {
    await tester.pumpWidget(_app()); // failing repository
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(find.text('Buy Groceries Easily with Us'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-320, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text('Fresh Products Every Day'), findsOneWidget);
  });
}
