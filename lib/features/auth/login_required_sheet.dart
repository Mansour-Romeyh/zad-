import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/session/session_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/zad_bottom_sheet.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/zad_primary_button.dart';

/// Shared bottom sheet shown when a guest taps a gated action (cart,
/// favourites, checkout, profile — PRD A3): "سجّل الدخول للمتابعة" with
/// login/register CTAs.
class LoginRequiredSheet extends StatelessWidget {
  const LoginRequiredSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.authLoginRequiredTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: ZadColors.ink,
          ),
        ),
        const SizedBox(height: 20),
        ZadPrimaryButton(
          label: l10n.authLoginButton,
          onPressed: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/auth/login');
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/auth/register');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: ZadColors.primary,
              side: const BorderSide(color: ZadColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ZadRadii.button),
              ),
            ),
            child: Text(
              l10n.authRegisterLink,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// Returns `true` immediately if the user is already logged in. Otherwise
/// shows [LoginRequiredSheet] and returns whether the session ended up
/// authed once the sheet is dismissed — callers (cart/fav/checkout taps)
/// use this to decide whether to proceed with the gated action.
Future<bool> ensureLoggedIn(BuildContext context) async {
  final session = context.read<SessionStore>();
  if (session.isAuthed) return true;

  await showZadSheet<void>(context, builder: (_) => const LoginRequiredSheet());

  if (!context.mounted) return false;
  return context.read<SessionStore>().isAuthed;
}
