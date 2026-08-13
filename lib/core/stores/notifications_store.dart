import 'package:flutter/foundation.dart';

import '../../data/notifications_repository.dart';
import '../session/session_store.dart';

/// Session-synced unread-notifications state (PRD F2 `notifications.
/// unread_count`/`mark_read`), exposed via `provider` above `MaterialApp`
/// — the home bell badge watches [unreadCount].
///
/// Notifications are a logged-in-only feature: the bell tap is gated with
/// `ensureLoggedIn`, and this store treats any call while guest as a no-op.
/// While authed it hydrates the count — at app boot via [restore] (after
/// `SessionStore.restore`), on login via its [SessionStore] listener, and
/// whenever NotificationsPage wants it fresh via [refresh]. Logout clears
/// everything, including any in-flight fetch (the FavouritesStore /
/// AddressStore session-boundary pattern: user B must never see user A's
/// count).
class NotificationsStore extends ChangeNotifier {
  NotificationsStore({
    required NotificationsRepository repository,
    SessionStore? session,
  })  : _repository = repository,
        _session = session {
    _authed = session?.isAuthed ?? false;
    session?.addListener(_handleSessionChanged);
  }

  final NotificationsRepository _repository;
  final SessionStore? _session;

  bool _authed = false;
  int _unreadCount = 0;
  Object? _error;

  /// Bumped on EVERY session transition (login and logout). Fetches and
  /// the mark-read decrement capture it when they start and act only if it
  /// is unchanged: an `_authed`-only guard cannot tell user B's session
  /// from user A's — a straggling response from before A's logout would
  /// otherwise corrupt B's badge.
  int _epoch = 0;

  /// The one in-flight `unread_count` fetch — concurrent [refresh] callers
  /// share it instead of double-fetching. Nulled on logout so a relogin's
  /// refresh can never adopt (or share) a stale fetch made with the
  /// previous account's token.
  Future<void>? _countInFlight;

  /// Resolves once the login-triggered hydrate (or logout reset) from the
  /// last [SessionStore] transition has settled — mirrors
  /// `FavouritesStore.sessionSyncDone` for deterministic tests.
  Future<void> get sessionSyncDone => _sessionSyncFuture ?? Future<void>.value();
  Future<void>? _sessionSyncFuture;

  /// Unread notifications for the badge; 0 while guest.
  int get unreadCount => _unreadCount;

  /// The last [refresh] failure; cleared by the next attempt. The badge
  /// simply keeps its previous count on failure — no error UI.
  Object? get error => _error;

  /// Hydrates at app boot when a session was restored (call once at
  /// startup, after `SessionStore.restore` has resolved). Never throws.
  Future<void> restore() async {
    _authed = _session?.isAuthed ?? false;
    if (_authed) await refresh();
  }

  /// Re-pulls `unread_count`. No-op while guest; never throws — failures
  /// land on [error]. Concurrent callers share a single in-flight fetch.
  Future<void> refresh() {
    if (!_authed) return Future<void>.value();
    final existing = _countInFlight;
    if (existing != null) return existing;
    final future = _fetchCount();
    _countInFlight = future;
    future.whenComplete(() {
      // Guarded reset: only clear the slot for our own fetch, never a
      // newer one (or the null a logout just wrote).
      if (identical(_countInFlight, future)) _countInFlight = null;
    });
    return future;
  }

  /// Marks [name] read and decrements the badge on success. Returns whether
  /// the server accepted the call, so NotificationsPage can roll back its
  /// optimistic row flip on failure. Never throws; no-op while guest.
  Future<bool> markRead(String name) async {
    if (!_authed || name.isEmpty) return false;
    final epoch = _epoch;
    try {
      await _repository.markRead(name);
    } catch (_) {
      return false;
    }
    // Decrement only within the same session: a straggling completion from
    // before a logout must not corrupt the next account's badge.
    if (epoch == _epoch && _unreadCount > 0) {
      _unreadCount -= 1;
      notifyListeners();
    }
    return true;
  }

  @override
  void dispose() {
    _session?.removeListener(_handleSessionChanged);
    super.dispose();
  }

  // -- internals ---------------------------------------------------------

  Future<void> _fetchCount() async {
    final epoch = _epoch;
    _error = null;
    try {
      final count = await _repository.unreadCount();
      // Adopt only within the fetch's own session: a straggler from before
      // a logout must never write the next account's badge, no matter when
      // it lands (`_authed` alone cannot tell the two sessions apart).
      if (epoch == _epoch) {
        _unreadCount = count;
        notifyListeners();
      }
    } catch (e) {
      // Same epoch guard: a stale failure must not poison the new session.
      if (epoch == _epoch) _error = e;
    }
  }

  void _handleSessionChanged() {
    final authed = _session!.isAuthed;
    if (authed == _authed) return;
    _authed = authed;
    _epoch += 1; // every transition invalidates in-flight work
    if (authed) {
      _sessionSyncFuture = refresh();
    } else {
      _unreadCount = 0;
      _error = null;
      _sessionSyncFuture = null;
      // Invalidate any hung fetch from the previous account: a relogin's
      // refresh() must issue a fresh unread_count with the new token.
      _countInFlight = null;
      notifyListeners();
    }
  }
}
