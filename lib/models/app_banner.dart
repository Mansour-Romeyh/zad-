/// A home-screen banner (PRD F2 `home.get_banners`):
/// `{image, title, link_type, link_value}`.
class AppBannerModel {
  const AppBannerModel({
    this.imageUrl,
    required this.title,
    this.linkType,
    this.linkValue,
  });

  final String? imageUrl;
  final String title;
  final String? linkType;
  final String? linkValue;

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
    );
  }
}
