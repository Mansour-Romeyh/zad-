import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/catalog_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/category.dart';
import '../basket/widgets/cart_fab.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/section_state.dart';
import '../product/paged_products_view.dart';
import 'widgets/category_products_skeleton.dart';
import 'widgets/category_rail.dart';

/// Route arguments for `/categories`. [initialGroupId] pre-selects a rail
/// entry when the browser is opened from a specific category tile; null (the
/// "See All" entry point) selects the first category.
class CategoryBrowserArgs {
  const CategoryBrowserArgs({this.initialGroupId});

  final String? initialGroupId;
}

/// `/categories` — the "Shop By Category" browser (PRD F3): a rail of every
/// Item Group on the start side and the selected group's paged products on
/// the other. Selection is swapped in place (no navigation); the products
/// pane is a [PagedProductsView] keyed by the selected id so it reloads on
/// switch. The narrow pane passes a fixed [PagedProductsView.mainAxisExtent]
/// so its 2-column cards never overflow.
class CategoryBrowserPage extends StatefulWidget {
  const CategoryBrowserPage({super.key});

  @override
  State<CategoryBrowserPage> createState() => _CategoryBrowserPageState();
}

class _CategoryBrowserPageState extends State<CategoryBrowserPage> {
  static const double _cellHeight =
      250 + kProductCardControlHeight + kProductCardControlGap;

  SectionState<List<GroceryCategory>> _state = const SectionState.loading();

  /// Null until the user taps a rail item; while null the selection falls back
  /// to the route arg / first category (see [_resolveSelected]).
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const SectionState.loading());
    try {
      final categories = await context.read<CatalogRepository>().getCategories();
      if (!mounted) return;
      setState(() => _state = SectionState.data(categories));
    } catch (e) {
      if (!mounted) return;
      setState(() => _state = SectionState.error(e));
    }
  }

  /// The active group: the user's tapped id if any, else the route arg's group
  /// (when present in the loaded list), else the first category.
  String _resolveSelected(List<GroceryCategory> categories) {
    final tapped = _selectedId;
    if (tapped != null) return tapped;
    final args = ModalRoute.of(context)?.settings.arguments;
    final wanted = args is CategoryBrowserArgs ? args.initialGroupId : null;
    final match = categories.where((c) => c.id == wanted);
    return match.isNotEmpty ? match.first.id : categories.first.id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        title: Text(l10n.shopByCategory),
      ),
      // Pushed routes have no bottom-nav basket icon — this floating button is
      // how a shopper reaches the basket after adding items here. Hidden until
      // the cart has something in it.
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: AsyncSection<List<GroceryCategory>>(
          state: _state,
          skeleton: const Center(child: CircularProgressIndicator()),
          onRetry: _load,
          isEmpty: (data) => data.isEmpty,
          emptyBuilder: (context) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ZadSpacing.screenPadding),
              child: Text(
                l10n.categoriesEmpty,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ZadColors.muted, fontSize: 14),
              ),
            ),
          ),
          builder: (context, categories) {
            final selectedId = _resolveSelected(categories);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CategoryRail(
                  categories: categories,
                  selectedId: selectedId,
                  onSelect: (id) => setState(() => _selectedId = id),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeIn,
                    // A gentle fade + short vertical settle (direction-agnostic,
                    // so it reads the same in Arabic) when the group changes —
                    // no spinner-flash swap.
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: PagedProductsView(
                      key: ValueKey(selectedId),
                      fetchPage: (page) => context
                          .read<CatalogRepository>()
                          .itemsByCategory(selectedId, page: page),
                      emptyText: l10n.categoryItemsEmpty,
                      mainAxisExtent: _cellHeight,
                      skeleton: const CategoryProductsSkeleton(
                        cellHeight: _cellHeight,
                      ),
                      animateEntrance: true,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
