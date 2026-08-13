import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import 'page_dots.dart';

class OnboardingCard extends StatelessWidget {
  const OnboardingCard({
    required this.index,
    required this.title,
    required this.body,
    required this.onNext,
    this.count = 3,
    super.key,
  });

  final int index;

  /// Total slides — 3 for the bundled fallback, or however many the
  /// backend's `get_onboarding` returned.
  final int count;

  final String title;
  final String body;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(ZadRadii.sheet)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PageDots(count: count, index: index),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                height: 1.3,
                color: ZadColors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: ZadColors.muted,
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              button: true,
              label: AppLocalizations.of(context).next,
              child: Material(
                color: ZadColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: onNext,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 56,
                    height: 56,
                    child: Icon(Icons.arrow_forward,
                        color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
