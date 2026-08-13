import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/constants.dart';

/// Full-width primary CTA button shared by the auth screens, with a
/// built-in loading spinner state so async submit handlers don't each
/// reinvent it.
class ZadPrimaryButton extends StatelessWidget {
  const ZadPrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: ZadColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: ZadColors.primary.withValues(alpha: 0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZadRadii.button),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
