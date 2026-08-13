import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted key for the user's language choice (`'ar'` | `'en'`).
const kLocaleCacheKey = 'zad.locale';

/// App language store — Arabic-first market, so the app boots in Arabic
/// regardless of the device language. An explicit in-app choice (profile →
/// language) is persisted and restored on the next launch.
class LocaleStore extends ChangeNotifier {
  /// Languages the app ships translations for, Arabic first.
  static const supported = [Locale('ar'), Locale('en')];

  Locale _locale = const Locale('ar');

  Locale get locale => _locale;
  bool get isArabic => _locale.languageCode == 'ar';

  /// Restores a previously saved choice. Keeps the Arabic default when
  /// nothing (or an unknown value) is saved — best-effort, never throws.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(kLocaleCacheKey);
      final match = supported.where((l) => l.languageCode == saved);
      if (match.isNotEmpty &&
          match.first.languageCode != _locale.languageCode) {
        _locale = match.first;
        notifyListeners();
      }
    } catch (_) {
      // Corrupt/unreadable prefs read as "no saved choice".
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (locale.languageCode == _locale.languageCode) return;
    _locale = Locale(locale.languageCode);
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLocaleCacheKey, _locale.languageCode);
    } catch (_) {
      // Best-effort: a failed write just means the next boot is Arabic.
    }
  }
}
