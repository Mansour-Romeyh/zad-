import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../stores/cart_store.dart';
import 'zad_snack.dart';

/// The app's single subscription to [CartStore.warnings] (soft stock-check
/// notices, sync-failure warnings). Mounted once via `MaterialApp.builder`
/// — below the root [ScaffoldMessenger] and `Localizations`, above the
/// [Navigator] — so every warning surfaces as exactly ONE SnackBar on
/// whichever screen is current, no matter how deep the navigation stack
/// is. Individual pages must NOT also subscribe, or warnings would show
/// once per open subscriber.
///
/// The locale-less store emits typed sentinels for its own warnings
/// ([kCartSyncFailedWarning]); this listener maps them to localized text.
/// Raw server warning strings pass through unchanged.
class CartWarningsListener extends StatefulWidget {
  const CartWarningsListener({required this.child, super.key});

  final Widget child;

  @override
  State<CartWarningsListener> createState() => _CartWarningsListenerState();
}

class _CartWarningsListenerState extends State<CartWarningsListener> {
  StreamSubscription<List<String>>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = context.read<CartStore>().warnings.listen(_show);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String _resolve(String warning) {
    if (warning == kCartSyncFailedWarning) {
      return AppLocalizations.of(context).cartSyncFailed;
    }
    return warning;
  }

  void _show(List<String> warnings) {
    if (!mounted) return;
    if (ScaffoldMessenger.maybeOf(context) == null) return;
    if (warnings.isEmpty) return;
    final message = warnings.map(_resolve).join('\n');
    showZadSnack(context, message, variant: ZadSnackVariant.warning);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
