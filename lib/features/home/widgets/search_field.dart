import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';

/// Home's search entry point: a *non-editable* field that just navigates to
/// the real `/search` screen on tap (Task 5). The [TextField] stays
/// `enabled: false` so it never grabs focus here — disabled fields ignore
/// pointer events, which lets the wrapping [GestureDetector] own the tap.
class SearchField extends StatelessWidget {
  const SearchField({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pushNamed(context, '/search'),
      child: Container(
        height: 52,
        decoration: const BoxDecoration(
          color: ZadColors.surface,
          borderRadius: BorderRadius.all(Radius.circular(26)),
        ),
        child: TextField(
          enabled: false,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: l10n.searchHint,
            hintStyle: const TextStyle(fontSize: 14, color: ZadColors.muted),
            prefixIcon:
                const Icon(Iconsax.search_normal_1, color: ZadColors.muted, size: 20),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ),
    );
  }
}
