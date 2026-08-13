import '../core/json_utils.dart';

/// App-wide config (PRD F2 `content.get_app_config`):
/// `{splash_image, splash_bg_color, splash_duration_sec, app_min_version,
/// maintenance_mode, support_phone}`.
class AppConfig {
  const AppConfig({
    this.splashImage,
    this.splashBgColor,
    this.splashDurationSec,
    this.appMinVersion,
    this.maintenanceMode = false,
    this.supportPhone,
    this.termsUrl,
    this.privacyUrl,
    this.storeOpenTime,
    this.storeCloseTime,
    this.deliveryFee,
    this.freeDeliveryOver,
  });

  final String? splashImage;
  final String? splashBgColor;
  final int? splashDurationSec;
  final String? appMinVersion;
  final bool maintenanceMode;
  final String? supportPhone;
  final String? termsUrl;
  final String? privacyUrl;

  /// Daily working-hours window as the backend's `"HH:MM:SS"` strings
  /// (`content.get_app_config`); null = not configured = always open.
  final String? storeOpenTime;
  final String? storeCloseTime;

  /// Flat delivery fee (IQD) from App Settings; null/0 = no fee configured.
  final double? deliveryFee;

  /// Item-subtotal at/above which delivery is free (IQD); null/0 = never.
  final double? freeDeliveryOver;

  factory AppConfig.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveImageUrl,
  }) {
    final resolver = resolveImageUrl ?? (String? p) => p;
    return AppConfig(
      splashImage: resolver(json['splash_image'] as String?),
      splashBgColor: json['splash_bg_color'] as String?,
      splashDurationSec: toInt(json['splash_duration_sec']),
      appMinVersion: json['app_min_version'] as String?,
      maintenanceMode: toBool(json['maintenance_mode']),
      supportPhone: json['support_phone'] as String?,
      termsUrl: json['terms_url'] as String?,
      privacyUrl: json['privacy_url'] as String?,
      storeOpenTime: json['store_open_time'] as String?,
      storeCloseTime: json['store_close_time'] as String?,
      deliveryFee: toDouble(json['delivery_fee']),
      freeDeliveryOver: toDouble(json['free_delivery_over']),
    );
  }

  /// Round-trips through [AppConfig.fromJson] (with the default identity
  /// resolver — [splashImage] is already an absolute URL by the time a
  /// config is cached), so `AppConfigStore` can persist the last-good
  /// fetched config in `shared_preferences`.
  Map<String, dynamic> toJson() => {
        'splash_image': splashImage,
        'splash_bg_color': splashBgColor,
        'splash_duration_sec': splashDurationSec,
        'app_min_version': appMinVersion,
        'maintenance_mode': maintenanceMode,
        'support_phone': supportPhone,
        'terms_url': termsUrl,
        'privacy_url': privacyUrl,
        'store_open_time': storeOpenTime,
        'store_close_time': storeCloseTime,
        'delivery_fee': deliveryFee,
        'free_delivery_over': freeDeliveryOver,
      };

  /// Whether the store is open at [now] — same window semantics as the
  /// backend's `store_hours()`: unset/half-set/equal → always open;
  /// `open < close` → open when `open <= now < close`; `open > close` →
  /// overnight window (open when `now >= open` OR `now < close`). The
  /// caller supplies [now] (device clock in the app, fixed instants in
  /// tests); the server clock stays authoritative at `place_order`.
  bool isStoreOpenAt(DateTime now) {
    final open = _secondsOfDay(storeOpenTime);
    final close = _secondsOfDay(storeCloseTime);
    if (open == null || close == null || open == close) return true;
    final t = now.hour * 3600 + now.minute * 60 + now.second;
    if (open < close) return open <= t && t < close;
    return t >= open || t < close;
  }

  /// Whether a positive delivery fee is configured. Drives whether checkout
  /// shows a Delivery line at all — an unset/0 fee behaves exactly as before
  /// (no line, Total == Subtotal).
  bool get hasDeliveryFee => (deliveryFee ?? 0) > 0;

  /// The delivery fee applied to a basket whose item subtotal is [netTotal]
  /// — the app's advisory copy of the backend rule (`delivery_fee_for`); the
  /// server recomputes authoritatively at `place_order`. 0 when no fee is
  /// configured or the subtotal reaches the free-delivery threshold.
  double deliveryFeeFor(double netTotal) {
    final fee = deliveryFee ?? 0;
    final threshold = freeDeliveryOver ?? 0;
    if (fee <= 0) return 0;
    if (threshold > 0 && netTotal >= threshold) return 0;
    return fee;
  }

  /// `"HH:MM[:SS]"` → seconds since midnight, or null when absent or
  /// malformed (malformed reads as "not configured", never as closed).
  static int? _secondsOfDay(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = parts.length > 2 ? (int.tryParse(parts[2]) ?? 0) : 0;
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return h * 3600 + m * 60 + s;
  }
}
