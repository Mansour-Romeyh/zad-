import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/stores/cart_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/remote_image.dart';
import '../../core/widgets/zad_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../auth/login_required_sheet.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../product/weight_selector.dart';

/// Bottom-nav Basket tab (PRD F5 cart, hosted inside the `HomePage`
/// IndexedStack shell): line items with a qty stepper honoring weight
/// steps, swipe/trash removal, clear-all, a totals footer and the
/// "إتمام الطلب" checkout CTA — login-gated for guests (PRD J2 "any action
/// requires login" at checkout).
///
/// Soft stock warnings are NOT handled here — `CartWarningsListener` (the
/// single app-level subscription) turns them into SnackBars.
class BasketPage extends StatefulWidget {
  const BasketPage({required this.onShopNow, super.key});

  /// Invoked by the empty-state CTA — the host (`HomePage`) switches the
  /// bottom nav back to the Home tab.
  final VoidCallback onShopNow;

  @override
  State<BasketPage> createState() => _BasketPageState();
}

class _BasketPageState extends State<BasketPage> {
  /// Runs a cart mutation, turning any [ApiException] (including network
  /// failures) into an error SnackBar instead of an unhandled async error.
  /// Returns whether the mutation succeeded — the swipe-to-remove
  /// `confirmDismiss` uses that to animate the row back on failure.
  Future<bool> _guard(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
      return false;
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showZadConfirm(
      context,
      title: l10n.basketClearTitle,
      message: l10n.basketClearMessage,
      confirmLabel: l10n.basketClearAll,
      cancelLabel: l10n.cancel,
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (confirmed && context.mounted) {
      final cart = context.read<CartStore>();
      await _guard(cart.clear);
    }
  }

  Future<void> _handleCheckout(BuildContext context) async {
    final ok = await ensureLoggedIn(context);
    if (!ok || !context.mounted) return;
    Navigator.pushNamed(context, '/checkout');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cart = context.watch<CartStore>();
    final items = cart.items;

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZadSpacing.screenPadding,
              12,
              ZadSpacing.screenPadding,
              0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.basketTitle,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: ZadColors.ink,
                  ),
                ),
                if (items.isNotEmpty)
                  TextButton(
                    key: const Key('basketClearAllButton'),
                    onPressed: () => _confirmClear(context),
                    child: Text(l10n.basketClearAll),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? _EmptyBasket(l10n: l10n, onShopNow: widget.onShopNow)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      ZadSpacing.screenPadding,
                      12,
                      ZadSpacing.screenPadding,
                      12,
                    ),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) =>
                        _BasketLineTile(line: items[i], guard: _guard),
                  ),
          ),
          if (items.isNotEmpty)
            _TotalsFooter(cart: cart, onCheckout: () => _handleCheckout(context)),
        ],
      ),
    );
  }
}

class _EmptyBasket extends StatelessWidget {
  const _EmptyBasket({required this.l10n, required this.onShopNow});

  final AppLocalizations l10n;
  final VoidCallback onShopNow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.bag_2, size: 48, color: ZadColors.muted),
            const SizedBox(height: 16),
            Text(
              l10n.basketEmptyTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ZadColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            ZadPrimaryButton(label: l10n.shopNow, onPressed: onShopNow),
          ],
        ),
      ),
    );
  }
}

class _BasketLineTile extends StatelessWidget {
  const _BasketLineTile({required this.line, required this.guard});

  final CartLineView line;

  /// The page's error guard — wraps every mutation so a server/network
  /// failure becomes a SnackBar and reports success back (the swipe
  /// gesture animates the row back into place when it returns false).
  final Future<bool> Function(Future<void> Function() action) guard;

  String _qtyLabel(AppLocalizations l10n) {
    if (line.soldByWeight) {
      return formatWeightGrams(line.qty * 1000, gramUnit: l10n.unitGram, kgUnit: l10n.unitKg);
    }
    return line.qty.round().toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final cart = context.read<CartStore>();

    return Dismissible(
      key: ValueKey('basketLine-${line.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(ZadRadii.tile),
        ),
        child: const Icon(Iconsax.trash, color: Colors.white),
      ),
      // The remove happens inside confirmDismiss (not onDismissed) so a
      // failed server call returns false and the row animates back into
      // place — with onDismissed a failed remove would leave a dismissed
      // Dismissible for a line still present in the store (an assertion
      // error on the next rebuild).
      confirmDismiss: (_) => guard(() => cart.remove(line.id)),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ZadColors.surface,
          borderRadius: BorderRadius.circular(ZadRadii.tile),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 64,
                height: 64,
                child: RemoteImage(
                  url: line.imageUrl,
                  placeholder: const Icon(Iconsax.gallery, color: ZadColors.muted),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.nameFor(languageCode),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ZadColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(line.unit, style: const TextStyle(fontSize: 12, color: ZadColors.muted)),
                  const SizedBox(height: 6),
                  Text(
                    formatPrice(line.lineTotal, languageCode),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ZadColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Semantics(
                  button: true,
                  label: l10n.basketRemoveItem,
                  child: IconButton(
                    key: Key('removeLine-${line.id}'),
                    onPressed: () => guard(() => cart.remove(line.id)),
                    icon: const Icon(Iconsax.trash, size: 20, color: ZadColors.muted),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('decrementLine-${line.id}'),
                      onPressed: cart.canDecrement(line)
                          ? () => guard(() => cart.decrement(line))
                          : null,
                      icon: const Icon(Iconsax.minus_cirlce),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        _qtyLabel(l10n),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      key: Key('incrementLine-${line.id}'),
                      onPressed: cart.canIncrement(line)
                          ? () => guard(() => cart.increment(line))
                          : null,
                      icon: const Icon(Iconsax.add_circle),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsFooter extends StatelessWidget {
  const _TotalsFooter({required this.cart, required this.onCheckout});

  final CartStore cart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final totals = cart.totals;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        ZadSpacing.screenPadding,
        16,
        ZadSpacing.screenPadding,
        16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: ZadColors.ink.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(l10n.basketSubtotal, style: const TextStyle(fontSize: 13, color: ZadColors.muted)),
              Text(
                formatPrice(totals.netTotal, languageCode),
                style: const TextStyle(fontSize: 13, color: ZadColors.ink),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.basketTotal,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ZadColors.ink),
              ),
              Text(
                formatPrice(totals.grandTotal, languageCode),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ZadColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ZadPrimaryButton(
            key: const Key('checkoutButton'),
            label: l10n.basketCheckout,
            onPressed: onCheckout,
          ),
        ],
      ),
    );
  }
}
