import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/remote_image.dart';

/// The shared Item Group image container: a rounded-square tile (radius
/// [ZadRadii.tile]) holding the group image *contained* with [padding], and an
/// [Iconsax.category] placeholder when the image is missing or fails to load.
/// Used by both the Home category grid and the category browser's side rail so
/// the same Item Group renders identically in both. Purely presentational —
/// each caller supplies the [fillColor]/[borderColor] that contrast with its
/// own background, and owns its own sizing (e.g. an [AspectRatio]) and any
/// press/selection animation.
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
    this.padding = const EdgeInsets.all(10),
    super.key,
  });

  final String? imageUrl;
  final Color fillColor;
  final Color? borderColor;
  final double borderWidth;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
        border: borderColor == null
            ? null
            : Border.all(color: borderColor!, width: borderWidth),
      ),
      child: Padding(
        padding: padding,
        child: RemoteImage(
          url: imageUrl,
          placeholder: const Icon(Iconsax.category, color: ZadColors.muted),
        ),
      ),
    );
  }
}
