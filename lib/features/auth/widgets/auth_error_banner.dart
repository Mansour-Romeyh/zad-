import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';

/// Inline error banner for auth screens (wrong OTP, expired OTP, cooldown,
/// invalid credentials, network failure — whatever [ApiException.message]
/// the server/client produced).
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ZadColors.errorSurface,
        borderRadius: BorderRadius.circular(ZadRadii.button),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13, color: ZadColors.errorText),
      ),
    );
  }
}
