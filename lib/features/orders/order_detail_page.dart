import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/order_status.dart';
import '../../core/theme.dart';
import '../../data/order_repository.dart';
import '../../l10n/app_localizations.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/section_state.dart';
import 'order_status_chip.dart';

/// Everything the detail screen needs, fetched together so the page has
/// one loading/error lifecycle (`order.detail` + `order.changes`).
class _OrderDetailData {
  const _OrderDetailData({required this.detail, required this.changes});

  final OrderDetail detail;
  final List<OrderChange> changes;
}

/// One order (PRD F5 `order.detail` + `order.changes`): header with status
/// chip, the A2 status timeline (placed → … → delivered; Expired/Cancelled
/// render as a terminal banner instead of progress), lines with
/// estimated/actual qty (a "تم التعديل" badge when the picker confirmed a
/// different weight, PRD E6), totals, and the change feed (weight
/// adjustments / substitutions / removals, newest first, server-rendered
/// Arabic descriptions).
class OrderDetailPage extends StatefulWidget {
  const OrderDetailPage({required this.orderName, super.key});

  final String orderName;

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  SectionState<_OrderDetailData> _state = const SectionState.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const SectionState.loading());
    try {
      final repository = context.read<OrderRepository>();
      final detailFuture = repository.detail(widget.orderName);
      // Degrade, don't block: the change feed is auxiliary — if only
      // `order.changes` fails the page still renders the full detail
      // (header, timeline, lines, totals) with the feed omitted. The
      // handler is attached before awaiting the detail so a double failure
      // can never surface as an unhandled rejection.
      final changesFuture = repository
          .changes(widget.orderName)
          .then<List<OrderChange>?>((changes) => changes)
          .onError((_, _) => null);
      final detail = await detailFuture;
      final changes = await changesFuture ?? const <OrderChange>[];
      if (!mounted) return;
      setState(() {
        _state = SectionState.data(
          _OrderDetailData(detail: detail, changes: changes),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = SectionState.error(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        title: Text(l10n.orderDetailTitle),
      ),
      body: SafeArea(
        child: AsyncSection<_OrderDetailData>(
          state: _state,
          skeleton: const Padding(
            padding: EdgeInsets.all(ZadSpacing.screenPadding),
            child: SectionSkeleton(height: 300),
          ),
          onRetry: _load,
          builder: (context, data) => _DetailBody(
            detail: data.detail,
            changes: data.changes,
            l10n: l10n,
          ),
        ),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.detail,
    required this.changes,
    required this.l10n,
  });

  final OrderDetail detail;
  final List<OrderChange> changes;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return ListView(
      padding: const EdgeInsets.all(ZadSpacing.screenPadding),
      children: [
        // -- header ---------------------------------------------------
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ZadColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatDisplayDate(
                      detail.date,
                      Localizations.localeOf(context).toString(),
                    ),
                    style: const TextStyle(fontSize: 12, color: ZadColors.muted),
                  ),
                ],
              ),
            ),
            OrderStatusChip(status: detail.status),
          ],
        ),
        const SizedBox(height: ZadSpacing.sectionGap),
        // -- status timeline -------------------------------------------
        _SectionTitle(text: l10n.orderStatusTimelineTitle),
        const SizedBox(height: 12),
        _StatusTimeline(status: detail.status, l10n: l10n),
        const SizedBox(height: ZadSpacing.sectionGap),
        // -- lines ------------------------------------------------------
        _SectionTitle(text: l10n.orderItemsTitle),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: ZadColors.surface,
            borderRadius: BorderRadius.circular(ZadRadii.tile),
          ),
          child: Column(
            children: [
              for (var i = 0; i < detail.items.length; i++) ...[
                if (i > 0) const Divider(height: 18),
                _OrderLineTile(line: detail.items[i], l10n: l10n),
              ],
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.basketSubtotal,
                    style: const TextStyle(fontSize: 13, color: ZadColors.muted),
                  ),
                  Text(
                    formatPrice(detail.totals.netTotal, languageCode),
                    style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                  ),
                ],
              ),
              if (detail.totals.deliveryFee > 0) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.checkoutDelivery,
                      style:
                          const TextStyle(fontSize: 13, color: ZadColors.muted),
                    ),
                    Text(
                      formatPrice(detail.totals.deliveryFee, languageCode),
                      style:
                          const TextStyle(fontSize: 13, color: ZadColors.ink),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.basketTotal,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ZadColors.ink,
                    ),
                  ),
                  Text(
                    formatPrice(detail.totals.grandTotal, languageCode),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: ZadColors.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // -- change feed --------------------------------------------------
        if (changes.isNotEmpty) ...[
          const SizedBox(height: ZadSpacing.sectionGap),
          _SectionTitle(text: l10n.orderChangesTitle),
          const SizedBox(height: 12),
          for (final change in changes)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 10),
              child: _ChangeTile(change: change),
            ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ZadColors.ink,
      ),
    );
  }
}

/// The PRD A2 happy-path pipeline as a vertical stepper. Steps up to the
/// current status are "reached" (green); Expired/Cancelled show a terminal
/// banner above a fully-unreached pipeline.
class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status, required this.l10n});

  final String status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final reachedIndex = OrderStatus.timelineIndex(status);
    final isTerminalFailure = OrderStatus.terminal.contains(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isTerminalFailure) ...[
          Container(
            key: const Key('terminalStatusBanner'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: orderStatusColor(status).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(ZadRadii.button),
            ),
            child: Row(
              children: [
                Icon(Iconsax.close_circle, size: 20, color: orderStatusColor(status)),
                const SizedBox(width: 10),
                Text(
                  orderStatusLabel(l10n, status),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: orderStatusColor(status),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < OrderStatus.timeline.length; i++)
          _TimelineStep(
            label: orderStatusLabel(l10n, OrderStatus.timeline[i]),
            reached: reachedIndex != null && i <= reachedIndex,
            isCurrent: reachedIndex != null && i == reachedIndex,
            isLast: i == OrderStatus.timeline.length - 1,
          ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.label,
    required this.reached,
    required this.isCurrent,
    required this.isLast,
  });

  final String label;
  final bool reached;
  final bool isCurrent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = reached ? ZadColors.primary : ZadColors.muted;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Icon(
                reached ? Iconsax.tick_circle : Iconsax.record,
                size: 18,
                color: color,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: reached
                        ? ZadColors.primary.withValues(alpha: 0.4)
                        : ZadColors.muted.withValues(alpha: 0.3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: reached ? ZadColors.ink : ZadColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderLineTile extends StatelessWidget {
  const _OrderLineTile({required this.line, required this.l10n});

  final OrderLine line;
  final AppLocalizations l10n;

  /// `2` not `2.0`, `0.5` kept — quantities are Kg decimals for weight
  /// lines and integers otherwise.
  static String _fmtQty(double qty) {
    if (qty == qty.roundToDouble()) return qty.round().toString();
    var text = qty.toStringAsFixed(3);
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  String _qtyWithUom(double qty) {
    final uom = line.uom;
    return uom == null || uom.isEmpty ? _fmtQty(qty) : '${_fmtQty(qty)} $uom';
  }

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                line.itemName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: ZadColors.ink,
                ),
              ),
            ),
            if (line.adjusted) ...[
              const SizedBox(width: 8),
              Container(
                key: Key('adjustedBadge-${line.name}'),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF3E1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.orderAdjustedBadge,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFB7791F),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 12),
            Text(
              formatPrice(line.amount, languageCode),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ZadColors.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (line.adjusted)
          Wrap(
            spacing: 12,
            runSpacing: 2,
            children: [
              Text(
                l10n.orderEstimatedQty(_qtyWithUom(line.estimatedQty)),
                style: const TextStyle(fontSize: 12, color: ZadColors.muted),
              ),
              Text(
                l10n.orderActualQty(_qtyWithUom(line.actualQty)),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ZadColors.ink,
                ),
              ),
            ],
          )
        else
          Text(
            '${_qtyWithUom(line.qty)} × ${formatPrice(line.rate, languageCode)}',
            style: const TextStyle(fontSize: 12, color: ZadColors.muted),
          ),
      ],
    );
  }
}

class _ChangeTile extends StatelessWidget {
  const _ChangeTile({required this.change});

  final OrderChange change;

  IconData get _icon => switch (change.type) {
    OrderChange.weightAdjustment => Iconsax.weight,
    OrderChange.substitution => Iconsax.arrange_square_2,
    OrderChange.removal => Iconsax.trash,
    _ => Iconsax.info_circle,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_icon, size: 20, color: ZadColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  change.detail,
                  style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                ),
                if (change.timestamp != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    change.timestamp!,
                    style: const TextStyle(fontSize: 11, color: ZadColors.muted),
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
