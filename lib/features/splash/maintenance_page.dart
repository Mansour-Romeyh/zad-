import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/stores/app_config_store.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/zad_primary_button.dart';

/// Blocking maintenance gate (PRD D1.1 `maintenance_mode`): shown by the
/// splash boot when the (fresh or cached) config says the backend is down
/// for maintenance. Retry re-fetches the config — only a successful fresh
/// fetch with the flag cleared lets the app proceed (back through `/`, so
/// the normal boot chain re-runs); a network failure keeps the gate up.
class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key});

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    final store = context.read<AppConfigStore>();
    final fetched = await store.refresh();
    if (!mounted) return;
    if (fetched && !store.maintenanceMode) {
      Navigator.pushReplacementNamed(context, '/');
      return;
    }
    setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Iconsax.setting_2, size: 56, color: ZadColors.muted),
                const SizedBox(height: 20),
                Text(
                  l10n.maintenanceTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ZadColors.ink,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.maintenanceBody,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: ZadColors.muted,
                  ),
                ),
                const SizedBox(height: 28),
                ZadPrimaryButton(
                  label: l10n.retry,
                  onPressed: _retry,
                  loading: _retrying,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
