import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme.dart';

/// Branded modal bottom sheet: a grabber handle, [ZadRadii.sheet] top corners,
/// white surface, safe-area + keyboard-inset aware padding, and an optional
/// [title] header. Core-only imports.
Future<T?> showZadSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: ZadColors.white,
    barrierColor: ZadColors.scrim,
    elevation: ZadElevation.sheet,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(ZadRadii.sheet)),
    ),
    builder: (sheetContext) {
      final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            ZadSpacing.screenPadding,
            10,
            ZadSpacing.screenPadding,
            ZadSpacing.screenPadding + bottomInset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  key: const Key('zadSheetHandle'),
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: ZadColors.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null) ...[
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700, color: ZadColors.ink)),
                const SizedBox(height: 12),
              ],
              builder(sheetContext),
            ],
          ),
        ),
      );
    },
  );
}
