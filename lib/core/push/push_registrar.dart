import 'dart:async';

import '../../data/profile_repository.dart';
import '../session/session_store.dart';
import 'push_service.dart';

/// Keeps the backend's copy of this device's FCM token current
/// (`profile.register_device` — PRD Part G): registers when a session is
/// already authed at startup, on every guest -> authed transition, and on
/// every FCM token rotation while authed. Guests are never registered (the
/// endpoint requires a login), and nothing here can throw into the session
/// flow — `ProfileRepository.registerDevice` swallows all failures by
/// contract.
class PushRegistrar {
  PushRegistrar({
    required PushService pushService,
    required ProfileRepository profileRepository,
    required SessionStore sessionStore,
  })  : _push = pushService,
        _profile = profileRepository,
        _session = sessionStore;

  final PushService _push;
  final ProfileRepository _profile;
  final SessionStore _session;

  StreamSubscription<String>? _refreshSub;
  bool _wasAuthed = false;

  /// Begins listening; completes after the initial registration attempt so
  /// callers (and tests) can await a deterministic state.
  Future<void> start() async {
    _wasAuthed = _session.isAuthed;
    _session.addListener(_onSessionChanged);
    _refreshSub = _push.onTokenRefresh.listen(_onTokenRefresh);
    if (_session.isAuthed) await _register();
  }

  void dispose() {
    _session.removeListener(_onSessionChanged);
    _refreshSub?.cancel();
  }

  void _onSessionChanged() {
    final authed = _session.isAuthed;
    // Edge-triggered on login only: SessionStore notifies for more than
    // status flips, and re-registering the same token on every notify would
    // spam the backend.
    if (authed && !_wasAuthed) _register();
    _wasAuthed = authed;
  }

  void _onTokenRefresh(String token) {
    if (_session.isAuthed) _profile.registerDevice(token);
  }

  Future<void> _register() async {
    // Permission result deliberately ignored — see PushService.
    await _push.requestPermission();
    final token = await _push.getToken();
    if (token != null && token.isNotEmpty) {
      await _profile.registerDevice(token);
    }
  }
}
