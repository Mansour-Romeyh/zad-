import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

abstract final class ZadSpacing {
  static const double screenPadding = 20;
  static const double sectionGap = 24;
}

abstract final class ZadRadii {
  static const double tile = 14;
  static const double banner = 16;
  static const double sheet = 30;
  static const double button = 12;
  static const double dialog = 28;
}

/// Number of digits in a WhatsApp OTP — drives both the segmented input's box
/// count and its "complete" validation. Must match the backend
/// `WASender Settings.otp_length`.
const int kOtpLength = 4;

/// Minimum length of a signup password — mirrors the backend
/// `auth.MIN_PASSWORD_LENGTH` so the register form rejects short passwords
/// inline, before an OTP is ever requested.
const int kMinPasswordLength = 8;

/// Shadow blur radii for popups (not Material elevation).
abstract final class ZadElevation {
  static const double dialog = 24;
  static const double sheet = 16;
  static const double snack = 6;
}

abstract final class ZadDurations {
  static const popupIn = Duration(milliseconds: 220);
  static const snack = Duration(seconds: 3);
}

abstract final class ZadCurves {
  static const popupIn = Curves.easeOutCubic;
}

const kSplashDuration = Duration(milliseconds: 2500);
const kOnboardingDoneKey = 'onboarding_done';

/// Grace period after the user taps "Place Order" during which the order is
/// held client-side (not yet sent) so they can cancel & edit or send it early
/// (checkout's confirm countdown). Nothing reaches the server until it elapses.
const kOrderCancelWindow = Duration(seconds: 30);

/// shared_preferences key the guest local cart is persisted under
/// (`CartStore`, PRD J2). Cleared once its lines are merged into the
/// server cart on login.
const kGuestCartKey = 'guest_cart_v1';

/// shared_preferences key the last successfully fetched app config is
/// cached under (`AppConfigStore`, PRD F2/D1.1) — the offline-boot
/// fallback between "fresh fetch" and "bundled defaults".
const kAppConfigCacheKey = 'app_config_v1';

/// Height reserved on every [ProductCard] for its add/stepper control row, so
/// fixed-height grid cells stay uniform whether the card shows a `+` or the
/// `[ − value + ]` stepper.
const double kProductCardControlHeight = 44;

/// Vertical gap between the price and the control row on a [ProductCard].
const double kProductCardControlGap = 8;

/// Formats [price] as Iraqi Dinar (PRD currency: IQD), locale-aware, with
/// no decimal places: `IQD 1,500` in English, `1,500 د.ع` in Arabic.
/// Digit grouping always uses Western numerals/comma separators (Iraqi
/// apps conventionally keep prices in Western digits even in Arabic UI) —
/// only the currency symbol's text and position change with [languageCode].
String formatPrice(num price, [String languageCode = 'en']) {
  final amount = NumberFormat('#,##0', 'en').format(price);
  return languageCode == 'ar' ? '$amount د.ع' : 'IQD $amount';
}

/// Formats a backend date string (`YYYY-MM-DD`, or any ISO-8601 form) for
/// display in [locale] — e.g. `Jul 13, 2026` in English, `١٣ يوليو ٢٠٢٦` in
/// Arabic — matching the style the notifications feed already uses.
/// Unparseable input falls through verbatim (render beats crash).
String formatDisplayDate(String raw, String locale) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return raw;
  return DateFormat.yMMMd(locale).format(parsed);
}
