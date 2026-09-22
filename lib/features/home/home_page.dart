import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/stores/address_store.dart';
import '../../core/stores/cart_store.dart';
import '../../core/stores/favourites_store.dart';
import '../../core/theme.dart';
import '../../data/catalog_repository.dart';
import '../../data/content_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_banner.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../addresses/add_address_nudge_sheet.dart';
import '../basket/basket_page.dart';
import '../favourites/favourites_tab.dart';
import '../profile/profile_tab.dart';
import 'widgets/async_section.dart';
import 'widgets/best_deal_grid.dart';
import 'widgets/cart_fly.dart';
import 'widgets/category_grid.dart';
import 'widgets/location_header.dart';
import 'widgets/promo_banner.dart';
import 'widgets/search_field.dart';
import 'widgets/section_header.dart';
import 'widgets/section_state.dart';
import 'widgets/zad_bottom_nav.dart';

/// The bottom-nav shell: an `IndexedStack` of the four tabs (Home,
/// Favourites, Basket, Profile) behind [ZadBottomNav] — switching tabs
/// keeps each one's state alive (scroll position, in-flight cart edits,
/// ...) instead of rebuilding it from scratch. `/home` and `/basket`
/// (PRD navbar Home/Favourites/Basket/Profile) both route here, only
/// differing in which tab starts active.
class HomePage extends StatefulWidget {
  const HomePage({this.initialIndex = kHomeNavIndex, super.key});

  /// Which tab is active on first build — see the `kXNavIndex` constants
  /// in `zad_bottom_nav.dart`.
  final int initialIndex;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late int _navIndex = widget.initialIndex;

  /// Shared by the item cards (fly source) and the bottom-nav basket icon
  /// (fly target + bounce) via [CartFlyScope]. Owned here so its lifecycle
  /// matches the shell.
  final CartFlyController _flyController = CartFlyController();

  /// Safety cap on the best-deal page walk (20 items/page → 2000 items), so a
  /// backend that never clears `has_more` can't spin the loader forever.
  static const int _maxBestItemPages = 100;

  SectionState<List<GroceryCategory>> _categories =
      const SectionState.loading();
  SectionState<List<AppBannerModel>> _banners = const SectionState.loading();
  SectionState<List<Product>> _bestItems = const SectionState.loading();

  late final AddressStore _addressStore;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadBanners();
    _loadBestItems();
    // First-login no-address nudge (PRD A3): the store flips
    // `shouldShowNudge` once an authed session hydrates with zero
    // addresses. Checked post-frame for the common boot path (splash
    // hydrated the store before home mounted) and via the listener for a
    // hydrate that completes while home is on screen.
    _addressStore = context.read<AddressStore>();
    _addressStore.addListener(_maybeShowAddressNudge);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeShowAddressNudge(),
    );
  }

  @override
  void dispose() {
    _addressStore.removeListener(_maybeShowAddressNudge);
    _flyController.dispose();
    super.dispose();
  }

  void _maybeShowAddressNudge() {
    if (!mounted || !_addressStore.shouldShowNudge) return;
    // Consume BEFORE presenting: once per session, even if the store
    // notifies again while the sheet is open.
    _addressStore.consumeNudge();
    // Post-frame so a notify landing mid-build can never show a sheet
    // while the tree is locked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(ZadRadii.sheet),
          ),
        ),
        builder: (_) => const AddAddressNudgeSheet(),
      );
    });
  }

  Future<void> _loadCategories() async {
    final repo = context.read<CatalogRepository>();
    setState(() => _categories = const SectionState.loading());
    try {
      final categories = await repo.getCategories();
      if (!mounted) return;
      setState(() => _categories = SectionState.data(categories));
    } catch (e) {
      if (!mounted) return;
      setState(() => _categories = SectionState.error(e));
    }
  }

  Future<void> _loadBanners() async {
    final repo = context.read<ContentRepository>();
    setState(() => _banners = const SectionState.loading());
    try {
      final banners = await repo.getBanners();
      if (!mounted) return;
      setState(() => _banners = SectionState.data(banners));
    } catch (e) {
      if (!mounted) return;
      setState(() => _banners = SectionState.error(e));
    }
  }

  Future<void> _loadBestItems() async {
    final repo = context.read<CatalogRepository>();
    setState(() => _bestItems = const SectionState.loading());
    try {
      // The section shows every best-deal item (no See All), so walk the
      // paged envelope ({items, page, has_more}) to the end, accumulating
      // all pages. Guard a backend that never clears has_more: stop on an
      // empty page and cap the walk at _maxBestItemPages.
      final items = <Product>[];
      for (var page = 1; page <= _maxBestItemPages; page++) {
        final envelope = await repo.getBestItems(page: page);
        if (!mounted) return;
        items.addAll(envelope.items);
        if (!envelope.hasMore || envelope.items.isEmpty) break;
      }
      if (!mounted) return;
      // ItemCard payloads carry `is_favourite` for authed users — seed the
      // hearts (seed-only, never un-favourites).
      context.read<FavouritesStore>().seed(items);
      setState(() => _bestItems = SectionState.data(items));
    } catch (e) {
      if (!mounted) return;
      setState(() => _bestItems = SectionState.error(e));
    }
  }

  Future<void> _refreshAll() =>
      Future.wait([_loadCategories(), _loadBanners(), _loadBestItems()]);

  void _goToHomeTab() => setState(() => _navIndex = kHomeNavIndex);

  void _onNavTap(int index) {
    if (index == kBasketNavIndex && _navIndex != index) {
      // Opening the basket re-pulls the server cart (and retries any
      // pending guest-line merge) so the tab never shows stale/stranded
      // state. Fire-and-forget: refresh() no-ops for guests, the store
      // records failures on its busy/error state, and the swallow below
      // keeps a network error from ever blocking the tab switch.
      context.read<CartStore>().refresh().catchError((_) {});
    }
    if (index == kFavouritesNavIndex && _navIndex != index) {
      // Opening favourites re-pulls wishlist.list so the tab reflects
      // hearts toggled elsewhere (or on another device) since the last
      // hydrate. No-op for guests; never throws — a failure lands on the
      // store's error state, which the tab renders as a retry prompt.
      context.read<FavouritesStore>().refresh();
    }
    setState(() => _navIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return CartFlyScope(
      controller: _flyController,
      child: Scaffold(
        bottomNavigationBar: ZadBottomNav(
          activeIndex: _navIndex,
          onTap: _onNavTap,
        ),
        body: SafeArea(
          child: IndexedStack(
            index: _navIndex,
            children: [
              _homeContent(context),
              const FavouritesTab(),
              BasketPage(onShopNow: _goToHomeTab),
              const ProfileTab(),
            ],
          ),
        ),
      ),
    );
  }

  /// Whether the banner fetch succeeded with zero banners. In that case the
  /// promo slot (and its trailing section gap) is omitted entirely — no
  /// generic marketing card with a dead CTA. Loading and error states still
  /// occupy the slot so the skeleton/retry UI stays visible.
  bool get _bannersCollapsed =>
      _banners.status == SectionStatus.data && (_banners.data?.isEmpty ?? true);

  Widget _homeContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const hPad = EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding);
    return RefreshIndicator(
      onRefresh: _refreshAll,
      child: ListView(
        // Pull-to-refresh must work even when the sections above are short
        // enough to fit the viewport without needing to scroll.
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 12),
          const Padding(padding: hPad, child: LocationHeader()),
          const SizedBox(height: 20),
          const Padding(padding: hPad, child: SearchField()),
          const SizedBox(height: ZadSpacing.sectionGap),
          Padding(
            padding: hPad,
            child: SectionHeader(
              title: l10n.shopByCategory,
              titleFontSize: 22,
              titleFontWeight: FontWeight.bold,
              onSeeAll: () => Navigator.pushNamed(context, '/categories'),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: hPad,
            child: AsyncSection<List<GroceryCategory>>(
              state: _categories,
              skeleton: const SectionSkeleton(height: 180),
              onRetry: _loadCategories,
              isEmpty: (data) => data.isEmpty,
              emptyBuilder: (context) =>
                  _EmptyMessage(text: l10n.categoriesEmpty),
              builder: (context, data) => CategoryGrid(categories: data),
            ),
          ),
          const SizedBox(height: ZadSpacing.sectionGap),
          if (!_bannersCollapsed) ...[
            Padding(
              padding: hPad,
              child: AsyncSection<List<AppBannerModel>>(
                state: _banners,
                skeleton: const SectionSkeleton(height: 160),
                onRetry: _loadBanners,
                builder: (context, data) => PromoBanner(banners: data),
              ),
            ),
            const SizedBox(height: ZadSpacing.sectionGap),
          ],
          Padding(
            padding: hPad,
            // No "See All" — the section now lays out every best-deal item
            // (all pages) as a downward grid, so there is nothing more to see.
            child: SectionHeader(title: l10n.bestDeal),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: hPad,
            child: AsyncSection<List<Product>>(
              state: _bestItems,
              skeleton: const SectionSkeleton(height: 244),
              onRetry: _loadBestItems,
              isEmpty: (data) => data.isEmpty,
              emptyBuilder: (context) =>
                  _EmptyMessage(text: l10n.bestItemsEmpty),
              builder: (context, data) => BestDealGrid(products: data),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: ZadColors.muted, fontSize: 13),
        ),
      ),
    );
  }
}
