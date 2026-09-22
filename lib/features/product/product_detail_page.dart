import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/stores/cart_store.dart';
import '../../core/stores/favourites_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/remote_image.dart';
import '../../core/widgets/zad_snack.dart';
import '../../data/catalog_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/product.dart';
import '../auth/login_required_sheet.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../basket/widgets/cart_fab.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/section_state.dart';
import 'weight_selector.dart';

/// `/product` — full detail screen (PRD F3 `catalog.get_item`, E1 weight
/// selector, J4 acceptance): hero image, name, price per uom, short
/// description, availability badge, a weight-step selector (sold-by-weight
/// items) or an integer qty stepper (unit items) with a live total price,
/// a login-gated Add-to-basket CTA, and a login-gated favourite heart.
///
/// Only takes a `String itemCode` as its route argument — the page always
/// refetches the full detail via [CatalogRepository.getItem] rather than
/// accepting a [Product] built for a list card.
class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({super.key});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  bool _initialized = false;
  String _itemCode = '';

  SectionState<Product> _state = const SectionState.loading();

  /// Weight-step state for sold-by-weight items (PRD E1); `null` for unit
  /// items. Lives here, not in [CartStore] — only the final Kg value is
  /// handed to the store on Add.
  WeightSelector? _weight;

  /// Integer qty for unit items (starts at 1, steps by 1).
  int _qty = 1;

  String get _itemKey => _state.data?.itemCode ?? _itemCode;

  // Soft stock warnings from CartStore are NOT subscribed to here —
  // `CartWarningsListener` (the single app-level subscription in app.dart)
  // shows them, so an add from this page never produces duplicates.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    _itemCode = args is String ? args : '';
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const SectionState.loading());
    try {
      final repo = context.read<CatalogRepository>();
      final product = await repo.getItem(_itemCode);
      if (!mounted) return;
      // The detail payload is ItemCard-shaped too (PRD F3) — seed the
      // heart from its `is_favourite` (seed-only, never un-favourites).
      context.read<FavouritesStore>().seed([product]);
      setState(() {
        _state = SectionState.data(product);
        _qty = 1;
        _weight = product.soldByWeight
            ? WeightSelector(
                stepG: product.weightStepG ?? 500,
                minG: product.minG,
                maxG: product.maxG,
              )
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = SectionState.error(e));
    }
  }

  void _incrementWeight() => setState(() => _weight?.increment());

  void _decrementWeight() => setState(() => _weight?.decrement());

  void _incrementQty() => setState(() => _qty++);

  void _decrementQty() => setState(() => _qty = _qty > 1 ? _qty - 1 : 1);

  Future<void> _handleFavouriteTap() async {
    final ok = await ensureLoggedIn(context);
    if (!ok || !mounted) return;
    context.read<FavouritesStore>().toggle(_itemKey);
  }

  Future<void> _handleAdd(Product product) async {
    final ok = await ensureLoggedIn(context);
    if (!ok || !mounted) return;
    final cart = context.read<CartStore>();
    try {
      if (product.soldByWeight && _weight != null) {
        await cart.add(product, qtyKg: _weight!.kg);
      } else {
        await cart.add(product, qty: _qty);
      }
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      showZadSnack(context, l10n.addedToCart, variant: ZadSnackVariant.success);
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        actions: [
          if (_state.status == SectionStatus.data)
            IconButton(
              key: const Key('favouriteButton'),
              tooltip: l10n.addToFavorites,
              onPressed: _handleFavouriteTap,
              icon: Builder(
                builder: (context) {
                  final isFavourite = context.watch<FavouritesStore>().contains(
                    _itemKey,
                  );
                  return Icon(
                    isFavourite ? Iconsax.heart5 : Iconsax.heart,
                    color: isFavourite ? Colors.redAccent : ZadColors.ink,
                  );
                },
              ),
            ),
        ],
      ),
      // Basket button also reachable from the detail screen once the cart has
      // items; the scroll view reserves room for it (see _buildDetail).
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: AsyncSection<Product>(
          state: _state,
          skeleton: const Center(child: CircularProgressIndicator()),
          onRetry: _load,
          builder: (context, product) => _buildDetail(context, l10n, product),
        ),
      ),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    AppLocalizations l10n,
    Product product,
  ) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final inStock = product.inStock;
    final pricePerUom = product.pricePerUom ?? product.price;
    final uom = product.uom ?? product.unitFor(languageCode);
    final description = product.description;

    return SingleChildScrollView(
      // Extra bottom room so the Add-to-Basket button clears the floating
      // basket button when the cart is non-empty.
      padding: EdgeInsets.fromLTRB(
        ZadSpacing.screenPadding,
        ZadSpacing.screenPadding,
        ZadSpacing.screenPadding,
        ZadSpacing.screenPadding + cartFabClearanceOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(ZadRadii.tile),
              child: RemoteImage(
                url: product.imageUrl,
                fit: BoxFit.cover,
                placeholder: const ColoredBox(
                  color: ZadColors.surface,
                  child: Center(
                    child: Icon(
                      Iconsax.gallery,
                      color: ZadColors.muted,
                      size: 56,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            product.nameFor(languageCode),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: ZadColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                formatPrice(pricePerUom, languageCode),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ZadColors.primary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '/ $uom',
                style: const TextStyle(fontSize: 14, color: ZadColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AvailabilityBadge(inStock: inStock, l10n: l10n),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              description,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: ZadColors.muted,
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (product.soldByWeight && _weight != null)
            _weightSelectorSection(l10n, pricePerUom, languageCode)
          else
            _qtyStepperSection(l10n, pricePerUom, languageCode),
          const SizedBox(height: 28),
          ZadPrimaryButton(
            key: const Key('addToBasketButton'),
            label: l10n.addToBasket,
            onPressed: inStock ? () => _handleAdd(product) : null,
          ),
        ],
      ),
    );
  }

  Widget _weightSelectorSection(
    AppLocalizations l10n,
    double pricePerUom,
    String languageCode,
  ) {
    final weight = _weight!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                key: const Key('weightDecrementButton'),
                onPressed: weight.canDecrement ? _decrementWeight : null,
                icon: const Icon(Iconsax.minus_cirlce),
              ),
              Text(
                formatWeightGrams(
                  weight.grams,
                  gramUnit: l10n.unitGram,
                  kgUnit: l10n.unitKg,
                ),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ZadColors.ink,
                ),
              ),
              IconButton(
                key: const Key('weightIncrementButton'),
                onPressed: weight.canIncrement ? _incrementWeight : null,
                icon: const Icon(Iconsax.add_circle),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatPrice(weight.totalPrice(pricePerUom), languageCode),
            key: const Key('weightTotalPrice'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ZadColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyStepperSection(
    AppLocalizations l10n,
    double pricePerUom,
    String languageCode,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                key: const Key('qtyDecrementButton'),
                onPressed: _qty > 1 ? _decrementQty : null,
                icon: const Icon(Iconsax.minus_cirlce),
              ),
              Text(
                '$_qty',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ZadColors.ink,
                ),
              ),
              IconButton(
                key: const Key('qtyIncrementButton'),
                onPressed: _incrementQty,
                icon: const Icon(Iconsax.add_circle),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatPrice(pricePerUom * _qty, languageCode),
            key: const Key('qtyTotalPrice'),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: ZadColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.inStock, required this.l10n});

  final bool inStock;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: inStock
            ? ZadColors.paleGreen
            : ZadColors.ink.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        inStock ? l10n.inStock : l10n.outOfStock,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: inStock ? ZadColors.primary : Colors.white,
        ),
      ),
    );
  }
}
