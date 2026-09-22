import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

/// Renders a network image with a disk cache, decode downsizing, a loading
/// spinner, and a graceful fallback.
///
/// - While the image downloads, shows [loading] — by default a small brand
///   spinner — so the user gets a clear "loading" cue instead of the fallback
///   artwork flashing in first and then being swapped for the real image.
/// - Shows [placeholder] immediately when [url] is null/empty (nothing to
///   load), and if the load fails (offline, 404, broken path) — never a
///   broken-image icon or an uncaught error in tests.
/// - Backed by [CachedNetworkImage]: the bytes are cached on disk, so an
///   image is downloaded once and reused across scrolls and app launches
///   (Flutter's plain `Image.network` keeps only an in-memory cache and
///   re-downloads everything on the next launch). A cached image paints at
///   once, so the spinner only appears on the first, uncached load.
/// - Decodes to the display size (× devicePixelRatio) via [LayoutBuilder]
///   rather than the source's full resolution, so an oversized upload no
///   longer decodes as multi-megapixel bitmaps that jank the grid.
class RemoteImage extends StatelessWidget {
  const RemoteImage({
    required this.url,
    required this.placeholder,
    this.loading = defaultLoading,
    this.fit = BoxFit.contain,
    super.key,
  });

  final String? url;

  /// Shown when there is nothing to load ([url] null/empty) or the load fails.
  final Widget placeholder;

  /// Shown while the network image downloads. Defaults to [defaultLoading];
  /// pass your own to resize or restyle it for a particular slot.
  final Widget loading;
  final BoxFit fit;

  /// A small, centered progress spinner in the brand colour, sized modestly so
  /// it reads well inside both large banners and small thumbnails. This is the
  /// app-wide "loading" cue for network images.
  static const Widget defaultLoading = Center(
    child: SizedBox(
      width: 24,
      height: 24,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        color: ZadColors.primary,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final src = url;
    if (src == null || src.isEmpty) return placeholder;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cap decode/cache resolution at the on-screen size. Null when the
        // width is unbounded (rare for image containers) — then decode full.
        final targetWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth * dpr).round().clamp(1, 4096)
            : null;
        return CachedNetworkImage(
          imageUrl: src,
          fit: fit,
          memCacheWidth: targetWidth,
          maxWidthDiskCache: targetWidth,
          fadeInDuration: const Duration(milliseconds: 150),
          placeholder: (context, _) => loading,
          errorWidget: (context, _, _) => placeholder,
        );
      },
    );
  }
}
