import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/constants.dart';
import 'package:zad/core/theme.dart';

void main() {
  test('color tokens match the Figma design', () {
    expect(ZadColors.primary, const Color(0xFF5AC268));
    expect(ZadColors.ink, const Color(0xFF101811));
    expect(ZadColors.paleGreen, const Color(0xFFEFF9F0));
    expect(ZadColors.surface, const Color(0xFFFAFAFA));
    expect(ZadColors.muted, const Color(0xFFA9AFAA));
  });

  test('theme uses Poppins with Cairo fallback on white scaffold', () {
    final theme = zadTheme();
    expect(theme.scaffoldBackgroundColor, Colors.white);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Poppins');
    expect(theme.textTheme.bodyMedium?.fontFamilyFallback, contains('Cairo'));
    expect(theme.colorScheme.primary, ZadColors.primary);
  });

  test('formatPrice renders IQD with grouping and no decimals', () {
    expect(formatPrice(1500), 'IQD 1,500');
    expect(formatPrice(9), 'IQD 9');
    expect(formatPrice(12.6), 'IQD 13'); // rounds to whole IQD
  });

  test('formatPrice renders Arabic-locale IQD with trailing symbol', () {
    expect(formatPrice(1500, 'ar'), '1,500 د.ع');
    expect(formatPrice(9, 'ar'), '9 د.ع');
  });

  test('semantic + popup tokens exist and are distinct', () {
    expect(ZadColors.danger, isNot(ZadColors.primary));
    expect(ZadColors.success, isNot(ZadColors.info));
    expect(ZadRadii.dialog, 28);
    expect(ZadElevation.dialog, greaterThan(0));
    expect(ZadDurations.popupIn.inMilliseconds, greaterThan(0));
  });

  test('theme defines dialog + snackbar themes on brand', () {
    final t = zadTheme();
    expect(t.dialogTheme.backgroundColor, ZadColors.white);
    expect(t.snackBarTheme.behavior, SnackBarBehavior.floating);
  });
}
