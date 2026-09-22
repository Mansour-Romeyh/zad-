import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/category.dart';
import '../../category/category_browser_page.dart';
import '../../category/widgets/category_tile.dart';

/// "Shop By Category" shelf: **three rows** that scroll **horizontally** so the
/// first nine groups sit in view (3 columns × 3 rows) with larger tiles, and any
/// extras flow into new columns to the side — never a fourth row. Columns fill
/// top-to-bottom (column-major), which keeps the first nine groups the visible
/// ones and lets the tenth peek in at the trailing edge as the scroll
/// affordance. The scroll is direction-aware: a horizontal [ListView] takes its
/// leading edge from the ambient [Directionality], so it runs right→left under
/// an RTL (Arabic) locale automatically.
///
/// Showing three visible columns (not four) makes each Item Group image
/// noticeably bigger than the old four-up shelf.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({required this.categories, super.key});

  final List<GroceryCategory> categories;

  /// Rows in the shelf, and how many columns stay in view at once.
  static const int _rows = 3;
  static const int _visibleColumns = 3;

  /// Gaps: between columns, and between rows.
  static const double _colSpacing = 12;
  static const double _rowSpacing = 16;

  /// Fraction of the next column left visible as the "scroll me" hint when the
  /// shelf overflows its three visible columns. Kept small so the visible tiles
  /// stay large.
  static const double _peek = 0.2;

  /// Fixed vertical budget below each square tile for its (up to) two-line
  /// label, so label room stays constant no matter how wide the column is.
  static const double _imageLabelGap = 6;
  static const double _labelHeight = 30;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columnCount = (categories.length / _rows).ceil();
        final scrolls = columnCount > _visibleColumns;

        // When the shelf overflows, narrow the columns just enough that the
        // next one peeks past the trailing edge. When it fits, the three
        // columns fill the row exactly — nothing to reveal, so nothing peeks.
        final colWidth = scrolls
            ? (width - _visibleColumns * _colSpacing) / (_visibleColumns + _peek)
            : (width - (_visibleColumns - 1) * _colSpacing) / _visibleColumns;

        final tileHeight = colWidth + _imageLabelGap + _labelHeight;
        final shelfHeight = tileHeight * _rows + (_rows - 1) * _rowSpacing;

        return SizedBox(
          height: shelfHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: scrolls
                ? const BouncingScrollPhysics()
                : const NeverScrollableScrollPhysics(),
            itemCount: columnCount,
            separatorBuilder: (_, _) => const SizedBox(width: _colSpacing),
            itemBuilder: (context, col) => SizedBox(
              width: colWidth,
              child: Column(
                children: [
                  for (var row = 0; row < _rows; row++) ...[
                    if (row > 0) const SizedBox(height: _rowSpacing),
                    _cell(context, col * _rows + row, tileHeight, languageCode),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// One category tile at a fixed [height]. An out-of-range [index] (an empty
  /// bottom slot of a final, partly-filled column) renders a same-height spacer
  /// so all three rows stay aligned.
  Widget _cell(
    BuildContext context,
    int index,
    double height,
    String languageCode,
  ) {
    if (index >= categories.length) return SizedBox(height: height);

    final category = categories[index];
    final label = category.nameFor(languageCode);
    return SizedBox(
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pushNamed(
          context,
          '/categories',
          arguments: CategoryBrowserArgs(initialGroupId: category.id),
        ),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 1,
              // No grey ground behind the group image: a transparent-PNG icon
              // sits on the page, and a raster image already fills the tile.
              child: CategoryTile(
                imageUrl: category.imageUrl,
                fillColor: Colors.transparent,
              ),
            ),
            const SizedBox(height: _imageLabelGap),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.25,
                  color: ZadColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
