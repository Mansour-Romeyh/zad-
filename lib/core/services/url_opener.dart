import 'package:url_launcher/url_launcher.dart';

/// A thin, injectable seam over `url_launcher`, so opening external links is
/// testable without the platform channel. [open] returns whether the URL was
/// handed off to the OS; callers show an error affordance on false.
abstract class UrlOpener {
  Future<bool> open(String url);
}

class DefaultUrlOpener implements UrlOpener {
  const DefaultUrlOpener();

  @override
  Future<bool> open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.isEmpty) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
