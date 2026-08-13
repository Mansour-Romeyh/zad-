import '../core/api/api_client.dart';
import '../models/category.dart';
import '../models/paged_items.dart';
import '../models/product.dart';

/// Thin, typed wrapper over `grocery.api.catalog.*` (PRD Part F3).
/// Guest-accessible.
///
/// Paged list endpoints (`items_by_category`, `get_best_items`) return the
/// backend envelope `{items, page, has_more}`, surfaced as [PagedItems];
/// `get_categories` returns a bare list and `get_item` a single object.
class CatalogRepository {
  CatalogRepository(this._client);

  final ApiClient _client;

  Future<List<GroceryCategory>> getCategories() async {
    final data = await _client.get('grocery.api.catalog.get_categories');
    if (data is! List) return const [];
    return data
        .map(
          (e) => GroceryCategory.fromJson(
            e as Map<String, dynamic>,
            resolveImageUrl: _client.resolveFileUrl,
          ),
        )
        .toList();
  }

  Future<PagedItems<Product>> itemsByCategory(
    String itemGroup, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _client.post(
      'grocery.api.catalog.items_by_category',
      data: {'item_group': itemGroup, 'page': page, 'page_size': pageSize},
    );
    return _pagedProducts(data, pageSize: pageSize);
  }

  Future<PagedItems<Product>> getBestItems({int page = 1}) async {
    final data = await _client.post(
      'grocery.api.catalog.get_best_items',
      data: {'page': page},
    );
    return _pagedProducts(data, pageSize: 20);
  }

  Future<Product> getItem(String itemCode) async {
    final data = await _client.post(
      'grocery.api.catalog.get_item',
      data: {'item_code': itemCode},
    );
    return Product.fromJson(
      data as Map<String, dynamic>,
      resolveImageUrl: _client.resolveFileUrl,
    );
  }

  PagedItems<Product> _pagedProducts(dynamic data, {required int pageSize}) {
    return PagedItems.fromJson(
      data,
      itemFromJson: (json) =>
          Product.fromJson(json, resolveImageUrl: _client.resolveFileUrl),
      pageSize: pageSize,
    );
  }
}
