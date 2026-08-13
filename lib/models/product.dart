import '../core/json_utils.dart';

/// A catalog item, combining the original UI-mock fields (kept so existing
/// widgets/tests keep compiling) with the backend **ItemCard** shape
/// (PRD Part F3): `{item_code, item_name, image, price_per_uom, uom,
/// sold_by_weight, weight_step_g, min_g, max_g, available_qty, in_stock,
/// is_favourite?}`.
class Product {
  const Product({
    required this.id,
    required this.nameEn,
    required this.nameAr,
    required this.unitEn,
    required this.unitAr,
    required this.price,
    this.oldPrice,
    required this.imagePath,
    this.itemCode,
    this.imageUrl,
    this.pricePerUom,
    this.uom,
    this.soldByWeight = false,
    this.weightStepG,
    this.minG,
    this.maxG,
    this.availableQty,
    this.inStock = true,
    this.isFavourite,
    this.description,
  });

  // Original mock/display fields.
  final String id;
  final String nameEn;
  final String nameAr;
  final String unitEn;
  final String unitAr;
  final double price;
  final double? oldPrice;
  final String imagePath;

  // ItemCard fields.
  final String? itemCode;
  final String? imageUrl;
  final double? pricePerUom;
  final String? uom;
  final bool soldByWeight;
  final double? weightStepG;
  final double? minG;
  final double? maxG;
  final double? availableQty;
  final bool inStock;
  final bool? isFavourite;

  /// Short item description (`custom_short_desc` on the backend Item),
  /// only present on the `catalog.get_item` detail response (PRD F3: "ItemCard
  /// + description + weight config").
  final String? description;

  String nameFor(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;
  String unitFor(String languageCode) => languageCode == 'ar' ? unitAr : unitEn;

  /// Builds a [Product] from an ItemCard JSON payload. The backend already
  /// returns a locale-resolved `item_name`, so it is mapped into both
  /// [nameEn] and [nameAr] to keep [nameFor] working regardless of the
  /// requested language.
  ///
  /// [resolveImageUrl] turns the backend-relative `image` path (e.g.
  /// `/files/x.png`) into an absolute URL — pass [ApiClient.resolveFileUrl].
  /// When omitted, the raw path is kept as-is.
  factory Product.fromJson(
    Map<String, dynamic> json, {
    String? Function(String?)? resolveImageUrl,
  }) {
    final resolver = resolveImageUrl ?? (String? p) => p;
    final name = json['item_name'] as String? ?? '';
    final unit = json['uom'] as String? ?? '';
    final resolvedImage = resolver(json['image'] as String?);
    final pricePerUom = toDouble(json['price_per_uom']);

    return Product(
      id: json['item_code'] as String? ?? '',
      nameEn: name,
      nameAr: name,
      unitEn: unit,
      unitAr: unit,
      price: pricePerUom ?? 0,
      imagePath: resolvedImage ?? '',
      itemCode: json['item_code'] as String?,
      imageUrl: resolvedImage,
      pricePerUom: pricePerUom,
      uom: json['uom'] as String?,
      soldByWeight: toBool(json['sold_by_weight']),
      weightStepG: toDouble(json['weight_step_g']),
      minG: toDouble(json['min_g']),
      maxG: toDouble(json['max_g']),
      availableQty: toDouble(json['available_qty']),
      inStock: toBool(json['in_stock'], fallback: true),
      isFavourite:
          json.containsKey('is_favourite') && json['is_favourite'] != null
          ? toBool(json['is_favourite'])
          : null,
      description: json['description'] as String?,
    );
  }
}
