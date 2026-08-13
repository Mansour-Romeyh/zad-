import 'package:flutter/material.dart';

/// Renders a network image with a graceful fallback: shows [placeholder]
/// immediately when [url] is null/empty, and swaps to it if the network
/// load fails (offline, 404, broken backend path, ...) instead of letting
/// the image error surface as a broken-image icon — or, worse in widget
/// tests, as an uncaught error.
class RemoteImage extends StatelessWidget {
  const RemoteImage({
    required this.url,
    required this.placeholder,
    this.fit = BoxFit.contain,
    super.key,
  });

  final String? url;
  final Widget placeholder;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final src = url;
    if (src == null || src.isEmpty) return placeholder;
    return Image.network(
      src,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => placeholder,
    );
  }
}
