import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/session/session_store.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/auth_error_banner.dart';
import 'widgets/phone_field.dart';
import 'widgets/zad_primary_button.dart';
import 'widgets/zad_text_field.dart';

/// Phone + password login (PRD F1 `auth.login`). Links out to registration
/// and password reset; on success routes to `/home`.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _errorMessage;
  bool _submitting = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value) {
    final l10n = AppLocalizations.of(context);
    return (value == null || value.trim().isEmpty) ? l10n.authFieldRequired : null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final session = context.read<SessionStore>();
    try {
      await session.login(
        phone: PhoneField.e164(_phoneController),
        password: _passwordController.text,
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
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
        title: Text(l10n.authLoginTitle),
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
                PhoneField(controller: _phoneController),
                const SizedBox(height: 16),
                ZadTextField(
                  controller: _passwordController,
                  hintText: l10n.authPasswordLabel,
                  obscureText: true,
                  validator: _requiredValidator,
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/auth/reset'),
                    child: Text(l10n.authForgotPassword),
                  ),
                ),
                const SizedBox(height: 8),
                ZadPrimaryButton(
                  label: l10n.authLoginButton,
                  onPressed: _submit,
                  loading: _submitting,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.authNoAccount,
                      style: const TextStyle(color: ZadColors.muted, fontSize: 13),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/auth/register'),
                      child: Text(l10n.authRegisterLink),
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
