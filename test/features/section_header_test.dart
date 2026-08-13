import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/home/widgets/section_header.dart';

import '../helpers.dart';

void main() {
  testWidgets('tapping See All invokes the callback', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrapPage(SectionHeader(title: 'Best Deal', onSeeAll: () => tapped++)),
    );

    await tester.tap(find.text('See All'));
    expect(tapped, 1);
  });

  testWidgets('See All is hidden when no callback is provided', (tester) async {
    await tester.pumpWidget(wrapPage(const SectionHeader(title: 'Best Deal')));

    expect(find.text('Best Deal'), findsOneWidget);
    expect(find.text('See All'), findsNothing);
  });
}
