import 'package:flutter_test/flutter_test.dart';
import 'package:zad/models/app_config.dart';

void main() {
  test('fromJson parses a full payload', () {
    final config = AppConfig.fromJson(
      {
        'splash_image': '/files/splash.png',
        'splash_bg_color': '#5AC268',
        'splash_duration_sec': 3,
        'app_min_version': '1.0.0',
        'maintenance_mode': false,
        'support_phone': '+9647700000000',
        'store_open_time': '09:00:00',
        'store_close_time': '23:00:00',
      },
      resolveImageUrl: (p) => p == null ? null : 'http://test.local$p',
    );

    expect(config.splashImage, 'http://test.local/files/splash.png');
    expect(config.splashBgColor, '#5AC268');
    expect(config.splashDurationSec, 3);
    expect(config.appMinVersion, '1.0.0');
    expect(config.maintenanceMode, isFalse);
    expect(config.supportPhone, '+9647700000000');
    expect(config.storeOpenTime, '09:00:00');
    expect(config.storeCloseTime, '23:00:00');
  });

  test('toJson round-trips through fromJson (cache persistence)', () {
    const original = AppConfig(
      splashImage: 'http://test.local/files/splash.png',
      splashBgColor: '#5AC268',
      splashDurationSec: 3,
      appMinVersion: '1.0.0',
      maintenanceMode: true,
      supportPhone: '+9647700000000',
      storeOpenTime: '09:00:00',
      storeCloseTime: '23:00:00',
    );

    final restored = AppConfig.fromJson(original.toJson());

    expect(restored.splashImage, original.splashImage);
    expect(restored.splashBgColor, original.splashBgColor);
    expect(restored.splashDurationSec, original.splashDurationSec);
    expect(restored.appMinVersion, original.appMinVersion);
    expect(restored.maintenanceMode, original.maintenanceMode);
    expect(restored.supportPhone, original.supportPhone);
    expect(restored.storeOpenTime, original.storeOpenTime);
    expect(restored.storeCloseTime, original.storeCloseTime);
  });

  test('fromJson tolerates a minimal payload and defaults maintenanceMode false', () {
    final config = AppConfig.fromJson({});

    expect(config.splashImage, isNull);
    expect(config.splashBgColor, isNull);
    expect(config.splashDurationSec, isNull);
    expect(config.appMinVersion, isNull);
    expect(config.maintenanceMode, isFalse);
  });

  test('maintenance_mode as numeric 1 is treated as true', () {
    final config = AppConfig.fromJson({'maintenance_mode': 1});
    expect(config.maintenanceMode, isTrue);
  });

  group('isStoreOpenAt', () {
    final noon = DateTime(2026, 7, 17, 12);
    final lateNight = DateTime(2026, 7, 17, 23, 30);
    final earlyMorning = DateTime(2026, 7, 17, 1);

    test('unconfigured or half-configured is always open', () {
      expect(const AppConfig().isStoreOpenAt(noon), isTrue);
      expect(
        const AppConfig(storeOpenTime: '09:00:00').isStoreOpenAt(lateNight),
        isTrue,
      );
      expect(
        const AppConfig(storeCloseTime: '23:00:00').isStoreOpenAt(lateNight),
        isTrue,
      );
    });

    test('equal open and close is always open', () {
      const config = AppConfig(storeOpenTime: '09:00:00', storeCloseTime: '09:00:00');
      expect(config.isStoreOpenAt(earlyMorning), isTrue);
    });

    test('same-day window: open inside, closed outside', () {
      const config = AppConfig(storeOpenTime: '09:00:00', storeCloseTime: '23:00:00');
      expect(config.isStoreOpenAt(noon), isTrue);
      expect(config.isStoreOpenAt(lateNight), isFalse);
      expect(config.isStoreOpenAt(earlyMorning), isFalse);
      // Boundaries: inclusive open, exclusive close.
      expect(config.isStoreOpenAt(DateTime(2026, 7, 17, 9)), isTrue);
      expect(config.isStoreOpenAt(DateTime(2026, 7, 17, 23)), isFalse);
    });

    test('overnight window spans midnight', () {
      const config = AppConfig(storeOpenTime: '18:00:00', storeCloseTime: '02:00:00');
      expect(config.isStoreOpenAt(lateNight), isTrue);
      expect(config.isStoreOpenAt(earlyMorning), isTrue);
      expect(config.isStoreOpenAt(noon), isFalse);
    });

    test('malformed time strings read as always open', () {
      const config = AppConfig(storeOpenTime: 'bogus', storeCloseTime: '23:00:00');
      expect(config.isStoreOpenAt(noon), isTrue);
    });
  });

  test('parses and round-trips terms/privacy URLs', () {
    final config = AppConfig.fromJson(const {
      'terms_url': 'https://zad.micronext.net/terms',
      'privacy_url': 'https://zad.micronext.net/privacy-policy',
    });
    expect(config.termsUrl, 'https://zad.micronext.net/terms');
    expect(config.privacyUrl, 'https://zad.micronext.net/privacy-policy');

    final round = AppConfig.fromJson(config.toJson());
    expect(round.termsUrl, 'https://zad.micronext.net/terms');
    expect(round.privacyUrl, 'https://zad.micronext.net/privacy-policy');
  });

  test('missing URLs are null', () {
    final config = AppConfig.fromJson(const {});
    expect(config.termsUrl, isNull);
    expect(config.privacyUrl, isNull);
  });

  test('parses delivery fee fields and round-trips them', () {
    final config = AppConfig.fromJson({
      'delivery_fee': 2000,
      'free_delivery_over': 25000,
    });
    expect(config.deliveryFee, 2000);
    expect(config.freeDeliveryOver, 25000);

    final round = AppConfig.fromJson(config.toJson());
    expect(round.deliveryFee, 2000);
    expect(round.freeDeliveryOver, 25000);
  });

  test('deliveryFeeFor applies the fee below the threshold', () {
    const config = AppConfig(deliveryFee: 2000, freeDeliveryOver: 25000);
    expect(config.hasDeliveryFee, isTrue);
    expect(config.deliveryFeeFor(18000), 2000);
  });

  test('deliveryFeeFor waives the fee at or above the threshold', () {
    const config = AppConfig(deliveryFee: 2000, freeDeliveryOver: 25000);
    expect(config.deliveryFeeFor(25000), 0);
    expect(config.deliveryFeeFor(30000), 0);
  });

  test('deliveryFeeFor always charges when the threshold is 0/unset', () {
    const config = AppConfig(deliveryFee: 2000);
    expect(config.deliveryFeeFor(9999999), 2000);
  });

  test('deliveryFeeFor is free and hasDeliveryFee false when fee is unset', () {
    const config = AppConfig();
    expect(config.hasDeliveryFee, isFalse);
    expect(config.deliveryFeeFor(1000), 0);
  });
}
