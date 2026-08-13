import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/catalog_repository.dart';
import '../../l10n/app_localizations.dart';
import '../basket/widgets/cart_fab.dart';
import 'paged_products_view.dart';

/// `/best-deals` — the home "Best Deal" section's See All target: the full
/// `catalog.get_best_items` listing (home shows only the first page).
/// Pagination, empty, and error/retry handling live in [PagedProductsView].
class BestDealsPage extends StatelessWidget {
  const BestDealsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        title: Text(l10n.bestDeal),
      ),
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: PagedProductsView(
          fetchPage: (page) =>
              context.read<CatalogRepository>().getBestItems(page: page),
          emptyText: l10n.bestItemsEmpty,
        ),
      ),
    );
  }
}
