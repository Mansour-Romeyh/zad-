import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/constants.dart';
import '../../../l10n/app_localizations.dart';

/// Iraqi phone-number input: a fixed `+964` prefix (always LTR, regardless
/// of the ambient text direction) plus a local-number field. Callers read
/// [PhoneField.e164] to get the value formatted for the API.
class PhoneField extends StatelessWidget {
  const PhoneField({required this.controller, this.autofocus = false, super.key});

  final TextEditingController controller;
  final bool autofocus;

  /// Formats [controller]'s current text as an E.164-ish Iraqi number:
  /// `+964` + the local digits, normalized the way Iraqi users actually
  /// type them. `07701234567` (the universal local convention) must become
  /// `+9647701234567`, never `+96407701234567`, so with the country prefix
  /// applied any leading zeros are stripped. Pasted full numbers
  /// (`+964 770 123 4567`, `9647701234567`) also collapse to one prefix,
  /// and formatting separators (spaces, dashes) are dropped.
  static String e164(TextEditingController controller) =>
      '+964${_localDigits(controller.text)}';

  /// True when [text] normalizes to an Iraqi mobile number: 10 local digits
  /// starting with 7 (typed as 07XX XXX XXXX, sent as +9647XXXXXXXXX).
  static bool isValidIraqiMobile(String text) =>
      RegExp(r'^7\d{9}$').hasMatch(_localDigits(text));

  static String _localDigits(String text) {
    var digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    // A pasted country code: local Iraqi numbers are at most 10 digits, so
    // 964 + something longer than that can only be a full +964 number.
    if (digits.startsWith('964') && digits.length > 10) {
      digits = digits.substring(3);
    }
    return digits.replaceFirst(RegExp(r'^0+'), '');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.button),
      ),
      padding: const EdgeInsetsDirectional.only(start: 16, end: 4),
      child: Row(
        children: [
          const Text(
            '+964',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ZadColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 20, color: ZadColors.muted),
          Expanded(
            child: Semantics(
              label: l10n.authPhoneLabel,
              textField: true,
              child: TextFormField(
                controller: controller,
                autofocus: autofocus,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return l10n.authFieldRequired;
                  return isValidIraqiMobile(value) ? null : l10n.authPhoneInvalid;
                },
                style: const TextStyle(fontSize: 14, color: ZadColors.ink),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                  hintText: l10n.authPhoneHint,
                  hintStyle: const TextStyle(color: ZadColors.muted, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
