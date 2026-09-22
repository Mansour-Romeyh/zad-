import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.onSeeAll,
    this.titleFontSize = 18,
    this.titleFontWeight = FontWeight.w600,
    super.key,
  });

  final String title;

  /// Opens the section's full listing. When null the "See All" label is
  /// omitted entirely — never a visible label that does nothing.
  final VoidCallback? onSeeAll;

  /// Font size for the section title. Defaults to the standard 18.
  final double titleFontSize;

  /// Font weight for the section title. Defaults to semibold (w600).
  final FontWeight titleFontWeight;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: titleFontWeight,
              color: ZadColors.ink,
            ),
          ),
        ),
        if (onSeeAll != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onSeeAll,
            child: Text(
              l10n.seeAll,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: ZadColors.primary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
