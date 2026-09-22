import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../data/catalog_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/paged_items.dart';
import '../../models/product.dart';
import '../basket/widgets/cart_fab.dart';
import 'paged_products_view.dart';

/// Route arguments for [BannerItemsPage]: the item codes to show, and the
/// screen title (the banner's own title).
class BannerItemsArgs {
  const BannerItemsArgs(this.itemCodes, this.title);
  final List<String> itemCodes;
  final String title;
}

/// `/banner-items` — the screen a multi-item banner (App Banner
/// `link_type='Items'`) opens: the selected items in the standard 2-column
/// product grid, titled with the banner's title. Reuses [PagedProductsView];
/// the selection is a single bounded page (`has_more: false`), so page 2+ is
/// never fetched.
class BannerItemsPage extends StatelessWidget {
  const BannerItemsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final args = ModalRoute.of(context)?.settings.arguments;
    final codes = args is BannerItemsArgs ? args.itemCodes : const <String>[];
    final title = args is BannerItemsArgs && args.title.trim().isNotEmpty
        ? args.title
        : l10n.bannerItemsTitle;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        title: Text(title),
      ),
      floatingActionButton: const CartFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: PagedProductsView(
          fetchPage: (page) => page == 1
              ? context.read<CatalogRepository>().getItemsByCodes(codes)
              : Future.value(
                  const PagedItems<Product>(items: [], hasMore: false),
                ),
          emptyText: l10n.bannerItemsEmpty,
        ),
      ),
    );
  }
}
