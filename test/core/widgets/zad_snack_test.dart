import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/core/widgets/zad_snack.dart';

void main() {
  testWidgets('shows the message with a variant icon', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: zadTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showZadSnack(context, 'Saved', variant: ZadSnackVariant.success),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('go'));
    await tester.pump(); // start the snackbar animation
    await tester.pump(const Duration(milliseconds: 300)); // reveal floating snackbar
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byKey(const Key('zadSnack')), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });
}
