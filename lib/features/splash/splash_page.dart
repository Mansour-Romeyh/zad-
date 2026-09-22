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
    if (!mounted) return;
    // Resolve any saved session before routing, so the first screen the user
    // lands on already knows whether they're a guest or authed.
    await context.read<SessionStore>().restore();
    if (!mounted) return;
    // The remaining hydrations depend on the resolved session but not on each
    // other, so run them concurrently — boot then waits on the slowest call,
    // not the sum of four round-trips. All four are documented "never throws",
    // so Future.wait won't reject:
    //  - CartStore: guest local cart or the authed server cart.
    //  - FavouritesStore: wishlist for an authed session (no-op for guests).
    //  - AddressStore: address book, so the home header + no-address nudge
    //    (PRD A3) are correct on first paint.
    //  - NotificationsStore: unread badge for the home bell.
    await Future.wait([
      context.read<CartStore>().restore(),
      context.read<FavouritesStore>().restore(),
      context.read<AddressStore>().restore(),
      context.read<NotificationsStore>().restore(),
    ]);
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

  /// Brand wordmark — the placeholder/fallback for a config-driven remote
  /// splash image. Intentionally not localized.
  static const Widget _wordmark = Text(
    'Zad',
    style: TextStyle(
      fontFamily: 'Poppins',
      fontSize: 56,
      fontWeight: FontWeight.w700,
      color: ZadColors.primary,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final config = context.watch<AppConfigStore>().config;
    final remote = config.splashImage;

    // Backend takeover (PRD D1.1): a config-supplied splash image still wins —
    // shown centered on the config background with the wordmark as its
    // placeholder/fallback while (or in case) the remote image can't load.
    if (remote != null && remote.isNotEmpty) {
      return Scaffold(
        backgroundColor: _splashBackground(config.splashBgColor),
        body: Center(
          child: SizedBox(
            width: 220,
            height: 220,
            child: RemoteImage(
              url: remote,
              placeholder: const Center(child: _wordmark),
            ),
          ),
        ),
      );
    }

    // Bundled default: the full-screen brand artwork. Its 738×1600 (~19.5:9)
    // source matches most modern phones edge-to-edge; on other aspect ratios
    // `BoxFit.contain` letterboxes rather than crop, so the feature badges are
    // never cut off. The white→cream gradient is sampled from the art's own
    // top/bottom edges, so the bars blend into the image. `splash_bg_color`
    // stays honored as the scaffold base for the config contract.
    return Scaffold(
      backgroundColor: _splashBackground(config.splashBgColor),
      body: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFEFEFE), Color(0xFFEAF2DB)],
          ),
        ),
        child: SizedBox.expand(
          child: Image(
            image: AssetImage('assets/images/splash.jpg'),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
