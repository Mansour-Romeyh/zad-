/// A home-screen banner (PRD F2 `home.get_banners`):
/// `{image, title, link_type, link_value, link_items}`.
class AppBannerModel {
  const AppBannerModel({
    this.imageUrl,
    required this.title,
    this.linkType,
    this.linkValue,
    this.linkItems = const [],
  });

  final String? imageUrl;
  final String title;
  final String? linkType;
  final String? linkValue;

  /// Item codes for a `link_type == 'Items'` banner, in the admin's order.
  /// Empty for every other link type.
  final List<String> linkItems;

  factory AppBannerModel.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveImageUrl,
  }) {
    final resolver = resolveImageUrl ?? (String? p) => p;
    return AppBannerModel(
      imageUrl: resolver(json['image'] as String?),
      title: json['title'] as String? ?? '',
      linkType: json['link_type'] as String?,
      linkValue: json['link_value'] as String?,
      linkItems: _parseLinkItems(json['link_items']),
    );
  }

  /// Tolerant parse of the `link_items` payload: a list of item codes, with
  /// blanks dropped; anything else (missing / not a list) becomes empty.
  static List<String> _parseLinkItems(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);
  }
}
