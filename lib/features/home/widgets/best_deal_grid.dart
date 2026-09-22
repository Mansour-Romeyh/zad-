import 'package:flutter/material.dart';

import '../../../models/product.dart';
import '../../product/paged_products_view.dart' show kPagedProductCellExtent;
import 'product_card.dart';

/// "Best Deal" grid: a static **two-column** grid that grows downward, one row
/// per two products, showing every best-deal item at once. It does not scroll
/// on its own — it sizes to its content and lets the enclosing home page scroll
/// top-to-bottom (replacing the old horizontal, side-scrolling shelf). Cells
/// fill in reading order (row-major), so under an RTL (Arabic) locale the first
/// product sits top-right and each row reads right→left, courtesy of the
/// ambient [Directionality].
///
/// Columns and cell height match the full-screen best-deals grid
/// ([kPagedProductCellExtent]) so a product looks identical wherever it lands.
class BestDealGrid extends StatelessWidget {
  const BestDealGrid({required this.products, super.key});

  final List<Product> products;

  /// Columns per row.
  static const int _columns = 2;

  /// Gaps between columns and between rows.
  static const double _colSpacing = 14;
  static const double _rowSpacing = 16;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    final rowCount = (products.length / _columns).ceil();
    return Column(
      children: [
        for (var row = 0; row < rowCount; row++) ...[
          if (row > 0) const SizedBox(height: _rowSpacing),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < _columns; col++) ...[
                if (col > 0) const SizedBox(width: _colSpacing),
                Expanded(child: _cell(row * _columns + col)),
              ],
            ],
          ),
        ],
      ],
    );
  }

  /// One product cell at the shared fixed [kPagedProductCellExtent] height. An
  /// out-of-range [index] (the empty trailing slot of a final, odd row) renders
  /// a same-height spacer so the columns stay aligned.
  Widget _cell(int index) {
    if (index >= products.length) {
      return const SizedBox(height: kPagedProductCellExtent);
    }
    return SizedBox(
      height: kPagedProductCellExtent,
      child: ProductCard(product: products[index]),
    );
  }
}
