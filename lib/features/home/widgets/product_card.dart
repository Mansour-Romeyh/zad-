import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_exceptions.dart';
import '../../../core/constants.dart';
import '../../../core/errors/user_error.dart';
import '../../../core/stores/cart_store.dart';
import '../../../core/stores/favourites_store.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/remote_image.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/product.dart';
import '../../auth/login_required_sheet.dart';
import '../../product/weight_selector.dart';
import 'cart_fly.dart';

/// Standard luminance-preserving grayscale matrix, used to visually
/// disable an out-of-stock card.
const _grayscaleMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0, //
];

class ProductCard extends StatelessWidget {
  const ProductCard({required this.product, super.key});

  final Product product;

  /// The favourites/cart key: the backend `item_code`, falling back to
  /// [Product.id] for legacy/mock-style construction.
  String get _itemKey => product.itemCode ?? product.id;

  Future<void> _handleFavouriteTap(BuildContext context) async {
    final ok = await ensureLoggedIn(context);
    if (!ok || !context.mounted) return;
    context.read<FavouritesStore>().toggle(_itemKey);
  }

  void _openDetail(BuildContext context) =>
      Navigator.pushNamed(context, '/product', arguments: _itemKey);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    // `select` (not `watch`) so a card rebuilds only when ITS OWN favourite
    // bit flips — not on every FavouritesStore.notifyListeners() (which fires
    // on every page load's seed(), rebuilding all visible cards otherwise).
    final isFavourite =
        context.select<FavouritesStore, bool>((s) => s.contains(_itemKey));
    final inStock = product.inStock;

    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Detail-opening region: image + name + unit + price ONLY. The control
        // zone below is a sibling, deliberately outside this GestureDetector,
        // so stepper taps can never be stolen by the card-body tap (which would
        // otherwise open the detail page).
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openDetail(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  // Full-bleed product photo filling the rounded card — no grey
                  // ground, no padding. The surface only reappears behind the
                  // placeholder when there's no image to show.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(ZadRadii.tile),
                    child: SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: RemoteImage(
                        url: product.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: const ColoredBox(
                          color: ZadColors.surface,
                          child: Center(
                            child: Icon(
                              Iconsax.gallery,
                              color: ZadColors.muted,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    child: Semantics(
                      button: true,
                      selected: isFavourite,
                      label: l10n.addToFavorites,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: inStock ? () => _handleFavouriteTap(context) : null,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            isFavourite ? Iconsax.heart5 : Iconsax.heart,
                            size: 20,
                            color: isFavourite ? ZadColors.heart : ZadColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!inStock)
                    PositionedDirectional(
                      start: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: ZadColors.ink.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          l10n.outOfStock,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: ZadColors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                product.nameFor(languageCode),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  color: ZadColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                product.unitFor(languageCode),
                style: const TextStyle(fontSize: 11, color: ZadColors.muted),
              ),
              const SizedBox(height: 6),
              // Price only — the (+) moved into the control zone below.
              Row(
                children: [
                  Flexible(
                    child: Text(
                      formatPrice(
                        product.pricePerUom ?? product.price,
                        languageCode,
                      ),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ZadColors.ink,
                      ),
                    ),
                  ),
                  if (product.oldPrice != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      formatPrice(product.oldPrice!, languageCode),
                      style: const TextStyle(
                        fontSize: 12,
                        color: ZadColors.muted,
                        decoration: TextDecoration.lineThrough,
                        decorationColor: ZadColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: kProductCardControlGap),
        _CardCartControl(product: product, enabled: inStock),
      ],
    );

    if (inStock) return card;
    return Opacity(
      opacity: 0.6,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(_grayscaleMatrix),
        child: card,
      ),
    );
  }
}

/// The card's bottom control row (fixed height, always present so grid cells
/// stay uniform). Shows the (+) button when the item is not in the cart, and
/// the `[ − value + ]` stepper — bound to the live cart line — once it is.
class _CardCartControl extends StatelessWidget {
  const _CardCartControl({required this.product, required this.enabled});

  final Product product;
  final bool enabled;

  String get _itemKey => product.itemCode ?? product.id;

  @override
  Widget build(BuildContext context) {
    // Rebuild only when THIS item's line changes (present? qty? +-enabled?).
    final snap = context.select<CartStore, ({double qty, bool canInc})?>((cart) {
      final line = cart.lineFor(_itemKey);
      return line == null
          ? null
          : (qty: line.qty, canInc: cart.canIncrement(line));
    });

    return SizedBox(
      height: kProductCardControlHeight,
      child: snap == null ? _addButton(context) : _stepper(context, snap),
    );
  }

  Widget _addButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: _AddButton(
        enabled: enabled,
        label: l10n.add,
        onTap: (center) => _handleAddTap(context, center),
      ),
    );
  }

  Widget _stepper(BuildContext context, ({double qty, bool canInc}) snap) {
    final l10n = AppLocalizations.of(context);
    // Out-of-stock in-cart items may still be decremented/removed, but never
    // incremented further — the whole card's grayscale overlay doesn't block
    // taps, so this gate is what actually stops adding more of an OOS item.
    final canInc = enabled && snap.canInc;
    final label = product.soldByWeight
        ? formatWeightGrams(
            snap.qty * 1000,
            gramUnit: l10n.unitGram,
            kgUnit: l10n.unitKg,
          )
        : '${snap.qty.toInt()}';
    return Container(
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            key: const Key('cardStepperDecrement'),
            tooltip: l10n.decreaseQuantity,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: () => _handleDecrement(context),
            icon: const Icon(
              Iconsax.minus_cirlce,
              size: 22,
              color: ZadColors.primary,
            ),
          ),
          Flexible(
            child: Text(
              label,
              key: const Key('cardStepperValue'),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: ZadColors.ink,
              ),
            ),
          ),
          IconButton(
            key: const Key('cardStepperIncrement'),
            tooltip: l10n.increaseQuantity,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            onPressed: canInc ? () => _handleIncrement(context) : null,
            icon: Icon(
              Iconsax.add_circle,
              size: 22,
              color: canInc ? ZadColors.primary : ZadColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  void _handleIncrement(BuildContext context) {
    final cart = context.read<CartStore>();
    final line = cart.lineFor(_itemKey);
    if (line != null) cart.increment(line);
  }

  void _handleDecrement(BuildContext context) {
    final cart = context.read<CartStore>();
    final line = cart.lineFor(_itemKey);
    if (line == null) return;
    if (cart.canDecrement(line)) {
      cart.decrement(line);
    } else {
      cart.remove(line.id); // at the minimum → remove & collapse to (+)
    }
  }

  // --- moved verbatim from ProductCard (they only need `product` + context) ---

  /// Adds [product] to the cart. Weight-sold items add their minimum
  /// sellable weight — `weight_step_g` clamped up to `min_g`, the same
  /// value the detail page's [WeightSelector] starts at (PRD E1).
  Future<void> _handleAddTap(BuildContext context, Offset from) async {
    final ok = await ensureLoggedIn(context);
    if (!ok || !context.mounted) return;
    try {
      if (product.soldByWeight) {
        final selector = WeightSelector(
          stepG: product.weightStepG ?? 500,
          minG: product.minG,
          maxG: product.maxG,
        );
        await context.read<CartStore>().add(product, qtyKg: selector.kg);
      } else {
        await context.read<CartStore>().add(product);
      }
    } on ApiException catch (e) {
      if (!context.mounted) return;
      showErrorSnackBar(context, e);
      return;
    }
    if (!context.mounted) return;
    _celebrateAdd(context, from);
  }

  /// Post-add feedback: fly the item photo to the basket on the Home shell
  /// with animations enabled, otherwise a brief "Added" toast.
  void _celebrateAdd(BuildContext context, Offset from) {
    final controller = CartFlyScope.maybeOf(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (controller != null && !reduceMotion) {
      controller.fly(
        from: from,
        image: _flyImage(),
        overlay: Overlay.of(context),
      );
    } else {
      showAddedToBasketSnackBar(context);
    }
  }

  /// Image the flying thumbnail shows; null ⇒ the thumb draws a bag icon.
  ImageProvider? _flyImage() {
    final url = product.imageUrl;
    if (url == null || url.isEmpty) return null;
    return NetworkImage(url);
  }
}

/// The card's (+) button. A `StatefulWidget` so it can report its own global
/// center (via its `RenderBox`) as the fly's start point — no `GlobalKey`
/// churn on the rebuilt `ProductCard`.
class _AddButton extends StatefulWidget {
  const _AddButton({
    required this.enabled,
    required this.label,
    required this.onTap,
  });

  final bool enabled;
  final String label;
  final void Function(Offset center) onTap;

  @override
  State<_AddButton> createState() => _AddButtonState();
}

class _AddButtonState extends State<_AddButton> {
  void _handleTap() {
    final box = context.findRenderObject() as RenderBox?;
    final center = (box != null && box.hasSize)
        ? box.localToGlobal(box.size.center(Offset.zero))
        : Offset.zero;
    widget.onTap(center);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _handleTap : null,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: widget.enabled ? ZadColors.primary : ZadColors.muted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.add, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}
