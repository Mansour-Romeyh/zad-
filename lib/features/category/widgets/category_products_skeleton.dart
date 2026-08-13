import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';

/// A calm, static placeholder grid shown while a category's products load.
/// Deliberately un-animated: a switch to a category reads as an intentional
/// load rather than a spinner flash, and a static skeleton keeps
/// `pumpAndSettle`-based widget tests from deadlocking on a repeating shimmer.
class CategoryProductsSkeleton extends StatelessWidget {
  const CategoryProductsSkeleton({
    this.cellHeight = 250 + kProductCardControlHeight + kProductCardControlGap,
    super.key,
  });

  /// Matches the browser grid's `mainAxisExtent` so the skeleton occupies the
  /// same footprint the real cards will.
  final double cellHeight;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(ZadSpacing.screenPadding),
      crossAxisCount: 2,
      mainAxisSpacing: 16,
      crossAxisSpacing: 14,
      mainAxisExtent: cellHeight,
      children: List.generate(6, (_) => const _SkeletonCard()),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: ZadColors.surface,
              borderRadius: BorderRadius.circular(ZadRadii.tile),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const _Bar(widthFactor: 0.85),
        const SizedBox(height: 8),
        const _Bar(widthFactor: 0.5),
        const SizedBox(height: 10),
        const _Bar(widthFactor: 0.35, height: 14),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.widthFactor, this.height = 10});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: ZadColors.surface,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}
