import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';

/// Home's search entry point: a *non-editable* pill that navigates to the
/// real `/search` screen on tap (Task 5). Styled to match the reference
/// design — a light-grey pill with a dark-green circular search button at the
/// start (the right edge under RTL).
class SearchField extends StatelessWidget {
  const SearchField({super.key});

  // From the reference design. Kept local to this widget since they're
  // specific to the search pill, not app-wide tokens.
  static const _fieldBackground = Color(0xFFEAEAEA);
  static const _buttonGreen = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.pushNamed(context, '/search'),
      child: Container(
        height: 52,
        padding: const EdgeInsetsDirectional.only(start: 6, end: 20),
        decoration: const BoxDecoration(
          color: _fieldBackground,
          borderRadius: BorderRadius.all(Radius.circular(26)),
        ),
        child: Row(
          children: [
            // Circular search button — sits at the start (right under RTL),
            // matching the reference.
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: _buttonGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Iconsax.search_normal_1,
                color: ZadColors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.searchHint,
                style: const TextStyle(fontSize: 14, color: ZadColors.muted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
