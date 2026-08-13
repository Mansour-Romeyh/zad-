import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/session/session_store.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/otp_cooldown_button.dart';
import 'widgets/phone_field.dart';
import 'widgets/zad_otp_field.dart';
import 'widgets/zad_primary_button.dart';
import 'widgets/zad_text_field.dart';

/// Password reset (PRD F1 `auth.request_reset_otp` + `auth.reset_password`):
/// phone entry, then a single OTP + new-password step (reset doesn't have a
/// separate "verify OTP" call — both are submitted together).
class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

enum _ResetStep { phone, otpAndPassword }

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _newPasswordFocus = FocusNode();

  _ResetStep _step = _ResetStep.phone;
  String? _errorMessage;
  bool _submitting = false;
  int _cooldownSec = 0;
  String _phone = '';

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _newPasswordFocus.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value) {
    final l10n = AppLocalizations.of(context);
    return (value == null || value.trim().isEmpty) ? l10n.authFieldRequired : null;
  }

  String _messageFor(Object e) => userErrorMessage(AppLocalizations.of(context), e);

  Future<void> _requestOtp() async {
    if (!(_phoneFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final phone = PhoneField.e164(_phoneController);
    final session = context.read<SessionStore>();
    try {
      final result = await session.requestResetOtp(phone);
      if (!mounted) return;
      setState(() {
        _phone = phone;
        _cooldownSec = result.cooldownSec;
        _step = _ResetStep.otpAndPassword;
        _submitting = false;
      });
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
    final result = await session.requestResetOtp(_phone);
    return result.cooldownSec;
  }

  Future<void> _submitReset() async {
    if (!(_resetFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final session = context.read<SessionStore>();
    try {
      await session.resetPassword(
        phone: _phone,
        otp: _otpController.text.trim(),
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.authResetSuccess)));
      Navigator.pushReplacementNamed(context, '/auth/login');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageFor(e);
        _submitting = false;
      });
    }
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
        title: Text(l10n.authResetTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: _step == _ResetStep.phone ? _phoneStep(l10n) : _otpAndPasswordStep(l10n),
        ),
      ),
    );
  }

  Widget _phoneStep(AppLocalizations l10n) {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            AuthErrorBanner(message: _errorMessage!),
            const SizedBox(height: 16),
          ],
          PhoneField(controller: _phoneController),
          const SizedBox(height: 24),
          ZadPrimaryButton(
            label: l10n.authSendOtpButton,
            onPressed: _requestOtp,
            loading: _submitting,
          ),
        ],
      ),
    );
  }

  Widget _otpAndPasswordStep(AppLocalizations l10n) {
    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.authOtpInstructions(_phone),
            style: const TextStyle(fontSize: 14, color: ZadColors.muted),
          ),
          const SizedBox(height: 20),
          if (_errorMessage != null) ...[
            AuthErrorBanner(message: _errorMessage!),
            const SizedBox(height: 16),
          ],
          ZadOtpField(
            controller: _otpController,
            onCompleted: _newPasswordFocus.requestFocus,
            semanticsLabel: l10n.authOtpHint,
            validator: (value) => (value == null || value.length != kOtpLength)
                ? l10n.authFieldRequired
                : null,
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: OtpCooldownButton(
              initialCooldownSec: _cooldownSec,
              onResend: _resend,
              onError: (e) => setState(() => _errorMessage = _messageFor(e)),
            ),
          ),
          const SizedBox(height: 8),
          ZadTextField(
            controller: _newPasswordController,
            focusNode: _newPasswordFocus,
            hintText: l10n.authNewPasswordLabel,
            obscureText: true,
            validator: _requiredValidator,
          ),
          const SizedBox(height: 24),
          ZadPrimaryButton(
            label: l10n.authResetSubmitButton,
            onPressed: _submitReset,
            loading: _submitting,
          ),
        ],
      ),
    );
  }
}
