import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/session/session_store.dart';
import '../../../core/stores/address_store.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../../addresses/address_label.dart';
import '../../auth/login_required_sheet.dart';
import 'notifications_bell.dart';

/// Home header (PRD F4/A3): shows the authed user's default address —
/// label as the title, address line + city underneath — and routes a tap
/// to `/addresses`. Guests see the generic placeholder; their tap opens
/// the shared login sheet first (and proceeds to the address book only if
/// they end up logged in).
class LocationHeader extends StatelessWidget {
  const LocationHeader({super.key});

  Future<void> _onTap(BuildContext context) async {
    final ok = await ensureLoggedIn(context);
    if (!ok || !context.mounted) return;
    Navigator.pushNamed(context, '/addresses');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAuthed = context.watch<SessionStore>().isAuthed;
    final defaultAddress =
        isAuthed ? context.watch<AddressStore>().defaultAddress : null;

    final String title;
    final String subtitle;
    if (!isAuthed) {
      title = l10n.homeLabel;
      subtitle = l10n.addressPlaceholder;
    } else if (defaultAddress != null) {
      title = localizedAddressLabel(l10n, defaultAddress.label);
      subtitle = [
        defaultAddress.addressLine,
        defaultAddress.city,
      ].where((part) => part.isNotEmpty).join(', ');
    } else {
      title = l10n.homeLabel;
      subtitle = l10n.addressSelectPrompt;
    }

    return Row(
      children: [
        Expanded(
          child: InkWell(
            key: const Key('locationHeaderTap'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => _onTap(context),
            child: Row(
              children: [
                Icon(
                  defaultAddress != null
                      ? addressLabelIcon(defaultAddress.label)
                      : Iconsax.location,
                  color: ZadColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: ZadColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Iconsax.arrow_down_1,
                            size: 14,
                            color: ZadColors.ink,
                          ),
                        ],
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: ZadColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        const NotificationsBell(),
      ],
    );
  }
}
