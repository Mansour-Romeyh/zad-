import 'package:flutter/material.dart';

import '../constants.dart';
import '../theme.dart';

/// The icon-led dialog scaffold shared by [showZadConfirm] and [showZadDialog]:
/// a circular tinted icon badge, bold centred title, muted body/content, and a
/// bottom action column (one full-width filled primary, optional text
/// secondary). 28px radius, white surface, soft shadow, scale+fade entrance.
///
/// Lives in core/widgets and imports only core tokens — no feature deps.
class ZadDialog extends StatelessWidget {
  const ZadDialog({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Material(
          color: ZadColors.white,
          elevation: ZadElevation.dialog,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(ZadRadii.dialog),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _iconBadge(IconData icon, Color color) => Container(
  width: 56,
  height: 56,
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.12),
    shape: BoxShape.circle,
  ),
  child: Icon(icon, color: color, size: 28),
);

Widget _primaryButton({
  required Key key,
  required String label,
  required Color color,
  required VoidCallback? onPressed,
}) => SizedBox(
  width: double.infinity,
  height: 52,
  child: ElevatedButton(
    key: key,
    onPressed: onPressed,
    style: ElevatedButton.styleFrom(
      backgroundColor: color,
      foregroundColor: ZadColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ZadRadii.button),
      ),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    ),
  ),
);

Future<T?> _showBrandedDialog<T>(
  BuildContext context, {
  required bool barrierDismissible,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: ZadColors.scrim,
    transitionDuration: ZadDurations.popupIn,
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: ZadCurves.popupIn);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Confirm/cancel dialog. Resolves true on confirm, false on cancel. When
/// [destructive] the primary is [ZadColors.danger] and the barrier is NOT
/// dismissible (forces an explicit choice); otherwise a barrier tap ⇒ false.
Future<bool> showZadConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  IconData? icon,
  bool destructive = false,
}) async {
  final color = destructive ? ZadColors.danger : ZadColors.primary;
  final result = await _showBrandedDialog<bool>(
    context,
    barrierDismissible: !destructive,
    builder: (dialogContext) => ZadDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            _iconBadge(icon, color),
            const SizedBox(height: 18),
          ],
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ZadColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: ZadColors.muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          _primaryButton(
            key: const Key('zadDialogPrimary'),
            label: confirmLabel,
            color: color,
            onPressed: () => Navigator.pop(dialogContext, true),
          ),
          const SizedBox(height: 4),
          TextButton(
            key: const Key('zadDialogSecondary'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              cancelLabel,
              style: const TextStyle(fontSize: 14, color: ZadColors.muted),
            ),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}

/// Lower-level dialog for custom body/actions (lists, checkboxes, option rows).
/// [contentBuilder] renders below the title; [actions] are laid out in a
/// bottom column. Callers pop [Navigator] with their own result value.
Future<T?> showZadDialog<T>(
  BuildContext context, {
  IconData? icon,
  String? title,
  required WidgetBuilder contentBuilder,
  List<Widget> actions = const [],
  bool barrierDismissible = true,
}) {
  return _showBrandedDialog<T>(
    context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => ZadDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (icon != null) ...[
            Center(child: _iconBadge(icon, ZadColors.primary)),
            const SizedBox(height: 18),
          ],
          if (title != null) ...[
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ZadColors.ink,
              ),
            ),
            const SizedBox(height: 12),
          ],
          contentBuilder(dialogContext),
          if (actions.isNotEmpty) ...[const SizedBox(height: 20), ...actions],
        ],
      ),
    ),
  );
}

/// A full-width filled primary action for use inside [showZadDialog.actions].
Widget zadDialogPrimaryAction({
  required String label,
  required VoidCallback? onPressed,
  bool destructive = false,
}) => _primaryButton(
  key: const Key('zadDialogPrimary'),
  label: label,
  color: destructive ? ZadColors.danger : ZadColors.primary,
  onPressed: onPressed,
);
