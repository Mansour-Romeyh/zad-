import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/features/auth/widgets/zad_otp_field.dart';

import '../../../helpers.dart';

Widget _harness(TextEditingController controller, {VoidCallback? onCompleted}) => wrapPage(
      Scaffold(
        body: Form(
          child: ZadOtpField(controller: controller, onCompleted: onCompleted),
        ),
      ),
    );

void main() {
  testWidgets('renders kOtpLength boxes', (tester) async {
    await tester.pumpWidget(_harness(TextEditingController()));
    expect(find.byType(TextField), findsNWidgets(kOtpLength));
  });

  testWidgets('entering the full code distributes across boxes, syncs the '
      'controller, and fires onCompleted once', (tester) async {
    final controller = TextEditingController();
    var completed = 0;
    await tester.pumpWidget(_harness(controller, onCompleted: () => completed++));

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pump();

    expect(controller.text, '1234');
    for (var i = 0; i < kOtpLength; i++) {
      expect(tester.widget<TextField>(find.byType(TextField).at(i)).controller!.text, '${i + 1}');
    }
    expect(completed, 1);
  });

  testWidgets('non-digits are filtered; a mixed string still yields the code', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_harness(controller));

    await tester.enterText(find.byType(TextField).first, '12ab34');
    await tester.pump();

    expect(controller.text, '1234');
  });

  testWidgets('typing a digit advances focus to the next box', (tester) async {
    await tester.pumpWidget(_harness(TextEditingController()));

    await tester.enterText(find.byType(TextField).at(0), '7');
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField).at(1)).focusNode!.hasFocus, isTrue);
  });

  testWidgets('backspace on an empty box clears and focuses the previous box', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_harness(controller));

    // Fill box 0 -> focus advances to the empty box 1.
    await tester.enterText(find.byType(TextField).at(0), '7');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text, '');
    expect(tester.widget<TextField>(find.byType(TextField).at(0)).focusNode!.hasFocus, isTrue);
    expect(controller.text, '');
  });

  testWidgets('digits stay left-to-right under an ar locale (forced LTR)', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(wrapPage(
      Scaffold(body: Form(child: ZadOtpField(controller: controller))),
      locale: const Locale('ar'),
    ));

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pump();

    // Box order maps to code order, and the boxes sit under a forced-LTR wrap.
    expect(controller.text, '1234');
    final dir = tester.widget<Directionality>(
      find.ancestor(of: find.byType(TextField).first, matching: find.byType(Directionality)).first,
    );
    expect(dir.textDirection, TextDirection.ltr);
  });
}
