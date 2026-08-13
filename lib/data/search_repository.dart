import '../core/api/api_client.dart';
import '../models/paged_items.dart';
import '../models/product.dart';

/// Thin, typed wrapper over `grocery.api.search.*` (PRD F3).
///
/// [query] and [trending] are guest-accessible; [recent]/[clearRecent]
/// require a logged-in session — the backend returns 401 for guests, which
/// [ApiClient] surfaces as [UnauthenticatedException]. Callers must check
/// `SessionStore.isAuthed` before calling them (Task 5 binding decisions).
class SearchRepository {
  SearchRepository(this._client);

  final ApiClient _client;

  /// `search.query {q, page}` — paged envelope `{items, page, has_more}`,
  /// same shape as the catalog paged endpoints. The backend logs the query
  /// as a Recent Search server-side when the caller is authed.
  Future<PagedItems<Product>> query(String q, {int page = 1}) async {
    final data = await _client.post(
      'grocery.api.search.query',
      data: {'q': q, 'page': page},
    );
    return PagedItems.fromJson(
      data,
      itemFromJson: (json) =>
          Product.fromJson(json, resolveImageUrl: _client.resolveFileUrl),
      pageSize: 20,
    );
  }

  /// `search.recent` — bare list of up to 10 past query strings, most
  /// recent first (server-side ordering/limit).
  Future<List<String>> recent() async {
    final data = await _client.post('grocery.api.search.recent');
    if (data is! List) return const [];
    return data.map((e) => e.toString()).toList();
  }

  /// `search.clear_recent` — clears the caller's recent-search history.
  Future<void> clearRecent() async {
    await _client.post('grocery.api.search.clear_recent');
  }

  /// `search.trending` — bare ItemCard list (no paging envelope): top items
  /// by SO qty over the last 14 days, unioned with items flagged
  /// `custom_is_trending`.
  Future<List<Product>> trending() async {
    final data = await _client.post('grocery.api.search.trending');
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
}
