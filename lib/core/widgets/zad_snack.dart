import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme.dart';

enum ZadSnackVariant { success, error, info, warning }

({IconData icon, Color color}) _style(ZadSnackVariant v) => switch (v) {
      ZadSnackVariant.success => (icon: Icons.check_circle_outline, color: ZadColors.success),
      ZadSnackVariant.error => (icon: Icons.error_outline, color: ZadColors.danger),
      ZadSnackVariant.info => (icon: Icons.info_outline, color: ZadColors.info),
      ZadSnackVariant.warning => (icon: Icons.warning_amber_rounded, color: ZadColors.warning),
    };

/// Floating, rounded, leading-icon snackbar coloured by [variant]. Uses
/// ScaffoldMessenger.of(context) (caller guards `context.mounted`). Clears any
/// in-flight snackbar first so they never stack.
void showZadSnack(
  BuildContext context,
  String message, {
  ZadSnackVariant variant = ZadSnackVariant.info,
}) {
  final s = _style(variant);
  final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ZadColors.white,
      elevation: ZadElevation.snack,
      duration: ZadDurations.snack,
      margin: const EdgeInsets.all(ZadSpacing.screenPadding),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZadRadii.button),
        side: BorderSide(color: s.color.withValues(alpha: 0.35)),
      ),
      content: Row(
        key: const Key('zadSnack'),
        children: [
          Icon(s.icon, color: s.color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 14, color: ZadColors.ink)),
          ),
        ],
      ),
    ),
  );
}
