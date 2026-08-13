import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/stores/locale_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('LocaleStore', () {
    test('defaults to Arabic before and after load with nothing saved',
        () async {
      final store = LocaleStore();
      expect(store.locale, const Locale('ar'));

      await store.load();

      expect(store.locale, const Locale('ar'));
      expect(store.isArabic, isTrue);
    });

    test('load() restores a saved English choice', () async {
      SharedPreferences.setMockInitialValues({kLocaleCacheKey: 'en'});
      final store = LocaleStore();

      await store.load();

      expect(store.locale, const Locale('en'));
      expect(store.isArabic, isFalse);
    });

    test('load() ignores an unknown saved value and keeps Arabic', () async {
      SharedPreferences.setMockInitialValues({kLocaleCacheKey: 'fr'});
      final store = LocaleStore();

      await store.load();

      expect(store.locale, const Locale('ar'));
    });

    test('setLocale() switches, notifies, and persists', () async {
      final store = LocaleStore();
      var notified = 0;
      store.addListener(() => notified++);

      await store.setLocale(const Locale('en'));

      expect(store.locale, const Locale('en'));
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kLocaleCacheKey), 'en');
    });

    test('setLocale() with the current locale is a no-op', () async {
      final store = LocaleStore();
      var notified = 0;
      store.addListener(() => notified++);

      await store.setLocale(const Locale('ar'));

      expect(notified, 0);
    });

    test('a fresh store load()s back the persisted choice', () async {
      final first = LocaleStore();
      await first.setLocale(const Locale('en'));

      final second = LocaleStore();
      await second.load();

      expect(second.locale, const Locale('en'));
    });
  });
}
