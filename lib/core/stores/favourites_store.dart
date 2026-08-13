import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/wishlist_repository.dart';
import '../../models/product.dart';
import '../session/session_store.dart';

/// Server-synced favourites state (PRD F8 `wishlist.list/add/remove`),
/// exposed via `provider` above `MaterialApp`.
///
/// Favourites are a logged-in-only feature: call sites gate guest heart
/// taps with `ensureLoggedIn` (LoginRequiredSheet), and this store treats
/// any mutation while guest as a no-op, so guests can never build up
/// phantom local favourites. While authed it hydrates from `wishlist.list`
/// — at app start via [restore], on login via its [SessionStore] listener,
/// and whenever the favourites tab is opened via [refresh] — and applies
/// [add]/[remove] optimistically, rolling the flip back if the server call
/// fails (the heart visibly reverting is the error surface; mutations never
/// throw, since heart taps are fire-and-forget call sites). Logout clears
/// everything.
///
/// ItemCard payloads from any listing endpoint can [seed] the store with
/// their `is_favourite` flags — seed-only, never un-favouriting.
class FavouritesStore extends ChangeNotifier {
  FavouritesStore({required WishlistRepository repository, SessionStore? session})
    : _repository = repository,
      _session = session {
    _authed = session?.isAuthed ?? false;
    session?.addListener(_handleSessionChanged);
  }

  final WishlistRepository _repository;
  final SessionStore? _session;

  bool _authed = false;
  bool _busy = false;
  Object? _error;
  bool _hydrated = false;

  /// Bumped on EVERY session transition (login and logout). Fetches and
  /// mutation rollbacks capture it when they start and act only if it is
  /// unchanged on completion: an `_authed`-only guard cannot tell user B's
  /// session from user A's — a straggling response from before A's logout
  /// would otherwise overwrite B's freshly hydrated store.
  int _epoch = 0;

  final Set<String> _itemCodes = <String>{};
  List<Product> _items = <Product>[];

  /// Optimistic mutations still in flight — folded over any concurrently
  /// arriving `wishlist.list` snapshot, so a hydrate (e.g. the
  /// login-triggered one racing a heart tap made right after the login
  /// sheet popped) can never clobber a flip the server has not recorded
  /// yet. Also shields [seed]: a stale ItemCard payload cannot resurrect a
  /// heart with an un-favourite in flight.
  final Set<String> _pendingAdds = <String>{};
  final Set<String> _pendingRemoves = <String>{};

  /// The one in-flight `wishlist.list` fetch — concurrent [refresh] callers
  /// (tab activation + the login listener, the canonical overlap) share it
  /// instead of double-fetching.
  Future<void>? _listInFlight;

  /// Per-item mutation chain: a rapid double-toggle would otherwise race
  /// `wishlist.add` and `wishlist.remove` on the wire, letting the server
  /// commit them in either order and drift from the UI until the next
  /// hydrate. Each mutation awaits the previous one for the same item, so
  /// requests reach the server in tap order (idempotent server ops make
  /// this safe).
  final Map<String, Future<void>> _mutationInFlight = <String, Future<void>>{};

  /// Resolves once the login-triggered hydrate (or the logout reset) from
  /// the last [SessionStore] transition has settled. Mirrors
  /// `CartStore.sessionSyncDone`: the store is correct without anyone
  /// reading this — it exists so tests (or a future syncing UI) can await
  /// the transition deterministically instead of racing the listener.
  Future<void> get sessionSyncDone => _sessionSyncFuture ?? Future<void>.value();
  Future<void>? _sessionSyncFuture;

  /// Whether a `wishlist.list` fetch is currently in flight.
  bool get busy => _busy;

  /// The last [refresh]/hydrate failure; cleared by the next attempt.
  /// Mutation failures never land here — they roll the optimistic flip
  /// back instead, so one failed heart tap cannot flip the whole
  /// favourites page into its error state.
  Object? get error => _error;

  /// Whether at least one `wishlist.list` snapshot has been applied since
  /// login — the favourites page shows a skeleton until this flips, and a
  /// background [refresh] after it keeps showing the previous data.
  bool get hydrated => _hydrated;

  /// The hydrated favourite ItemCards, newest first (server order). An
  /// optimistic [remove] drops its card immediately; an [add] made outside
  /// the favourites page shows up here on the next [refresh].
  List<Product> get items => List.unmodifiable(_items);

  /// Whether [itemCode] is currently favourited — what every heart icon
  /// watches.
  bool contains(String itemCode) => _itemCodes.contains(itemCode);

  /// Favourites [itemCode]: flips the heart immediately, posts
  /// `wishlist.add`, and rolls the flip back if the server call fails.
  /// No-op while guest or when already favourited.
  Future<void> add(String itemCode) async {
    if (!_authed || itemCode.isEmpty || _itemCodes.contains(itemCode)) return;
    _itemCodes.add(itemCode);
    _pendingAdds.add(itemCode);
    _pendingRemoves.remove(itemCode);
    notifyListeners();
    final epoch = _epoch;
    await _chainMutation(itemCode, () async {
      try {
        await _whenListSettles();
        await _repository.add(itemCode);
      } catch (_) {
        // Roll back — only within the same session; after a logout (or a
        // relogin) the new session's state stays authoritative.
        if (epoch == _epoch && _itemCodes.remove(itemCode)) notifyListeners();
      } finally {
        _pendingAdds.remove(itemCode);
      }
    });
  }

  /// Un-favourites [itemCode]: flips the heart (and drops the card from
  /// [items]) immediately, posts `wishlist.remove`, and restores both —
  /// the card back at its original position — if the server call fails.
  /// No-op while guest or when not favourited.
  Future<void> remove(String itemCode) async {
    if (!_authed || !_itemCodes.contains(itemCode)) return;
    _itemCodes.remove(itemCode);
    final index = _items.indexWhere((p) => (p.itemCode ?? p.id) == itemCode);
    final removed = index >= 0 ? _items.removeAt(index) : null;
    _pendingRemoves.add(itemCode);
    _pendingAdds.remove(itemCode);
    notifyListeners();
    final epoch = _epoch;
    await _chainMutation(itemCode, () async {
      try {
        await _whenListSettles();
        await _repository.remove(itemCode);
      } catch (_) {
        // Roll back — only within the same session; after a logout (or a
        // relogin) the new session's state stays authoritative, and user
        // A's card must never be re-inserted into user B's list.
        if (epoch == _epoch) {
          _itemCodes.add(itemCode);
          if (removed != null) {
            _items.insert(math.min(index, _items.length), removed);
          }
          notifyListeners();
        }
      } finally {
        _pendingRemoves.remove(itemCode);
      }
    });
  }

  /// Queues [body] behind any in-flight mutation for the same item so
  /// same-item requests hit the wire in tap order. [body] never throws
  /// (both mutation bodies swallow into rollback), so a queued successor
  /// always runs.
  Future<void> _chainMutation(String itemCode, Future<void> Function() body) {
    final prior = _mutationInFlight[itemCode] ?? Future<void>.value();
    final mutation = prior.then((_) => body());
    _mutationInFlight[itemCode] = mutation;
    return mutation.whenComplete(() {
      if (identical(_mutationInFlight[itemCode], mutation)) {
        _mutationInFlight.remove(itemCode);
      }
    });
  }

  Future<void> toggle(String itemCode) =>
      _itemCodes.contains(itemCode) ? remove(itemCode) : add(itemCode);

  /// Seeds heart state from ItemCard payloads (`is_favourite`) returned by
  /// any listing endpoint (home best items, category pages, search
  /// results, item detail). Seed-only: a `false`/absent flag never
  /// un-favourites, and a stale `true` cannot resurrect an un-favourite
  /// still in flight.
  void seed(Iterable<Product> products) {
    // Guests can never hold hearts, even from a stale authed-era payload
    // landing after logout (the class invariant above).
    if (!_authed) return;
    var changed = false;
    for (final product in products) {
      if (product.isFavourite != true) continue;
      final code = product.itemCode ?? product.id;
      if (code.isEmpty || _pendingRemoves.contains(code)) continue;
      changed = _itemCodes.add(code) || changed;
    }
    if (changed) notifyListeners();
  }

  /// Hydrates at app boot when a session was restored (mirrors
  /// `CartStore.restore` — call once at startup, after
  /// `SessionStore.restore` has resolved). Never throws: an offline boot
  /// leaves [error] set and the next [refresh] retries.
  Future<void> restore() async {
    _authed = _session?.isAuthed ?? false;
    if (_authed) await refresh();
  }

  /// Re-pulls `wishlist.list` and adopts it as the new truth (modulo
  /// in-flight optimistic mutations). No-op while guest; never throws —
  /// failures land on [error] for the page to render. Concurrent callers
  /// share a single in-flight fetch.
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
      final products = await _repository.list();
      // Adopt only within the fetch's own session: a straggler from before
      // a logout must never populate the next account's store, no matter
      // when it lands (`_authed` alone cannot tell the two sessions apart).
      if (epoch == _epoch) {
        _applyList(products);
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

  void _applyList(List<Product> products) {
    _items = [
      for (final product in products)
        if (!_pendingRemoves.contains(product.itemCode ?? product.id)) product,
    ];
    _itemCodes
      ..clear()
      ..addAll(_items.map((p) => p.itemCode ?? p.id))
      ..addAll(_pendingAdds);
  }

  /// Waits for any in-flight `wishlist.list` to settle before a mutation
  /// posts, so the snapshot applies first and the pending-set fold-over —
  /// not luck of arrival order — decides the final state. Never throws
  /// ([_fetchList] swallows failures into [error]).
  Future<void> _whenListSettles() async {
    while (true) {
      final inFlight = _listInFlight;
      if (inFlight == null) return;
      await inFlight;
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
      _itemCodes.clear();
      _items = <Product>[];
      _pendingAdds.clear();
      _pendingRemoves.clear();
      _hydrated = false;
      _error = null;
      _sessionSyncFuture = null;
      // Invalidate any hung fetch from the previous account: a relogin's
      // refresh() must issue a fresh list with the new token, never adopt
      // (or share) the stale one — otherwise user B could briefly see
      // user A's favourites.
      _listInFlight = null;
      notifyListeners();
    }
  }
}
