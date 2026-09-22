import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/remote_image.dart';

/// The shared Item Group image container: a rounded-square tile (radius
/// [ZadRadii.tile]) whose group image *fills* the tile edge-to-edge
/// ([BoxFit.cover]) and is clipped to the rounded corners, with an
/// [Iconsax.category] placeholder when the image is missing or fails to load.
/// Used by both the Home category grid and the category browser's side rail so
/// the same Item Group renders identically in both. Purely presentational —
/// each caller supplies the [fillColor]/[borderColor] that contrast with its
/// own background, and owns its own sizing (e.g. an [AspectRatio]) and any
/// press/selection animation.
///
/// When a [borderColor] is set the image is inset by [borderWidth] and clipped
/// to the matching inner radius, so a flush, edge-to-edge image never paints
/// over the (rail-selected) border. With no border it sits truly flush.
///
/// Deliberately a [DecoratedBox], not a [Container]/[AnimatedContainer]: the
/// rail test asserts exactly one pale-green [Container] (its selected pill), so
/// a pale-green tile fill must never register as a `Container`.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    required this.imageUrl,
    this.fillColor = ZadColors.surface,
    this.borderColor,
    this.borderWidth = 1,
    super.key,
  });

  final String? imageUrl;
  final Color fillColor;
  final Color? borderColor;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    // Inset the image by the stroke width only when a border is drawn, so the
    // border stays visible; otherwise the image is flush to the tile edge.
    final inset = borderColor == null ? 0.0 : borderWidth;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      child: Padding(
        padding: EdgeInsets.all(inset),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(ZadRadii.tile - inset),
          child: RemoteImage(
            url: imageUrl,
            fit: BoxFit.cover,
            placeholder: const Center(
              child: Icon(Iconsax.category, color: ZadColors.muted),
            ),
          ),
        ),
      ),
    );
  }
}
