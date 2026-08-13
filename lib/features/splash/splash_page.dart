import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/session/session_store.dart';
import '../../core/stores/app_config_store.dart';
import '../../core/stores/address_store.dart';
import '../../core/stores/cart_store.dart';
import '../../core/stores/favourites_store.dart';
import '../../core/stores/notifications_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/remote_image.dart';

/// Config-driven boot (PRD F2/D1.1): fetches `get_app_config` (bounded by
/// `AppConfigStore.fetchTimeout`, falling back to the cached last-good
/// config, then bundled constants), applies the config's splash colors /
/// image / duration when present, gates on `maintenance_mode`, and only
/// then runs the session/cart/favourites/addresses/notifications restore
/// chain before routing to onboarding or home.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final configStore = context.read<AppConfigStore>();
    final stopwatch = Stopwatch()..start();
    // Never throws; internally network → cache → bundled defaults.
    await configStore.load();
    if (!mounted) return;

    // Config-driven splash duration (D1.1 splash_duration_sec), bundled
    // constant when absent. The config fetch time counts toward it.
    final durationSec = configStore.config.splashDurationSec;
    final total = durationSec != null && durationSec > 0
        ? Duration(seconds: durationSec)
        : kSplashDuration;
    final remaining = total - stopwatch.elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
    if (!mounted) return;

    if (configStore.maintenanceMode) {
      Navigator.pushReplacementNamed(context, '/maintenance');
      return;
    }
    await _navigateNext();
  }

  Future<void> _navigateNext() async {
    var done = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      done = prefs.getBool(kOnboardingDoneKey) ?? false;
    } catch (_) {
      // Storage unavailable: showing onboarding again is benign.
    }
    if (mounted) {
      // Resolve any saved session before routing, so the first screen the
      // user lands on already knows whether they're a guest or authed.
      await context.read<SessionStore>().restore();
    }
    if (mounted) {
      // Loads the guest local cart (or the server cart if already authed)
      // now that the session status is known — CartStore's own
      // login/logout listener handles later transitions.
      await context.read<CartStore>().restore();
    }
    if (mounted) {
      // Hydrates the wishlist for an already-authed session (no-op for
      // guests) — FavouritesStore's own login/logout listener handles
      // later transitions. Never throws; an offline boot retries on the
      // next favourites-tab activation.
      await context.read<FavouritesStore>().restore();
    }
    if (mounted) {
      // Hydrates the address book for an already-authed session (no-op
      // for guests) so the home header shows the default address on first
      // paint and the no-address nudge (PRD A3) can fire. Never throws.
      await context.read<AddressStore>().restore();
    }
    if (mounted) {
      // Hydrates the unread badge for an already-authed session (no-op
      // for guests) so the home bell is correct on first paint. Never
      // throws.
      await context.read<NotificationsStore>().restore();
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, done ? '/home' : '/onboarding');
  }

  /// Parses a `#RRGGBB` / `RRGGBB` / `#AARRGGBB` config color defensively —
  /// anything unparsable falls back to the bundled white.
  static Color _splashBackground(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.white;
    var value = hex.replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    if (value.length != 8) return Colors.white;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? Colors.white : Color(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfigStore>().config;
    const wordmark = Text(
      'Zad', // brand wordmark — intentionally not localized
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 56,
        fontWeight: FontWeight.w700,
        color: ZadColors.primary,
      ),
    );
    return Scaffold(
      backgroundColor: _splashBackground(config.splashBgColor),
      body: Stack(
        children: [
          Center(
            // Config splash image when the backend provides one; the
            // bundled wordmark is both the fallback and the placeholder
            // while (or in case) the remote image can't load.
            child: config.splashImage == null || config.splashImage!.isEmpty
                ? wordmark
                : SizedBox(
                    width: 220,
                    height: 220,
                    child: RemoteImage(
                      url: config.splashImage,
                      placeholder: Center(child: wordmark),
                    ),
                  ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Image.asset(
              'assets/images/produce_spread.png',
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
          ),
        ],
      ),
    );
  }
}
