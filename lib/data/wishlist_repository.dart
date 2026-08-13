import '../core/api/api_client.dart';
import '../models/product.dart';

/// Thin, typed wrapper over `grocery.api.wishlist.*` (PRD F8). Every method
/// requires a logged-in session — the backend returns 401 for guests, which
/// [ApiClient] surfaces as [UnauthenticatedException]. `FavouritesStore`
/// only calls this when authed; guest heart taps are gated at the tap site.
class WishlistRepository {
  WishlistRepository(this._client);

  final ApiClient _client;

  /// ItemCard list of the logged-in user's favourites, newest first
  /// (server-ordered by `added_on desc`).
  Future<List<Product>> list() async {
    final data = await _client.get('grocery.api.wishlist.list');
    if (data is! List) return const [];
    return data
        .map(
          (e) => Product.fromJson(
            e as Map<String, dynamic>,
            resolveImageUrl: _client.resolveFileUrl,
          ),
        )
        .toList();
  }

  /// Favourites [itemCode]; idempotent server-side (a repeat add is a
  /// clean no-op, never an error).
  Future<void> add(String itemCode) async {
    await _client.post('grocery.api.wishlist.add', data: {'item_code': itemCode});
  }

  /// Un-favourites [itemCode]; idempotent server-side.
  Future<void> remove(String itemCode) async {
    await _client.post('grocery.api.wishlist.remove', data: {'item_code': itemCode});
  }
}
