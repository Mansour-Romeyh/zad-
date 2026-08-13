import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zad/core/stores/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SettingsStore', () {
    test('defaults orderSoundEnabled to true, before and after load', () async {
      final store = SettingsStore();
      expect(store.orderSoundEnabled, isTrue);
      await store.load();
      expect(store.orderSoundEnabled, isTrue);
    });

    test('load() restores a saved false', () async {
      SharedPreferences.setMockInitialValues({kOrderSoundEnabledKey: false});
      final store = SettingsStore();
      await store.load();
      expect(store.orderSoundEnabled, isFalse);
    });

    test('load() tolerates corrupt prefs and keeps the default', () async {
      SharedPreferences.setMockInitialValues({kOrderSoundEnabledKey: 'not-a-bool'});
      final store = SettingsStore();
      await store.load(); // must not throw
      expect(store.orderSoundEnabled, isTrue);
    });

    test('setOrderSoundEnabled(false) flips, notifies once, and persists', () async {
      final store = SettingsStore();
      var notified = 0;
      store.addListener(() => notified++);

      await store.setOrderSoundEnabled(false);

      expect(store.orderSoundEnabled, isFalse);
      expect(notified, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kOrderSoundEnabledKey), isFalse);
    });

    test('setOrderSoundEnabled to the current value does not notify', () async {
      final store = SettingsStore();
      var notified = 0;
      store.addListener(() => notified++);
      await store.setOrderSoundEnabled(true); // already true
      expect(notified, 0);
    });
  });
}
