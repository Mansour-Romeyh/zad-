import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/theme.dart';
import 'package:zad/core/widgets/zad_dialog.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester,
    void Function(BuildContext) onTap,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: zadTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => onTap(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('confirm resolves true on primary, false on secondary', (
    tester,
  ) async {
    bool? result;
    await pumpHost(tester, (context) async {
      result = await showZadConfirm(
        context,
        title: 'Clear basket?',
        message: 'Removes all items.',
        confirmLabel: 'Clear',
        cancelLabel: 'Cancel',
        icon: Icons.delete_outline,
        destructive: true,
      );
    });

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Clear basket?'), findsOneWidget);

    // Destructive primary is danger-coloured.
    final btn = tester.widget<ElevatedButton>(
      find.byKey(const Key('zadDialogPrimary')),
    );
    final bg = btn.style!.backgroundColor!.resolve({});
    expect(bg, ZadColors.danger);

    await tester.tap(find.byKey(const Key('zadDialogPrimary')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('confirm resolves false on secondary tap', (tester) async {
    bool? result;
    await pumpHost(tester, (context) async {
      result = await showZadConfirm(
        context,
        title: 'T',
        message: 'M',
        confirmLabel: 'Yes',
        cancelLabel: 'No',
      );
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('zadDialogSecondary')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });

  testWidgets('showZadDialog returns the tapped action value', (tester) async {
    String? picked;
    await pumpHost(tester, (context) async {
      picked = await showZadDialog<String>(
        context,
        title: 'Pick',
        contentBuilder: (_) => const Text('body'),
        actions: [
          TextButton(
            key: const Key('optA'),
            onPressed: () => Navigator.pop(context, 'A'),
            child: const Text('A'),
          ),
        ],
      );
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('body'), findsOneWidget);
    await tester.tap(find.byKey(const Key('optA')));
    await tester.pumpAndSettle();
    expect(picked, 'A');
  });

  testWidgets('zadDialogPrimaryAction with null onPressed renders disabled', (
    tester,
  ) async {
    await pumpHost(tester, (context) async {
      await showZadDialog<void>(
        context,
        title: 'Gate',
        contentBuilder: (_) => const Text('body'),
        actions: [zadDialogPrimaryAction(label: 'Go', onPressed: null)],
      );
    });
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final btn = tester.widget<ElevatedButton>(
      find.byKey(const Key('zadDialogPrimary')),
    );
    expect(btn.enabled, isFalse);
  });

  testWidgets(
    'zadDialogPrimaryAction with non-null onPressed renders enabled',
    (tester) async {
      await pumpHost(tester, (context) async {
        await showZadDialog<void>(
          context,
          title: 'Gate',
          contentBuilder: (_) => const Text('body'),
          actions: [zadDialogPrimaryAction(label: 'Go', onPressed: () {})],
        );
      });
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final btn = tester.widget<ElevatedButton>(
        find.byKey(const Key('zadDialogPrimary')),
      );
      expect(btn.enabled, isTrue);
    },
  );
}
