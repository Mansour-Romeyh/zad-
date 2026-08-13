import 'package:flutter/foundation.dart';

import '../../data/address_repository.dart';
import '../session/session_store.dart';

/// Server-synced address book (PRD F4), exposed via `provider` above
/// `MaterialApp` so the address screens AND the home location header (which
/// shows the default address) share one truth.
///
/// Addresses are a logged-in-only feature: entry points gate guests with
/// `ensureLoggedIn` (LoginRequiredSheet) and this store no-ops any read
/// while guest. While authed it hydrates from `address.list` — at app boot
/// via [restore], on login via its [SessionStore] listener, and whenever an
/// address screen opens via [refresh]. Mutations post to the server and
/// re-pull the list, so ordering and default-exclusivity always come from
/// the server (which orders default-first and clears other defaults
/// atomically) rather than local bookkeeping. Unlike the fire-and-forget
/// heart taps, mutations rethrow their [Exception] — every call site is an
/// explicit form/button action that surfaces the failure itself.
///
/// Also owns the once-per-session "add your first address" nudge flag (PRD
/// A3): [shouldShowNudge] turns true when a hydrated, authed session has no
/// addresses and the nudge has not been consumed yet; logout re-arms it.
class AddressStore extends ChangeNotifier {
  AddressStore({required AddressRepository repository, SessionStore? session})
    : _repository = repository,
      _session = session {
    _authed = session?.isAuthed ?? false;
    session?.addListener(_handleSessionChanged);
  }

  final AddressRepository _repository;
  final SessionStore? _session;

  bool _authed = false;
  bool _busy = false;
  Object? _error;
  bool _hydrated = false;
  bool _nudgeConsumed = false;

  /// Bumped on EVERY session transition (login and logout). Fetches capture
  /// it when they start and adopt results only if it is unchanged: an
  /// `_authed`-only guard cannot tell user B's session from user A's — a
  /// straggling response from before A's logout would otherwise overwrite
  /// B's freshly hydrated address book.
  int _epoch = 0;

  List<AddressModel> _addresses = <AddressModel>[];

  /// The one in-flight `address.list` fetch — concurrent [refresh] callers
  /// (screen open + the login listener) share it instead of double-fetching.
  Future<void>? _listInFlight;

  /// Resolves once the login-triggered hydrate (or logout reset) from the
  /// last [SessionStore] transition has settled — mirrors
  /// `CartStore.sessionSyncDone` for deterministic tests.
  Future<void> get sessionSyncDone => _sessionSyncFuture ?? Future<void>.value();
  Future<void>? _sessionSyncFuture;

  /// Whether an `address.list` fetch is currently in flight.
  bool get busy => _busy;

  /// The last [refresh] failure; cleared by the next attempt. Mutation
  /// failures never land here — they rethrow to their call site instead.
  Object? get error => _error;

  /// Whether at least one `address.list` snapshot has been applied since
  /// login.
  bool get hydrated => _hydrated;

  /// Server-ordered addresses (default first, then newest first).
  List<AddressModel> get addresses => List.unmodifiable(_addresses);

  /// The default address, shown by the home location header — `null` while
  /// guest, un-hydrated, or when no address is marked default.
  AddressModel? get defaultAddress {
    for (final address in _addresses) {
      if (address.isDefault) return address;
    }
    return null;
  }

  /// PRD A3 first-login nudge: true exactly while an authed, hydrated
  /// session has no addresses and the (once-per-session) nudge is unspent.
  /// The home shell watches this and calls [consumeNudge] before showing
  /// the sheet.
  bool get shouldShowNudge =>
      _authed && _hydrated && _addresses.isEmpty && !_nudgeConsumed;

  /// Spends the once-per-session nudge (re-armed by logout). No notify —
  /// callers consume it right before presenting the sheet.
  void consumeNudge() => _nudgeConsumed = true;

  /// Hydrates at app boot when a session was restored (call after
  /// `SessionStore.restore`, like the other stores). Never throws — an
  /// offline boot leaves [error] set and the next [refresh] retries.
  Future<void> restore() async {
    _authed = _session?.isAuthed ?? false;
    if (_authed) await refresh();
  }

  /// Re-pulls `address.list` and adopts it as the new truth. No-op while
  /// guest; never throws — failures land on [error] for the screen to
  /// render. Concurrent callers share a single in-flight fetch.
  Future<void> refresh() {
    if (!_authed) return Future<void>.value();
    final existing = _listInFlight;
    if (existing != null) return existing;
    final future = _fetchList();
    _listInFlight = future;
    future.whenComplete(() {
      // Guarded reset: only clear the slot for our own fetch, never a
      // newer one started by a straggling awaiter's continuation.
      if (identical(_listInFlight, future)) _listInFlight = null;
    });
    return future;
  }

  /// Creates an address and re-pulls the list. The very first address is
  /// created as the default automatically (there is nothing else it could
  /// defer to). Returns the created address — its zone fields carry the
  /// coverage result the form surfaces (PRD E5, informational).
  Future<AddressModel> create({
    required String label,
    required String addressLine,
    required String city,
    double? lat,
    double? lng,
  }) async {
    final created = await _repository.create(
      label: label,
      addressLine: addressLine,
      city: city,
      // Backend signature requires lat/lng; 0 = "no location captured".
      lat: lat ?? 0,
      lng: lng ?? 0,
      // Only a hydrated-empty book auto-defaults: with the snapshot missing
      // (offline boot, hydrate in flight) the server may well hold a real
      // default this create must not silently steal.
      isDefault: _hydrated && _addresses.isEmpty,
    );
    await refresh();
    return created;
  }

  /// Updates an address and re-pulls the list. Returns the updated address
  /// with zone fields for its (possibly new) coordinates.
  Future<AddressModel> update(
    String name, {
    String? label,
    String? addressLine,
    String? city,
    double? lat,
    double? lng,
  }) async {
    final updated = await _repository.update(
      name,
      label: label,
      addressLine: addressLine,
      city: city,
      lat: lat,
      lng: lng,
    );
    await refresh();
    return updated;
  }

  /// Deletes an address and drops it locally (the server does not promote
  /// a new default, so no re-list is needed).
  Future<void> delete(String name) async {
    await _repository.delete(name);
    final before = _addresses.length;
    _addresses = [for (final a in _addresses) if (a.name != name) a];
    if (_addresses.length != before) notifyListeners();
  }

  /// Marks [name] as default, then re-pulls the list so exclusivity (the
  /// server cleared every other default) and default-first ordering come
  /// straight from the server.
  Future<void> setDefault(String name) async {
    await _repository.setDefault(name);
    await refresh();
  }

  @override
  void dispose() {
    _session?.removeListener(_handleSessionChanged);
    super.dispose();
  }

  // -- internals ---------------------------------------------------------

  Future<void> _fetchList() async {
    final epoch = _epoch;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final addresses = await _repository.list();
      // Adopt only within the fetch's own session: a straggler from before
      // a logout must never populate the next account's store, no matter
      // when it lands (`_authed` alone cannot tell the two sessions apart).
      if (epoch == _epoch) {
        _addresses = addresses;
        // Latch the nudge on the session's first snapshot: a session that
        // starts WITH addresses never nudges — deleting down to zero later
        // must not pop the "first address" sheet (PRD A3 scopes it to
        // after login).
        if (!_hydrated && addresses.isNotEmpty) _nudgeConsumed = true;
        _hydrated = true;
      }
    } catch (e) {
      // Same epoch guard: a stale failure must not poison the new session.
      if (epoch == _epoch) _error = e;
    } finally {
      _busy = false;
      notifyListeners();
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
      _addresses = <AddressModel>[];
      _hydrated = false;
      _error = null;
      _nudgeConsumed = false; // a later login gets its own nudge
      _sessionSyncFuture = null;
      // Invalidate any hung fetch from the previous account: a relogin's
      // refresh() must issue a fresh list with the new token, never adopt
      // (or share) the stale one — otherwise user B could briefly see
      // user A's address book.
      _listInFlight = null;
      notifyListeners();
    }
  }
}
