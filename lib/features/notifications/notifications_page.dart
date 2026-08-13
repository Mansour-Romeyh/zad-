import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/html_text.dart';
import '../../core/session/session_store.dart';
import '../../core/stores/notifications_store.dart';
import '../../core/theme.dart';
import '../../data/notifications_repository.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/section_state.dart';

/// `/notifications` (PRD F2 `notifications.list`): the caller's feed,
/// newest first, paged like the orders list (`has_more` straight from the
/// backend envelope). Tapping an unread row marks it read — optimistically
/// in the row, and through [NotificationsStore.markRead] so the home bell
/// badge decrements too (rolled back if the server refuses). Guests (deep
/// link) get a login prompt.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _loadMoreThresholdPx = 200;

  final _scrollController = ScrollController();

  SectionState<List<AppNotification>> _state = const SectionState.loading();
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// The last next-page load failed. A scrollable list would retry on the
  /// next scroll tick anyway, but an UNDERFILLED list has no scroll tick —
  /// so the tail slot renders a retry button instead of nothing.
  bool _loadMoreFailed = false;

  /// Whether a first-page load ever ran for the current authed stint — a
  /// mid-session force-logout flips the body to the guest prompt, and the
  /// user who logs back in lands here without a new initState, so [build]
  /// re-triggers the load on that transition (same pattern as OrdersPage).
  bool _loadedThisSession = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (context.read<SessionStore>().isAuthed) {
      _loadedThisSession = true;
      _loadFirstPage();
      // The badge may be stale (a push landed while the app was open) —
      // opening the page is the natural moment to resync it.
      context.read<NotificationsStore>().refresh();
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
      final result =
          await context.read<NotificationsRepository>().list(page: 1);
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

  /// Same dead-end guard as the orders/category lists: a first page shorter
  /// than the viewport can never fire [_onScroll].
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
          await context.read<NotificationsRepository>().list(page: nextPage);
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

  Future<void> _onTapNotification(int index, AppNotification notification) async {
    if (notification.read) return;
    // Optimistic: the row reads immediately; the store call decrements the
    // badge on success. Roll the row back if the server refused.
    _flipRead(index, notification.markedRead());
    final ok =
        await context.read<NotificationsStore>().markRead(notification.name);
    if (!ok && mounted) _flipRead(index, notification);
  }

  void _flipRead(int index, AppNotification replacement) {
    final items = _state.data;
    if (items == null || index >= items.length) return;
    final updated = [...items];
    updated[index] = replacement;
    setState(() => _state = SectionState.data(updated));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAuthed = context.watch<SessionStore>().isAuthed;
    if (isAuthed && !_loadedThisSession) {
      // Guest → authed while this page is open: initState never loaded, so
      // trigger the first page now — otherwise the skeleton renders forever.
      _loadedThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadFirstPage();
        context.read<NotificationsStore>().refresh();
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
        title: Text(l10n.notificationsTitle),
      ),
      body: SafeArea(
        child: isAuthed ? _buildList(l10n) : _GuestPrompt(l10n: l10n),
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n) {
    return AsyncSection<List<AppNotification>>(
      state: _state,
      skeleton: const Padding(
        padding: EdgeInsets.all(ZadSpacing.screenPadding),
        child: SectionSkeleton(height: 244),
      ),
      onRetry: _loadFirstPage,
      isEmpty: (items) => items.isEmpty,
      emptyBuilder: (context) => _EmptyNotifications(l10n: l10n),
      builder: (context, items) => ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.all(ZadSpacing.screenPadding),
        itemCount: items.length +
            (_loadingMore || (_loadMoreFailed && _hasMore) ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index >= items.length) {
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
          return _NotificationCard(
            notification: items[index],
            onTap: () => _onTapNotification(index, items[index]),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  String _formatCreation(BuildContext context) {
    final parsed = DateTime.tryParse(notification.creation);
    if (parsed == null) return notification.creation;
    final locale = Localizations.localeOf(context).toString();
    return DateFormat.yMMMd(locale).add_Hm().format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final unread = !notification.read;
    final body = htmlToPlainText(notification.body);
    return InkWell(
      key: Key('notification-${notification.name}'),
      borderRadius: BorderRadius.circular(ZadRadii.tile),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: unread ? ZadColors.paleGreen : ZadColors.surface,
          borderRadius: BorderRadius.circular(ZadRadii.tile),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (unread) ...[
                  Container(
                    key: Key('unreadDot-${notification.name}'),
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: ZadColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    notification.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                      color: ZadColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: ZadColors.ink,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _formatCreation(context),
              style: const TextStyle(fontSize: 11, color: ZadColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.notification, size: 48, color: ZadColors.muted),
            const SizedBox(height: 16),
            Text(
              l10n.notificationsEmptyTitle,
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
      padding:
          const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.notification, size: 48, color: ZadColors.muted),
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
