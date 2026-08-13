import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/session/session_store.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/otp_cooldown_button.dart';
import 'widgets/zad_primary_button.dart';
import 'widgets/zad_otp_field.dart';

/// 4-digit OTP entry that completes registration (PRD F1
/// `auth.verify_and_register`), reached from [RegisterPage] after
/// `request_signup_otp` succeeds.
class OtpPage extends StatefulWidget {
  const OtpPage({
    required this.phone,
    required this.fullName,
    required this.password,
    required this.initialCooldownSec,
    super.key,
  });

  final String phone;
  final String fullName;
  final String password;
  final int initialCooldownSec;

  @override
  State<OtpPage> createState() => _OtpPageState();
}

class _OtpPageState extends State<OtpPage> {
  final _formKey = GlobalKey<FormState>();
  final _otpController = TextEditingController();

  String? _errorMessage;
  bool _submitting = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  String _messageFor(Object e) => userErrorMessage(AppLocalizations.of(context), e);

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final session = context.read<SessionStore>();
    try {
      await session.register(
        fullName: widget.fullName,
        phone: widget.phone,
        password: widget.password,
        otp: _otpController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageFor(e);
        _submitting = false;
      });
    }
  }

  Future<int> _resend() async {
    final session = context.read<SessionStore>();
    final result = await session.requestSignupOtp(widget.phone);
    return result.cooldownSec;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        title: Text(l10n.authOtpTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.authOtpInstructions(widget.phone),
                  style: const TextStyle(fontSize: 14, color: ZadColors.muted),
                ),
                const SizedBox(height: 20),
                if (_errorMessage != null) ...[
                  AuthErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 16),
                ],
                ZadOtpField(
                  controller: _otpController,
                  onCompleted: _submit,
                  semanticsLabel: l10n.authOtpHint,
                  validator: (value) => (value == null || value.length != kOtpLength)
                      ? l10n.authFieldRequired
                      : null,
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OtpCooldownButton(
                    initialCooldownSec: widget.initialCooldownSec,
                    onResend: _resend,
                    onError: (e) => setState(() => _errorMessage = _messageFor(e)),
                  ),
                ),
                const SizedBox(height: 16),
                ZadPrimaryButton(
                  label: l10n.authVerifyButton,
                  onPressed: _submit,
                  loading: _submitting,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
