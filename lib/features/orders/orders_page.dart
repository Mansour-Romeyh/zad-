import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/session/session_store.dart';
import '../../core/theme.dart';
import '../../data/order_repository.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/section_state.dart';
import 'order_detail_page.dart';
import 'order_status_chip.dart';

/// `/orders` (PRD F5 `order.my_orders`): the caller's orders, newest first,
/// as paged cards (number, date, item count, total, localized fulfilment
/// status chip) — same infinite-scroll pattern as the category grid,
/// `has_more` straight from the backend envelope. Tapping a card opens
/// [OrderDetailPage]. Guests (deep link) get a login prompt.
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  static const _loadMoreThresholdPx = 200;

  final _scrollController = ScrollController();

  SectionState<List<OrderSummary>> _state = const SectionState.loading();
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// The last next-page load failed. A scrollable list would retry on the
  /// next scroll tick anyway, but an UNDERFILLED list has no scroll tick —
  /// so the tail slot renders a retry button instead of nothing.
  bool _loadMoreFailed = false;

  /// Whether a first-page load ever ran for the current authed stint —
  /// guests who log in from the inline prompt land back here without a new
  /// initState, so [build] triggers the load on that transition.
  bool _loadedThisSession = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (context.read<SessionStore>().isAuthed) {
      _loadedThisSession = true;
      _loadFirstPage();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _state = const SectionState.loading();
      _page = 1;
      _hasMore = true;
    });
    try {
      final result = await context.read<OrderRepository>().myOrders(page: 1);
      if (!mounted) return;
      setState(() {
        _state = SectionState.data(result.items);
        _hasMore = result.hasMore; // backend envelope, never inferred
      });
      _autoLoadIfUnderfilled();
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = SectionState.error(e));
    }
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (_state.status != SectionStatus.data) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThresholdPx) {
      _loadNextPage();
    }
  }

  /// Same dead-end guard as the category grid: a first page shorter than
  /// the viewport can never fire [_onScroll], so after each successful load
  /// check once whether the list is still unscrollable while `has_more`
  /// says more exist — and fetch directly if so.
  void _autoLoadIfUnderfilled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadingMore || !_hasMore) return;
      if (_state.status != SectionStatus.data) return;
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        return;
      }
      _loadNextPage();
    });
  }

  Future<void> _loadNextPage() async {
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    final nextPage = _page + 1;
    try {
      final result =
          await context.read<OrderRepository>().myOrders(page: nextPage);
      if (!mounted) return;
      setState(() {
        _state = SectionState.data([...?_state.data, ...result.items]);
        _page = nextPage;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
      _autoLoadIfUnderfilled();
    } catch (_) {
      // Loaded pages stay visible; the next scroll tick retries, and the
      // tail retry button covers underfilled lists that can't scroll.
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  void _openDetail(OrderSummary order) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailPage(orderName: order.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAuthed = context.watch<SessionStore>().isAuthed;
    if (isAuthed && !_loadedThisSession) {
      // Guest → authed while this page is open (inline login prompt):
      // initState never loaded, so trigger the first page now — otherwise
      // the skeleton would render forever.
      _loadedThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadFirstPage();
      });
    } else if (!isAuthed && _loadedThisSession) {
      _loadedThisSession = false; // re-arm for the next login
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        title: Text(l10n.ordersTitle),
      ),
      body: SafeArea(
        child: isAuthed ? _buildList(l10n) : _GuestPrompt(l10n: l10n),
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    return AsyncSection<List<OrderSummary>>(
      state: _state,
      skeleton: const Padding(
        padding: EdgeInsets.all(ZadSpacing.screenPadding),
        child: SectionSkeleton(height: 244),
      ),
      onRetry: _loadFirstPage,
      isEmpty: (orders) => orders.isEmpty,
      emptyBuilder: (context) => _EmptyOrders(l10n: l10n),
      builder: (context, orders) => ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(ZadSpacing.screenPadding),
        itemCount: orders.length +
            (_loadingMore || (_loadMoreFailed && _hasMore) ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= orders.length) {
            if (_loadMoreFailed && !_loadingMore) {
              return Center(
                child: TextButton(
                  key: const Key('loadMoreRetryButton'),
                  onPressed: _loadNextPage,
                  child: Text(l10n.retry),
                ),
              );
            }
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _OrderCard(
            order: orders[index],
            l10n: l10n,
            onTap: () => _openDetail(orders[index]),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.l10n, required this.onTap});

  final OrderSummary order;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final languageCode = locale.languageCode;
    return InkWell(
      key: Key('orderCard-${order.name}'),
      borderRadius: BorderRadius.circular(ZadRadii.tile),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ZadColors.surface,
          borderRadius: BorderRadius.circular(ZadRadii.tile),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ZadColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OrderStatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  formatDisplayDate(order.date, locale.toString()),
                  style: const TextStyle(fontSize: 12, color: ZadColors.muted),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.ordersItemCount(order.itemCount),
                  style: const TextStyle(fontSize: 12, color: ZadColors.muted),
                ),
                const Spacer(),
                Text(
                  formatPrice(order.grandTotal, languageCode),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: ZadColors.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.receipt_2, size: 48, color: ZadColors.muted),
            const SizedBox(height: 16),
            Text(
              l10n.ordersEmptyTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ZadColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestPrompt extends StatelessWidget {
  const _GuestPrompt({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.receipt_2, size: 48, color: ZadColors.muted),
            const SizedBox(height: 16),
            Text(
              l10n.authLoginRequiredTitle,
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
          ],
        ),
      ),
    );
  }
}
