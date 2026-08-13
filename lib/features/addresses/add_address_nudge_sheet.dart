import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/zad_primary_button.dart';
import 'address_form_page.dart';

/// First-login nudge (PRD A3): shown from home once per session when an
/// authed user has no saved addresses — "add your delivery address", fully
/// skippable. The add CTA goes straight into [AddressFormPage] (fewest taps
/// to a saved address); the skip button just dismisses.
class AddAddressNudgeSheet extends StatelessWidget {
  const AddAddressNudgeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ZadSpacing.screenPadding,
          28,
          ZadSpacing.screenPadding,
          ZadSpacing.screenPadding,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.location, size: 44, color: ZadColors.primary),
            const SizedBox(height: 14),
            Text(
              l10n.addressNudgeTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ZadColors.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.addressNudgeBody,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: ZadColors.muted),
            ),
            const SizedBox(height: 20),
            ZadPrimaryButton(
              key: const Key('nudgeAddAddressButton'),
              label: l10n.addressAdd,
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AddressFormPage(),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('nudgeSkipButton'),
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.addressNudgeSkip),
            ),
          ],
        ),
      ),
    );
  }
}
