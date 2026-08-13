import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/session/session_store.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'otp_page.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/phone_field.dart';
import 'widgets/zad_primary_button.dart';
import 'widgets/zad_text_field.dart';

/// Registration form (PRD F1 `auth.request_signup_otp`): full name, phone,
/// password. On success pushes [OtpPage] to complete `verify_and_register`.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _errorMessage;
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value) {
    final l10n = AppLocalizations.of(context);
    return (value == null || value.trim().isEmpty) ? l10n.authFieldRequired : null;
  }

  /// Password must be present and at least [kMinPasswordLength] characters —
  /// mirrors the backend rule so the user gets the error inline, before any
  /// OTP is requested (the API re-checks it in `verify_and_register`).
  String? _passwordValidator(String? value) {
    final l10n = AppLocalizations.of(context);
    if (value == null || value.isEmpty) return l10n.authFieldRequired;
    if (value.length < kMinPasswordLength) return l10n.authPasswordTooShort;
    return null;
  }

  Future<void> _requestOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final phone = PhoneField.e164(_phoneController);
    final fullName = _nameController.text.trim();
    final password = _passwordController.text;
    final session = context.read<SessionStore>();
    try {
      final result = await session.requestSignupOtp(phone);
      if (!mounted) return;
      setState(() => _submitting = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtpPage(
            phone: phone,
            fullName: fullName,
            password: password,
            initialCooldownSec: result.cooldownSec,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = userErrorMessage(AppLocalizations.of(context), e);
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
        title: Text(l10n.authRegisterTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  AuthErrorBanner(message: _errorMessage!),
                  const SizedBox(height: 16),
                ],
                ZadTextField(
                  controller: _nameController,
                  hintText: l10n.authFullNameLabel,
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 16),
                PhoneField(controller: _phoneController),
                const SizedBox(height: 16),
                ZadTextField(
                  controller: _passwordController,
                  hintText: l10n.authPasswordLabel,
                  obscureText: true,
                  validator: _passwordValidator,
                ),
                const SizedBox(height: 24),
                ZadPrimaryButton(
                  label: l10n.authSendOtpButton,
                  onPressed: _requestOtp,
                  loading: _submitting,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.authAlreadyHaveAccount,
                      style: const TextStyle(color: ZadColors.muted, fontSize: 13),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushReplacementNamed(context, '/auth/login'),
                      child: Text(l10n.authLoginLink),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
