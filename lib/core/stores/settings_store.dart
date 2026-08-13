import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted key for the order-placed confirmation sound toggle.
const kOrderSoundEnabledKey = 'zad.orderSoundEnabled';

/// User-preferences store (persisted via `shared_preferences`, like
/// [LocaleStore]). Currently just the order-placed confirmation sound + haptic
/// toggle. Defaults ON; an explicit choice from profile settings is restored
/// on the next launch.
class SettingsStore extends ChangeNotifier {
  bool _orderSoundEnabled = true;

  /// Whether the order-placed pip + haptic play. Default `true`.
  bool get orderSoundEnabled => _orderSoundEnabled;

  /// Restores a previously saved choice. Keeps the default when nothing (or an
  /// unreadable value) is saved — best-effort, never throws.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(kOrderSoundEnabledKey);
      if (saved != null && saved != _orderSoundEnabled) {
        _orderSoundEnabled = saved;
        notifyListeners();
      }
    } catch (_) {
      // Corrupt/unreadable prefs read as "no saved choice".
    }
  }

  Future<void> setOrderSoundEnabled(bool value) async {
    if (value == _orderSoundEnabled) return;
    _orderSoundEnabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kOrderSoundEnabledKey, value);
    } catch (_) {
      // Best-effort: a failed write just means the next boot uses the default.
    }
  }
}
