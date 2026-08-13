import '../core/json_utils.dart';

/// A catalog category, combining the original UI-mock fields with the
/// backend `catalog.get_categories` item shape (PRD Part F3):
/// `{name, label, image, item_count}`.
class GroceryCategory {
  const GroceryCategory({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.imagePath,
    this.name,
    this.label,
    this.imageUrl,
    this.itemCount,
  });

  // Original mock/display fields.
  final String id;
  final String nameEn;
  final String nameAr;
  final String imagePath;

  // Backend fields.
  /// The Item Group id (Frappe doc name).
  final String? name;
  final String? label;
  final String? imageUrl;
  final int? itemCount;

  String nameFor(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;

  /// Builds a [GroceryCategory] from a `catalog.get_categories` item. The
  /// backend returns a single locale-resolved `label`, mapped into both
  /// [nameEn] and [nameAr] to keep [nameFor] working regardless of the
  /// requested language.
  factory GroceryCategory.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveImageUrl,
  }) {
    final resolver = resolveImageUrl ?? (String? p) => p;
    final label = json['label'] as String? ?? '';
    final resolvedImage = resolver(json['image'] as String?);

    return GroceryCategory(
      id: json['name'] as String? ?? '',
      nameEn: label,
      nameAr: label,
      imagePath: resolvedImage ?? '',
      name: json['name'] as String?,
      label: json['label'] as String?,
      imageUrl: resolvedImage,
      itemCount: toInt(json['item_count']),
    );
  }
}
