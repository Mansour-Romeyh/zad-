import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/session/session_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/zad_snack.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/auth_error_banner.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../auth/widgets/zad_text_field.dart';

/// Change password (PRD F1 `auth.change_password {old, new}`): current +
/// new password, submitted against the logged-in session. A wrong current
/// password comes back as a 401 credential rejection (frappe
/// `check_password`) — surfaced as a localized inline error, NOT an app
/// logout (`ApiClient` skips the app-wide 401 hook for auth endpoints).
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _oldController = TextEditingController();
  final _newController = TextEditingController();

  String? _errorMessage;
  bool _submitting = false;

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    super.dispose();
  }

  String? _requiredValidator(String? value) {
    final l10n = AppLocalizations.of(context);
    return (value == null || value.trim().isEmpty)
        ? l10n.authFieldRequired
        : null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final l10n = AppLocalizations.of(context);
    final session = context.read<SessionStore>();
    try {
      await session.changePassword(
        oldPassword: _oldController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      showZadSnack(context, l10n.changePasswordSuccess, variant: ZadSnackVariant.success);
      Navigator.pop(context);
    } on UnauthenticatedException {
      // Wrong OLD password — frappe's check_password answers 401.
      if (!mounted) return;
      setState(() {
        _errorMessage = l10n.changePasswordWrongOld;
        _submitting = false;
      });
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
        title: Text(l10n.changePasswordTitle),
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
                  key: const Key('oldPasswordField'),
                  controller: _oldController,
                  hintText: l10n.changePasswordOldLabel,
                  obscureText: true,
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 16),
                ZadTextField(
                  key: const Key('newPasswordField'),
                  controller: _newController,
                  hintText: l10n.authNewPasswordLabel,
                  obscureText: true,
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 24),
                ZadPrimaryButton(
                  label: l10n.changePasswordSubmit,
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
