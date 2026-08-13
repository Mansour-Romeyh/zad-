import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/stores/cart_store.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';

/// Bottom space a scrollable reserves so its last content clears a visible
/// [CartFab] (the button's height plus its floating margins).
const double kCartFabClearance = 84;

/// The bottom inset to add to a scrollable so its final row/button isn't hidden
/// behind the [CartFab]: [kCartFabClearance] while the cart has items (the FAB
/// is showing), else 0. Call from a `build` — it depends on [CartStore], so the
/// scrollable re-pads the moment the cart becomes (non-)empty.
double cartFabClearanceOf(BuildContext context) =>
    context.watch<CartStore>().count > 0 ? kCartFabClearance : 0;

/// Floating "go to basket" button for browsing routes that live *outside* the
/// Home shell (the category browser, search, best-deals). Those are pushed
/// routes with no bottom-nav basket icon, so after the shopper taps add on a
/// product they'd otherwise have no way back to the basket. This appears —
/// bottom-centre — the moment the cart is non-empty, shows a live line count,
/// and opens `/basket` on tap. It renders nothing while the cart is empty.
class CartFab extends StatelessWidget {
  const CartFab({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch only the line count so the button appears/updates without
    // rebuilding the whole page.
    final count = context.watch<CartStore>().count;
    if (count == 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return FloatingActionButton.extended(
      key: const Key('cartFab'),
      onPressed: () => Navigator.pushNamed(context, '/basket'),
      backgroundColor: ZadColors.primary,
      foregroundColor: ZadColors.white,
      icon: const Icon(Iconsax.bag_2),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l10n.basketTitle,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          _CountPill(count: count),
        ],
      ),
    );
  }
}

/// Count chip on the button — a white pill (reads on the primary fill),
/// capped at "9+" so it never widens the button.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 9 ? '9+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: ZadColors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: ZadColors.primary,
          height: 1.3,
        ),
      ),
    );
  }
}
