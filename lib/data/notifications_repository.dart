import '../core/api/api_client.dart';
import '../core/json_utils.dart';

/// One row of the caller's notification feed (PRD F2 `notifications.list`):
/// `{name, title, body, read, creation}`. `body` may carry the HTML the
/// backend's push templates rendered — display through the shared
/// minimal-HTML helpers, never verbatim.
class AppNotification {
  const AppNotification({
    required this.name,
    required this.title,
    required this.body,
    required this.read,
    required this.creation,
  });

  final String name;
  final String title;
  final String body;
  final bool read;
  final String creation;

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        name: json['name'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        read: toBool(json['read']),
        creation: json['creation'] as String? ?? '',
      );

  AppNotification markedRead() => AppNotification(
        name: name,
        title: title,
        body: body,
        read: true,
        creation: creation,
      );
}

/// One page of `notifications.list`: `{items, page, has_more}` — `has_more`
/// straight from the backend envelope, never inferred from page length.
class NotificationsResult {
  const NotificationsResult({
    required this.items,
    required this.page,
    required this.hasMore,
  });

  final List<AppNotification> items;
  final int page;
  final bool hasMore;
}

/// Thin, typed wrapper over `grocery.api.notifications.*` (PRD F2). Every
/// method requires a logged-in session — the backend returns 401 for
/// guests, which [ApiClient] surfaces as `UnauthenticatedException`. Call
/// sites gate guest taps with `ensureLoggedIn`.
class NotificationsRepository {
  NotificationsRepository(this._client);

  final ApiClient _client;

  /// The caller's notifications, newest first, 20 per page.
  Future<NotificationsResult> list({int page = 1}) async {
    final data = await _client.get(
      'grocery.api.notifications.list',
      params: {'page': page},
    );
    final map = data as Map<String, dynamic>;
    final items = map['items'];
    return NotificationsResult(
      items: items is List
          ? items
              .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      page: toInt(map['page']) ?? page,
      hasMore: toBool(map['has_more']),
    );
  }

  /// `{count}` of the caller's unread notifications — drives the home bell
  /// badge.
  Future<int> unreadCount() async {
    final data = await _client.get('grocery.api.notifications.unread_count');
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    return toInt(map['count']) ?? 0;
  }

  /// Marks one notification read (ownership-guarded server-side).
  Future<void> markRead(String name) async {
    await _client.post(
      'grocery.api.notifications.mark_read',
      data: {'name': name},
    );
  }
}
