import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import 'section_state.dart';

/// Renders a home section's async lifecycle: [skeleton] while [state] is
/// loading, a retry prompt on error, [emptyBuilder] when data arrived but
/// is empty (only checked when both [isEmpty] and [emptyBuilder] are
/// given), otherwise [builder] with the loaded data.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    required this.state,
    required this.skeleton,
    required this.builder,
    required this.onRetry,
    this.isEmpty,
    this.emptyBuilder,
    super.key,
  });

  final SectionState<T> state;
  final Widget skeleton;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;
  final bool Function(T data)? isEmpty;
  final WidgetBuilder? emptyBuilder;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case SectionStatus.loading:
        return skeleton;
      case SectionStatus.error:
        return _SectionError(onRetry: onRetry);
      case SectionStatus.data:
        final data = state.data as T;
        if (isEmpty != null && emptyBuilder != null && isEmpty!(data)) {
          return emptyBuilder!(context);
        }
        return builder(context, data);
    }
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
      ),
      child: Column(
        children: [
          Text(
            l10n.sectionErrorMessage,
            style: const TextStyle(color: ZadColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}

/// A simple, static loading placeholder ("skeleton") — no animation, per
/// the brief's "simple containers" guidance — sized to roughly match the
/// section it stands in for.
class SectionSkeleton extends StatelessWidget {
  const SectionSkeleton({required this.height, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
      ),
    );
  }
}
