import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme.dart';
import '../../../core/constants.dart';
import '../../../l10n/app_localizations.dart';

/// A rounded, filled text field matching the Zad design language (same
/// surface/radius tokens as [SearchField]), reused across the auth screens
/// for password/full-name/OTP/new-password inputs.
///
/// When [obscureText] is set (i.e. a password input) the field owns a
/// show/hide eye toggle in its trailing edge, so every password field across
/// auth gets reveal-on-tap without any call-site change.
class ZadTextField extends StatefulWidget {
  const ZadTextField({
    required this.controller,
    required this.hintText,
    this.obscureText = false,
    this.keyboardType,
    this.textAlign = TextAlign.start,
    this.validator,
    this.autofocus = false,
    this.maxLength,
    this.textInputAction,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextAlign textAlign;
  final String? Function(String?)? validator;
  final bool autofocus;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;

  @override
  State<ZadTextField> createState() => _ZadTextFieldState();
}

class _ZadTextFieldState extends State<ZadTextField> {
  /// Live obscuring state; starts hidden for password fields and flips when
  /// the user taps the eye toggle. Always false for non-obscured fields.
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.button),
      ),
      child: TextFormField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        obscureText: _obscured,
        keyboardType: widget.keyboardType,
        textAlign: widget.textAlign,
        autofocus: widget.autofocus,
        maxLength: widget.maxLength,
        textInputAction: widget.textInputAction,
        validator: widget.validator,
        style: const TextStyle(fontSize: 14, color: ZadColors.ink),
        decoration: InputDecoration(
          counterText: '',
          border: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          hintText: widget.hintText,
          hintStyle: const TextStyle(color: ZadColors.muted, fontSize: 14),
          suffixIcon: widget.obscureText
              ? IconButton(
                  key: const Key('passwordVisibilityToggle'),
                  icon: Icon(
                    _obscured ? Iconsax.eye_slash : Iconsax.eye,
                    size: 20,
                    color: ZadColors.muted,
                  ),
                  tooltip:
                      _obscured ? l10n.authShowPassword : l10n.authHidePassword,
                  onPressed: () => setState(() => _obscured = !_obscured),
                )
              : null,
        ),
      ),
    );
  }
}
