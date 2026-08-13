import 'package:flutter/material.dart';
import 'constants.dart';

abstract final class ZadColors {
  static const primary = Color(0xFF5AC268);
  static const ink = Color(0xFF101811);
  static const paleGreen = Color(0xFFEFF9F0);
  static const surface = Color(0xFFFAFAFA);
  static const muted = Color(0xFFA9AFAA);

  /// Pure white — text/icons on [primary] fills and elevated bar surfaces.
  static const white = Color(0xFFFFFFFF);

  /// Active favourite hearts (was the raw `Colors.redAccent` literal).
  static const heart = Color(0xFFFF5252);

  /// Inline error banner background/text (Material error-tone pair).
  static const errorSurface = Color(0xFFFDECEA);
  static const errorText = Color(0xFFB3261E);

  /// Destructive-action fill (Clear/Delete/Logout) — the app's error red.
  static const danger = Color(0xFFB3261E);

  /// Snackbar variant accents.
  static const success = Color(0xFF2E7D32);
  static const info = Color(0xFF1565C0);
  static const warning = Color(0xFFB26A00);

  /// Dialog/sheet barrier scrim.
  static final scrim = Colors.black.withValues(alpha: 0.45);
}

ThemeData zadTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: ZadColors.primary,
      primary: ZadColors.primary,
      surface: Colors.white,
    ),
    scaffoldBackgroundColor: Colors.white,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: 'Poppins',
      fontFamilyFallback: const ['Cairo'],
      bodyColor: ZadColors.ink,
      displayColor: ZadColors.ink,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: ZadColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZadRadii.dialog),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZadRadii.button),
      ),
    ),
  );
}
