import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/category.dart';
import '../../category/category_browser_page.dart';
import '../../category/widgets/category_tile.dart';

/// "Shop By Category" shelf: two rows that scroll **horizontally** so the first
/// eight groups sit in view (4 columns × 2 rows) and any extras flow into new
/// columns to the side — no stray third row. Columns fill top-to-bottom
/// (column-major), which keeps the first eight groups the visible ones and lets
/// the ninth peek in at the trailing edge as the scroll affordance. The scroll
/// is direction-aware: it runs right→left under an RTL (Arabic) locale.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({required this.categories, super.key});

  final List<GroceryCategory> categories;

  /// Rows in the shelf, and how many columns stay in view at once.
  static const int _rows = 2;
  static const int _visibleColumns = 4;

  /// Gaps: between columns, and between the two rows.
  static const double _colSpacing = 12;
  static const double _rowSpacing = 16;

  /// Fraction of the next column left visible as the "scroll me" hint when the
  /// shelf overflows its four visible columns.
  static const double _peek = 0.35;

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
        // next one peeks past the trailing edge. When it fits, the four columns
        // fill the row exactly — nothing to reveal, so nothing peeks.
        final colWidth = scrolls
            ? (width - _visibleColumns * _colSpacing) / (_visibleColumns + _peek)
            : (width - (_visibleColumns - 1) * _colSpacing) / _visibleColumns;

        final tileHeight = colWidth + _imageLabelGap + _labelHeight;
        final shelfHeight = tileHeight * _rows + _rowSpacing;

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

  /// One category tile at a fixed [height]. An out-of-range [index] (the empty
  /// bottom slot of a final, odd column) renders a same-height spacer so both
  /// rows stay aligned.
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
              child: CategoryTile(imageUrl: category.imageUrl),
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
