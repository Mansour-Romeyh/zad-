import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/auth/widgets/zad_text_field.dart';
import 'package:zad/l10n/app_localizations.dart';

/// The show/hide toggle is owned by [ZadTextField] so every password input
/// (login, register, reset, change-password) gets it for free. It appears
/// only for obscured fields and flips the field's obscuring on tap.
void main() {
  Widget host(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      );

  bool obscured(WidgetTester tester) =>
      tester.widget<EditableText>(find.byType(EditableText)).obscureText;

  testWidgets('a password field starts obscured and the toggle reveals it',
      (tester) async {
    await tester.pumpWidget(host(
      ZadTextField(
        controller: TextEditingController(text: 'secret'),
        hintText: 'Password',
        obscureText: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passwordVisibilityToggle')), findsOneWidget);
    expect(obscured(tester), isTrue);

    await tester.tap(find.byKey(const Key('passwordVisibilityToggle')));
    await tester.pump();
    expect(obscured(tester), isFalse); // now visible

    await tester.tap(find.byKey(const Key('passwordVisibilityToggle')));
    await tester.pump();
    expect(obscured(tester), isTrue); // hidden again
  });

  testWidgets('a non-obscured field shows no toggle', (tester) async {
    await tester.pumpWidget(host(
      ZadTextField(
        controller: TextEditingController(),
        hintText: 'Full name',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('passwordVisibilityToggle')), findsNothing);
    expect(obscured(tester), isFalse);
  });
}
