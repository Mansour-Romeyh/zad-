import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/session/session_store.dart';
import '../../core/stores/favourites_store.dart';
import '../../core/theme.dart';
import '../../data/search_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/product.dart';
import '../basket/widgets/cart_fab.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/product_card.dart';
import '../home/widgets/section_state.dart';

/// `/search` — PRD F3 `search.*` (Task 5).
///
/// An autofocused search field drives two mutually exclusive body states:
///
/// - **Idle** (field empty): Recent Searches (authed only — the endpoint is
///   never called for guests) as tappable chips with a clear-all action,
///   plus Trending item names as tappable chips (names only, never full
///   cards). Tapping any chip fills the field and runs that query.
/// - **Results** (committed query): the debounced (350ms) query's paged
///   ItemCard grid, with the same infinite-scroll + viewport-fill-fallback
///   pagination as the category page, an empty-results message, and a
///   retry prompt on failure.
///
/// After a search completes the backend has logged it server-side (authed
/// callers), so the recent list is *refetched* — never appended locally.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _debounceDuration = Duration(milliseconds: 350);
  static const _loadMoreThresholdPx = 200;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  /// Bumped on every committed query (and on reset-to-idle) so responses
  /// belonging to an abandoned query are dropped instead of clobbering the
  /// state of the one the user typed after it.
  int _generation = 0;

  /// The committed (already debounced) query; empty string = idle state.
  String _query = '';
  SectionState<List<Product>> _results = const SectionState.data([]);
  int _page = 1;
  bool _hasMore = false;
  bool _loadingMore = false;

  SectionState<List<String>> _recent = const SectionState.loading();
  SectionState<List<Product>> _trending = const SectionState.loading();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadTrending();
    // Guests never hit search.recent (401) — the section simply doesn't
    // exist for them.
    if (context.read<SessionStore>().isAuthed) _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // ── Idle sections ────────────────────────────────────────────────────

  Future<void> _loadTrending() async {
    setState(() => _trending = const SectionState.loading());
    try {
      final items = await context.read<SearchRepository>().trending();
      if (!mounted) return;
      setState(() => _trending = SectionState.data(items));
    } catch (e) {
      if (!mounted) return;
      setState(() => _trending = SectionState.error(e));
    }
  }

  Future<void> _loadRecent() async {
    setState(() => _recent = const SectionState.loading());
    try {
      final queries = await context.read<SearchRepository>().recent();
      if (!mounted) return;
      setState(() => _recent = SectionState.data(queries));
    } catch (e) {
      if (!mounted) return;
      setState(() => _recent = SectionState.error(e));
    }
  }

  /// Refetches the recent list after a completed search — the backend logs
  /// the query server-side, so the fresh truth comes from the endpoint,
  /// never from an optimistic local append. Failures are swallowed: search
  /// results (the user's actual goal) already rendered.
  Future<void> _refreshRecent() async {
    if (!context.read<SessionStore>().isAuthed) return;
    try {
      final queries = await context.read<SearchRepository>().recent();
      if (!mounted) return;
      setState(() => _recent = SectionState.data(queries));
    } catch (_) {
      // Keep whatever list was already shown.
    }
  }

  Future<void> _clearRecent() async {
    try {
      await context.read<SearchRepository>().clearRecent();
      if (!mounted) return;
      setState(() => _recent = const SectionState.data([]));
    } catch (_) {
      // Clearing failed — the existing chips stay, nothing to roll back.
    }
  }

  // ── Query lifecycle ──────────────────────────────────────────────────

  void _onSearchTextChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      _resetToIdle();
      return;
    }
    _debounce = Timer(_debounceDuration, () => _startSearch(q));
  }

  void _resetToIdle() {
    _generation++; // in-flight query responses become stale
    setState(() {
      _query = '';
      _results = const SectionState.data([]);
      _hasMore = false;
      _loadingMore = false;
    });
  }

  /// Fills the field with a chip's query and runs it immediately (no
  /// debounce — a tap is already a committed intent). Programmatic
  /// controller writes don't fire [TextField.onChanged], so no double run.
  void _runChipQuery(String q) {
    _debounce?.cancel();
    _searchController.text = q;
    _searchController.selection = TextSelection.collapsed(offset: q.length);
    _startSearch(q);
  }

  Future<void> _startSearch(String q) async {
    final generation = ++_generation;
    setState(() {
      _query = q;
      _results = const SectionState.loading();
      _page = 1;
      _hasMore = false;
      _loadingMore = false;
    });
    try {
      final result = await context.read<SearchRepository>().query(q, page: 1);
      if (!mounted || generation != _generation) return;
      // ItemCard payloads carry `is_favourite` for authed users — seed the
      // hearts (seed-only, never un-favourites).
      context.read<FavouritesStore>().seed(result.items);
      setState(() {
        _results = SectionState.data(result.items);
        // From the backend envelope — never inferred from page length.
        _hasMore = result.hasMore;
      });
      _autoLoadIfUnderfilled();
      // The backend just logged this query for authed users (PRD F3).
      _refreshRecent();
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _results = SectionState.error(e));
    }
  }

  void _onScroll() {
    if (_query.isEmpty || _loadingMore || !_hasMore) return;
    if (_results.status != SectionStatus.data) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThresholdPx) {
      _loadNextPage();
    }
  }

  /// Same viewport-fill fallback as the category page: when a loaded page
  /// renders shorter than the viewport, scroll events can never fire, so
  /// after every successful load check (post-layout) whether the grid is
  /// still unscrollable while `has_more` promises more — and fetch directly.
  /// No loop: each check is scheduled only by a successful load,
  /// [_loadNextPage] flips [_loadingMore] synchronously, and the chain ends
  /// when `has_more` goes false or the grid becomes scrollable.
  void _autoLoadIfUnderfilled() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _query.isEmpty || _loadingMore || !_hasMore) return;
      if (_results.status != SectionStatus.data) return;
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        return; // scrollable — normal scroll-driven pagination takes over
      }
      _loadNextPage();
    });
  }

  Future<void> _loadNextPage() async {
    final generation = _generation;
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final result = await context
          .read<SearchRepository>()
          .query(_query, page: nextPage);
      if (!mounted || generation != _generation) return;
      context.read<FavouritesStore>().seed(result.items);
      setState(() {
        _results = SectionState.data([...?_results.data, ...result.items]);
        _page = nextPage;
        _hasMore = result.hasMore;
        _loadingMore = false;
      });
      _autoLoadIfUnderfilled();
    } catch (_) {
      // Drop the failed page silently (loaded items stay); the next scroll
      // tick retries because has_more is untouched.
      if (!mounted || generation != _generation) return;
      setState(() => _loadingMore = false);
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsetsDirectional.only(
            end: ZadSpacing.screenPadding,
          ),
          child: Container(
            height: 44,
            decoration: const BoxDecoration(
              color: ZadColors.surface,
              borderRadius: BorderRadius.all(Radius.circular(22)),
            ),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchTextChanged,
              style: const TextStyle(fontSize: 14, color: ZadColors.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: l10n.searchHint,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: ZadColors.muted,
                ),
                prefixIcon: const Icon(
                  Iconsax.search_normal_1,
                  color: ZadColors.muted,
                  size: 20,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: _query.isEmpty ? _idleView(context, l10n) : _resultsView(l10n),
      ),
    );
  }

  Widget _idleView(BuildContext context, AppLocalizations l10n) {
    final isAuthed = context.watch<SessionStore>().isAuthed;
    return ListView(
      padding: const EdgeInsets.all(ZadSpacing.screenPadding),
      children: [
        if (isAuthed) _recentSection(l10n),
        _trendingSection(l10n),
      ],
    );
  }

  /// Recent Searches: skeleton while loading, hidden entirely when empty
  /// or failed (a history list is not worth a retry block — trending below
  /// remains the idle screen's main content).
  Widget _recentSection(AppLocalizations l10n) {
    switch (_recent.status) {
      case SectionStatus.loading:
        return const Padding(
          padding: EdgeInsets.only(bottom: ZadSpacing.sectionGap),
          child: SectionSkeleton(height: 76),
        );
      case SectionStatus.error:
        return const SizedBox.shrink();
      case SectionStatus.data:
        final queries = _recent.data ?? const [];
        if (queries.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: ZadSpacing.sectionGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: _SectionTitle(l10n.searchRecentTitle)),
                  TextButton(
                    onPressed: _clearRecent,
                    child: Text(
                      l10n.searchClearAll,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: ZadColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _chipsWrap(queries),
            ],
          ),
        );
    }
  }

  /// Trending: item *names* as tappable chips — never full product cards
  /// (Task 5 binding decision).
  Widget _trendingSection(AppLocalizations l10n) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return AsyncSection<List<Product>>(
      state: _trending,
      skeleton: const SectionSkeleton(height: 76),
      onRetry: _loadTrending,
      isEmpty: (items) => items.isEmpty,
      emptyBuilder: (_) => const SizedBox.shrink(),
      builder: (context, items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(l10n.searchTrendingTitle),
          const SizedBox(height: 12),
          _chipsWrap(items.map((p) => p.nameFor(languageCode)).toList()),
        ],
      ),
    );
  }

  Widget _chipsWrap(List<String> labels) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final label in labels)
          _QueryChip(label: label, onTap: () => _runChipQuery(label)),
      ],
    );
  }

  Widget _resultsView(AppLocalizations l10n) {
    return AsyncSection<List<Product>>(
      state: _results,
      skeleton: const Center(child: CircularProgressIndicator()),
      onRetry: () => _startSearch(_query),
      isEmpty: (items) => items.isEmpty,
      emptyBuilder: (context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: Text(
            l10n.searchNoResults(_query),
            textAlign: TextAlign.center,
            style: const TextStyle(color: ZadColors.muted, fontSize: 14),
          ),
        ),
      ),
      builder: (context, items) => _ResultsGrid(
        items: items,
        controller: _scrollController,
        loadingMore: _loadingMore,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: ZadColors.ink,
      ),
    );
  }
}

/// A tappable query chip (recent search or trending item name).
class _QueryChip extends StatelessWidget {
  const _QueryChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZadColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ZadColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Same 2-column ItemCard grid as the category page, with the trailing
/// loading-more indicator while the next page is in flight.
class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({
    required this.items,
    required this.controller,
    required this.loadingMore,
  });

  final List<Product> items;
  final ScrollController controller;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: controller,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 14,
              childAspectRatio: 0.62,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  Center(child: ProductCard(product: items[index])),
              childCount: items.length,
            ),
          ),
        ),
        if (loadingMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        // Room for the floating basket button when it shows, so the last row
        // isn't hidden behind it.
        SliverToBoxAdapter(
          child: SizedBox(height: 12 + cartFabClearanceOf(context)),
        ),
      ],
    );
  }
}
