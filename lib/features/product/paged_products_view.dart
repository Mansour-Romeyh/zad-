import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/stores/favourites_store.dart';
import '../../core/theme.dart';
import '../../models/paged_items.dart';
import '../../models/product.dart';
import '../basket/widgets/cart_fab.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/product_card.dart';
import '../home/widgets/section_state.dart';

/// Default cell height for the 2-column grid when the caller passes no
/// [PagedProductsView.mainAxisExtent] (e.g. the full-screen best-deals
/// page). Mirrors the category browser's fixed extent (`250 +
/// kProductCardControlHeight + kProductCardControlGap`): width-independent,
/// so on narrow / large-font devices the fixed-height card can never
/// overflow a ratio-shrunk cell.
const double kPagedProductCellExtent =
    250 + kProductCardControlHeight + kProductCardControlGap;

/// Paged 2-column [ProductCard] grid over a backend paged envelope
/// (`{items, page, has_more}`), with infinite scroll: the next page is
/// fetched once the grid is scrolled near its bottom, and fetching stops
/// once the envelope reports `has_more: false`. Shared by the category
/// listing and the best-deals listing, which differ only in [fetchPage].
class PagedProductsView extends StatefulWidget {
  const PagedProductsView({
    required this.fetchPage,
    required this.emptyText,
    this.mainAxisExtent,
    this.skeleton,
    this.animateEntrance = false,
    super.key,
  });

  /// Fetches one page of the listing (1-based).
  final Future<PagedItems<Product>> Function(int page) fetchPage;

  /// Message shown when the first page comes back empty.
  final String emptyText;

  /// Fixed cell height (px) for the 2-column grid. When null the grid falls
  /// back to [kPagedProductCellExtent] — still a fixed, width-independent
  /// height, just the full-width default; explicit-extent callers (the
  /// category browser's narrow pane) override it so cards never overflow
  /// there either.
  final double? mainAxisExtent;

  /// Placeholder shown while the first page loads. Defaults to a centered
  /// spinner; the category browser passes a skeleton grid so switching groups
  /// reads as an intentional load rather than a spinner flash.
  final Widget? skeleton;

  /// When true the grid's first appearance plays a subtle staggered fade+rise
  /// (one-shot, driven by a single ticker so scroll-recycled cards never
  /// re-animate). Off by default so other listings are unaffected.
  final bool animateEntrance;

  @override
  State<PagedProductsView> createState() => _PagedProductsViewState();
}

class _PagedProductsViewState extends State<PagedProductsView> {
  static const _loadMoreThresholdPx = 200;

  final _scrollController = ScrollController();

  SectionState<List<Product>> _state = const SectionState.loading();
  int _page = 1;
  bool _hasMore = true;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _state = const SectionState.loading();
      _page = 1;
      _hasMore = true;
    });
    try {
      final result = await widget.fetchPage(1);
      if (!mounted) return;
      // ItemCard payloads carry `is_favourite` for authed users — seed the
      // hearts (seed-only, never un-favourites).
      context.read<FavouritesStore>().seed(result.items);
      setState(() {
        _state = SectionState.data(result.items);
        // From the backend envelope — never inferred from page length.
        _hasMore = result.hasMore;
      });
      _autoLoadIfUnderfilled();
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = SectionState.error(e));
    }
  }

  void _onScroll() {
    if (_loadingMore || !_hasMore) return;
    if (_state.status != SectionStatus.data) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThresholdPx) {
      _loadNextPage();
    }
  }

  /// Infinite scroll dead-ends when a page renders shorter than the
  /// viewport: with nothing to scroll, [_onScroll] never fires and the next
  /// page is unreachable. So after every *successful* page load, check once
  /// the new items have laid out whether the grid is still unscrollable
  /// while `has_more` says more exist — and if so, fetch the next page
  /// directly. No loop is possible: each check is scheduled only by a
  /// successful load, [_loadNextPage] flips [_loadingMore] synchronously
  /// (blocking re-entry), and the chain ends as soon as the envelope
  /// reports `has_more: false` or the grid becomes scrollable.
  void _autoLoadIfUnderfilled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadingMore || !_hasMore) return;
      if (_state.status != SectionStatus.data) return;
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        return; // scrollable — normal scroll-driven pagination takes over
      }
      _loadNextPage();
    });
  }

  Future<void> _loadNextPage() async {
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final result = await widget.fetchPage(nextPage);
      if (!mounted) return;
      context.read<FavouritesStore>().seed(result.items);
      setState(() {
        _state = SectionState.data([...?_state.data, ...result.items]);
        _page = nextPage;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
      _autoLoadIfUnderfilled();
    } catch (_) {
      // Leave has_more as-is so the next scroll tick retries; just clear the
      // in-flight flag and drop the failed page silently (no full-page error
      // — the already-loaded items stay visible).
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AsyncSection<List<Product>>(
      state: _state,
      skeleton: widget.skeleton ??
          const Center(child: CircularProgressIndicator()),
      onRetry: _loadFirstPage,
      isEmpty: (data) => data.isEmpty,
      emptyBuilder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: Text(
            widget.emptyText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: ZadColors.muted, fontSize: 14),
          ),
        ),
      ),
      builder: (context, items) => _ProductsGrid(
        items: items,
        controller: _scrollController,
        loadingMore: _loadingMore,
        mainAxisExtent: widget.mainAxisExtent,
        animateEntrance: widget.animateEntrance,
      ),
    );
  }
}

class _ProductsGrid extends StatefulWidget {
  const _ProductsGrid({
    required this.items,
    required this.controller,
    required this.loadingMore,
    required this.mainAxisExtent,
    required this.animateEntrance,
  });

  final List<Product> items;
  final ScrollController controller;
  final bool loadingMore;
  final double? mainAxisExtent;
  final bool animateEntrance;

  @override
  State<_ProductsGrid> createState() => _ProductsGridState();
}

class _ProductsGridState extends State<_ProductsGrid>
    with SingleTickerProviderStateMixin {
  /// Runs once when the grid first mounts (per category, since a category
  /// switch builds a fresh grid). It reaches — and stays at — 1.0, so cards
  /// scrolled into view after it completes read a settled value and never
  /// re-animate. Only created when [_ProductsGrid.animateEntrance] is set.
  AnimationController? _entrance;

  @override
  void initState() {
    super.initState();
    if (widget.animateEntrance) {
      _entrance = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 620),
      )..forward();
    }
  }

  @override
  void dispose() {
    _entrance?.dispose();
    super.dispose();
  }

  /// A subtle fade + 8px rise for card [index], staggered by index (capped so
  /// later / paged-in cards never lag). Respects the platform "reduce motion"
  /// setting and the no-animation default.
  Widget _entranceWrap(int index, Widget child) {
    final controller = _entrance;
    if (controller == null || MediaQuery.of(context).disableAnimations) {
      return child;
    }
    final start = (index.clamp(0, 8)) * 0.06; // 0.00 .. 0.48
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(start, (start + 0.5).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, (1 - anim.value) * 8),
          child: child,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: widget.controller,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 14,
              // mainAxisExtent always wins over childAspectRatio, so the
              // grid is always height-fixed, never width-ratio-governed —
              // that keeps it width-independent, which matters because the
              // card's content is mostly fixed height (140 image +
              // kProductCardControlHeight/Gap control row + text): a
              // ratio-shrunk cell can end up shorter than the card on narrow
              // / large-font devices and overflow. Explicit-extent callers
              // (the category browser) still override via mainAxisExtent.
              mainAxisExtent: widget.mainAxisExtent ?? kPagedProductCellExtent,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _entranceWrap(index, ProductCard(product: widget.items[index])),
              childCount: widget.items.length,
            ),
          ),
        ),
        if (widget.loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        // Trailing gap, plus room for the floating basket button when it shows
        // so the last row is never hidden behind it.
        SliverToBoxAdapter(
          child: SizedBox(height: 12 + cartFabClearanceOf(context)),
        ),
      ],
    );
  }
}
