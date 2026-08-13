import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/content_repository.dart';
import '../../models/app_config.dart';
import '../constants.dart';

/// Boot-time app config (PRD F2 `content.get_app_config` / D1.1): splash
/// look, maintenance gate, support phone. Guest-accessible — NOT session
/// scoped, so no login/logout wiring.
///
/// Resolution order on [load]: fresh network fetch (bounded by
/// [fetchTimeout], PRD "2s timeout") → cached last-good config from
/// `shared_preferences` → bundled defaults ([AppConfig]'s constructor
/// defaults). Never throws; [config] is always usable — a dead backend can
/// slow boot down by at most the timeout, never block it.
class AppConfigStore extends ChangeNotifier {
  AppConfigStore({
    required ContentRepository repository,
    this.fetchTimeout = const Duration(seconds: 2),
  }) : _repository = repository;

  final ContentRepository _repository;

  /// Cap on how long a boot waits for the network config.
  final Duration fetchTimeout;

  AppConfig _config = const AppConfig();
  bool _loaded = false;

  /// The active config — bundled defaults until [load] resolves.
  AppConfig get config => _config;

  /// Whether [load] has completed (with whatever source won).
  bool get loaded => _loaded;

  /// Whether the backend is gating the app (PRD D1.1). A cached
  /// maintenance flag counts: "last-good" means last successfully fetched,
  /// and a maintenance answer is a successful fetch.
  bool get maintenanceMode => _config.maintenanceMode;

  /// Boot-time load — see the class doc for the resolution order.
  Future<void> load() async {
    try {
      final fresh = await _repository.getAppConfig().timeout(fetchTimeout);
      _config = fresh;
      _loaded = true;
      notifyListeners();
      await _writeCache(fresh);
    } catch (_) {
      final cached = await _readCache();
      if (cached != null) _config = cached;
      _loaded = true;
      notifyListeners();
    }
  }

  /// Maintenance-screen retry: only a *successful fresh fetch* may change
  /// state — a network failure neither clears the gate (the server's
  /// status is unknown) nor falls back to cache (which is what put us
  /// here). Returns whether the fetch succeeded.
  Future<bool> refresh() async {
    try {
      final fresh = await _repository.getAppConfig().timeout(fetchTimeout);
      _config = fresh;
      _loaded = true;
      notifyListeners();
      await _writeCache(fresh);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeCache(AppConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kAppConfigCacheKey, jsonEncode(config.toJson()));
    } catch (_) {
      // Best-effort: a failed cache write just means the next offline boot
      // falls back to bundled defaults.
    }
  }

  Future<AppConfig?> _readCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kAppConfigCacheKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      return AppConfig.fromJson(decoded);
    } catch (_) {
      return null; // Corrupt cache reads as "no cache".
    }
  }
}
