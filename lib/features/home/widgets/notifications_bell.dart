import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/stores/notifications_store.dart';
import '../../../core/theme.dart';
import '../../auth/login_required_sheet.dart';

/// The home header's notifications bell (PRD F2): unread badge from
/// [NotificationsStore], tap → `/notifications`. Guests get the shared
/// login sheet first and proceed only if they end up logged in.
class NotificationsBell extends StatelessWidget {
  const NotificationsBell({super.key});

  Future<void> _onTap(BuildContext context) async {
    final ok = await ensureLoggedIn(context);
    if (!ok || !context.mounted) return;
    await Navigator.pushNamed(context, '/notifications');
    // Coming back: the page's mark-reads already decremented the badge,
    // but a resync catches anything that changed server-side meanwhile.
    if (context.mounted) context.read<NotificationsStore>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final count = context.watch<NotificationsStore>().unreadCount;
    return InkWell(
      key: const Key('notificationsBell'),
      borderRadius: BorderRadius.circular(10),
      onTap: () => _onTap(context),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Iconsax.notification, color: ZadColors.ink, size: 24),
            if (count > 0)
              PositionedDirectional(
                top: -4,
                end: -4,
                child: Container(
                  key: const Key('notificationsBadge'),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 9,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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
