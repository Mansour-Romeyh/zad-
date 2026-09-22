import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../models/category.dart';
import 'category_tile.dart';

/// The category browser's side rail: a vertical, independently scrollable list
/// of every Item Group, sitting on a soft [ZadColors.surface] panel that
/// separates it from the white products pane with a faint inner-edge shadow
/// (no hard divider). The [selectedId] tile animates into a rounded pale-green
/// pill with a green-bordered [CategoryTile] and a bolder label; tapping
/// any tile calls [onSelect]. Directional throughout, so Arabic flips the rail
/// to the screen's end edge automatically.
class CategoryRail extends StatelessWidget {
  const CategoryRail({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
    super.key,
  });

  /// Fixed rail width (px).
  static const double width = 100;

  final List<GroceryCategory> categories;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ZadColors.surface,
          boxShadow: [
            BoxShadow(
              color: ZadColors.ink.withValues(alpha: 0.04),
              blurRadius: 12,
              // Cast toward the products pane (right in LTR, left in RTL).
              offset: Offset(isRtl ? -2 : 2, 0),
            ),
          ],
        ),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return _RailTile(
              key: ValueKey('railTile-${category.id}'),
              category: category,
              selected: category.id == selectedId,
              onTap: () => onSelect(category.id),
            );
          },
        ),
      ),
    );
  }
}

/// One rail entry. Stateful only to give the tap a light press-scale; the
/// selected/unselected transition is driven by implicit animations so moving
/// the selection reads as the pill easing from one tile to the next.
class _RailTile extends StatefulWidget {
  const _RailTile({
    required this.category,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final GroceryCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_RailTile> createState() => _RailTileState();
}

class _RailTileState extends State<_RailTile> {
  static const _motion = Duration(milliseconds: 220);
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final selected = widget.selected;
    final label = widget.category.nameFor(languageCode);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: _motion,
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? ZadColors.paleGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: CategoryTile(
                  imageUrl: widget.category.imageUrl,
                  fillColor: ZadColors.white,
                  borderColor: selected
                      ? ZadColors.primary
                      : ZadColors.muted.withValues(alpha: 0.2),
                  borderWidth: selected ? 1.5 : 1,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedDefaultTextStyle(
                duration: _motion,
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? ZadColors.ink : ZadColors.muted,
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
