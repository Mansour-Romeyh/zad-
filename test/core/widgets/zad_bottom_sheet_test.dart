import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/core/widgets/zad_bottom_sheet.dart';

void main() {
  testWidgets('shows grabber + title and returns the builder result', (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      theme: zadTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showZadSheet<String>(
                  context,
                  title: 'Sort by',
                  builder: (sheetContext) => ElevatedButton(
                    key: const Key('pick'),
                    onPressed: () => Navigator.pop(sheetContext, 'price'),
                    child: const Text('Price'),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zadSheetHandle')), findsOneWidget);
    expect(find.text('Sort by'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pick')));
    await tester.pumpAndSettle();
    expect(result, 'price');
  });
}
