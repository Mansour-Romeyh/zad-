import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/services/url_opener.dart';
import '../../core/session/session_store.dart';
import '../../core/stores/app_config_store.dart';
import '../../core/stores/locale_store.dart';
import '../../core/stores/settings_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/zad_dialog.dart';
import '../../core/widgets/zad_snack.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/zad_primary_button.dart';
import 'change_password_page.dart';

/// The bottom-nav Profile tab (PRD F2/profile). Authed: name/phone card +
/// the account menu — العناوين, طلباتي, تغيير كلمة المرور, الشروط والأحكام,
/// سياسة الخصوصية, الدعم (copyable support phone from app config), تسجيل
/// الخروج (confirm dialog). Guest: login CTA.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionStore>();
    return session.isAuthed
        ? _AuthedProfile(session: session)
        : const _GuestPrompt();
  }
}

/// Official WhatsApp brand green for the support "WhatsApp" action button.
const Color _whatsappGreen = Color(0xFF25D366);

/// Digits-only form of [phone] for a `wa.me/<number>` link — strips `+`,
/// spaces and separators, which the wa.me endpoint requires (bare
/// country-code + number).
String _digitsOnly(String phone) => phone.replaceAll(RegExp(r'[^0-9]'), '');

/// Dial string for a `tel:` URI — keeps a leading `+` for international
/// dialing but drops spaces/dashes that some dialers reject.
String _dialablePhone(String phone) {
  final digits = _digitsOnly(phone);
  return phone.trim().startsWith('+') ? '+$digits' : digits;
}

/// A full-width filled action button (leading icon + label) for the support
/// dialog — mirrors the branded dialog's primary-button metrics (52px tall,
/// [ZadRadii.button], white foreground on [color]).
class _SupportActionButton extends StatelessWidget {
  const _SupportActionButton({
    required super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: ZadColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZadRadii.button),
          ),
        ),
      ),
    );
  }
}

/// Language picker dialog — shared by the guest prompt and the authed menu
/// so the choice (persisted in [LocaleStore]) is reachable before login.
Future<void> _showLanguageDialog(BuildContext context) async {
  final store = context.read<LocaleStore>();
  final l10n = AppLocalizations.of(context);
  final current = store.locale.languageCode;
  final choice = await showZadDialog<Locale>(
    context,
    title: l10n.languageTitle,
    contentBuilder: (dialogContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _languageOption(
          key: const Key('languageOptionAr'),
          label: l10n.languageArabic,
          selected: current == 'ar',
          onTap: () => Navigator.pop(dialogContext, const Locale('ar')),
        ),
        _languageOption(
          key: const Key('languageOptionEn'),
          label: l10n.languageEnglish,
          selected: current == 'en',
          onTap: () => Navigator.pop(dialogContext, const Locale('en')),
        ),
      ],
    ),
  );
  if (choice != null) await store.setLocale(choice);
}

Widget _languageOption({
  required Key key,
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) => ListTile(
  key: key,
  contentPadding: EdgeInsets.zero,
  onTap: onTap,
  title: Text(
    label,
    style: const TextStyle(fontSize: 16, color: ZadColors.ink),
  ),
  trailing: selected
      ? const Icon(Icons.check, color: ZadColors.primary, size: 20)
      : null,
);

class _GuestPrompt extends StatelessWidget {
  const _GuestPrompt();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.user, size: 48, color: ZadColors.muted),
            const SizedBox(height: 16),
            Text(
              l10n.profileGuestTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ZadColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            ZadPrimaryButton(
              label: l10n.authLoginButton,
              onPressed: () => Navigator.pushNamed(context, '/auth/login'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              key: const Key('guestLanguageButton'),
              onPressed: () => _showLanguageDialog(context),
              icon: const Icon(Iconsax.global, size: 18),
              label: Text(l10n.languageTitle),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthedProfile extends StatelessWidget {
  const _AuthedProfile({required this.session});

  final SessionStore session;

  void _openChangePassword(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const ChangePasswordPage()),
    );
  }

  Future<void> _openUrl(BuildContext context, String? url) async {
    final l10n = AppLocalizations.of(context);
    if (url == null || url.isEmpty) return;
    final ok = await context.read<UrlOpener>().open(url);
    if (!ok && context.mounted) {
      showZadSnack(context, l10n.sectionErrorMessage, variant: ZadSnackVariant.error);
    }
  }

  /// The URL a policy tile opens: the server-configured [configured] value
  /// when set, otherwise the backend's own policy page ([path], e.g.
  /// `/terms`) built off the API base URL. Store compliance requires these
  /// links to always be reachable, so the tiles are shown unconditionally and
  /// this never returns empty for a valid [path].
  String _policyUrl(BuildContext context, String? configured, String path) {
    if (configured != null && configured.isNotEmpty) return configured;
    return context.read<ApiClient>().resolveFileUrl(path) ?? path;
  }

  Future<void> _showSupportDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final phone = context.read<AppConfigStore>().config.supportPhone;
    final hasPhone = phone != null && phone.isNotEmpty;
    await showZadDialog<void>(
      context,
      icon: Icons.headset_mic_outlined,
      title: l10n.supportTitle,
      contentBuilder: (dialogContext) => !hasPhone
          ? Text(
              l10n.supportUnavailable,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: ZadColors.muted),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    phone,
                    key: const Key('supportPhoneText'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: ZadColors.ink,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('supportCopyButton'),
                  tooltip: l10n.supportCopy,
                  icon: const Icon(Iconsax.copy, color: ZadColors.primary),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: phone));
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                    if (context.mounted) {
                      showZadSnack(
                        context,
                        l10n.supportPhoneCopied,
                        variant: ZadSnackVariant.success,
                      );
                    }
                  },
                ),
              ],
            ),
      actions: [
        if (hasPhone) ...[
          _SupportActionButton(
            key: const Key('supportCallButton'),
            icon: Iconsax.call,
            label: l10n.supportCall,
            color: ZadColors.primary,
            onPressed: () {
              Navigator.pop(context);
              _launchSupport(context, 'tel:${_dialablePhone(phone)}');
            },
          ),
          const SizedBox(height: 8),
          _SupportActionButton(
            key: const Key('supportWhatsappButton'),
            icon: Iconsax.message,
            label: l10n.supportWhatsapp,
            color: _whatsappGreen,
            onPressed: () {
              Navigator.pop(context);
              _launchSupport(context, 'https://wa.me/${_digitsOnly(phone)}');
            },
          ),
          const SizedBox(height: 4),
        ],
        TextButton(
          key: const Key('zadDialogSecondary'),
          onPressed: () => Navigator.pop(context),
          child: Text(
            l10n.close,
            style: const TextStyle(fontSize: 14, color: ZadColors.muted),
          ),
        ),
      ],
    );
  }

  /// Hands a `tel:`/`wa.me` URL to the OS, surfacing an error snack when no
  /// app can handle it (e.g. WhatsApp not installed, tablet with no dialer).
  Future<void> _launchSupport(BuildContext context, String url) async {
    final l10n = AppLocalizations.of(context);
    final ok = await context.read<UrlOpener>().open(url);
    if (!ok && context.mounted) {
      showZadSnack(
        context,
        l10n.sectionErrorMessage,
        variant: ZadSnackVariant.error,
      );
    }
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showZadConfirm(
      context,
      title: l10n.profileLogoutConfirmTitle,
      message: l10n.profileLogoutConfirmMessage,
      confirmLabel: l10n.profileLogoutButton,
      cancelLabel: l10n.cancel,
      icon: Icons.logout,
      destructive: true,
    );
    if (confirmed) await session.logout();
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showZadDialog<bool>(
      context,
      barrierDismissible: false,
      icon: Icons.warning_amber_rounded,
      title: l10n.deleteAccountTitle,
      contentBuilder: (dialogContext) {
        var checked = false;
        return StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.deleteAccountWarning,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: ZadColors.muted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                key: const Key('deleteAccountCheckbox'),
                value: checked,
                onChanged: (v) => setState(() => checked = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.deleteAccountConfirmCheckbox),
              ),
              const SizedBox(height: 12),
              zadDialogPrimaryAction(
                label: l10n.deleteAccountButton,
                destructive: true,
                onPressed: checked
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
              ),
              TextButton(
                key: const Key('zadDialogSecondary'),
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  l10n.cancel,
                  style: const TextStyle(fontSize: 14, color: ZadColors.muted),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;
    try {
      await session.deleteAccount();
      if (context.mounted) {
        showZadSnack(context, l10n.deleteAccountSuccess, variant: ZadSnackVariant.success);
      }
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = context.watch<AppConfigStore>().config;
    return ListView(
      padding: const EdgeInsets.all(ZadSpacing.screenPadding),
      children: [
        _ProfileHeaderCard(session: session),
        const SizedBox(height: ZadSpacing.sectionGap),
        _MenuTile(
          key: const Key('profileMenuAddresses'),
          icon: Iconsax.location,
          label: l10n.addressesTitle,
          onTap: () => Navigator.pushNamed(context, '/addresses'),
        ),
        _MenuTile(
          key: const Key('profileMenuOrders'),
          icon: Iconsax.receipt_2,
          label: l10n.ordersTitle,
          onTap: () => Navigator.pushNamed(context, '/orders'),
        ),
        _MenuTile(
          key: const Key('profileMenuChangePassword'),
          icon: Iconsax.lock,
          label: l10n.changePasswordTitle,
          onTap: () => _openChangePassword(context),
        ),
        _MenuTile(
          key: const Key('profileMenuLanguage'),
          icon: Iconsax.global,
          label: l10n.languageTitle,
          onTap: () => _showLanguageDialog(context),
        ),
        _MenuToggleTile(
          key: const Key('profileOrderSoundToggle'),
          icon: Iconsax.volume_high,
          label: l10n.profileOrderSoundLabel,
          value: context.watch<SettingsStore>().orderSoundEnabled,
          onChanged: (v) =>
              context.read<SettingsStore>().setOrderSoundEnabled(v),
        ),
        _MenuTile(
          key: const Key('profileMenuTerms'),
          icon: Iconsax.document_text,
          label: l10n.profileTermsTitle,
          onTap: () =>
              _openUrl(context, _policyUrl(context, config.termsUrl, '/terms')),
        ),
        _MenuTile(
          key: const Key('profileMenuPrivacy'),
          icon: Iconsax.shield_tick,
          label: l10n.profilePrivacyTitle,
          onTap: () => _openUrl(
            context,
            _policyUrl(context, config.privacyUrl, '/privacy-policy'),
          ),
        ),
        _MenuTile(
          key: const Key('profileMenuSupport'),
          icon: Iconsax.headphone,
          label: l10n.supportTitle,
          onTap: () => _showSupportDialog(context),
        ),
        _MenuTile(
          key: const Key('profileMenuLogout'),
          icon: Iconsax.logout,
          label: l10n.profileLogoutButton,
          destructive: true,
          onTap: () => _confirmLogout(context),
        ),
        _MenuTile(
          key: const Key('profileMenuDeleteAccount'),
          icon: Iconsax.trash,
          label: l10n.deleteAccountTitle,
          destructive: true,
          onTap: () => _confirmDeleteAccount(context),
        ),
      ],
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({required this.session});

  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = session.fullName ?? session.phone ?? session.user ?? '';
    final phone = session.phone;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ZadColors.paleGreen,
        borderRadius: BorderRadius.circular(ZadRadii.banner),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Iconsax.user, color: ZadColors.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.profileGreeting(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ZadColors.ink,
                  ),
                ),
                if (phone != null && phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ZadColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : ZadColors.ink;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(ZadRadii.tile),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 10, 14),
          decoration: BoxDecoration(
            color: ZadColors.surface,
            borderRadius: BorderRadius.circular(ZadRadii.tile),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: destructive ? Colors.redAccent : ZadColors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: ZadColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings row shaped like [_MenuTile] but with a trailing switch.
class _MenuToggleTile extends StatelessWidget {
  const _MenuToggleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 6, 2),
        decoration: BoxDecoration(
          color: ZadColors.surface,
          borderRadius: BorderRadius.circular(ZadRadii.tile),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: ZadColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ZadColors.ink,
                ),
              ),
            ),
            Switch.adaptive(
              value: value,
              activeThumbColor: ZadColors.primary,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
