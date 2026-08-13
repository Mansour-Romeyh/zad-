import '../core/json_utils.dart';

/// One page of a paged list endpoint. The backend wraps every paged list
/// (`catalog.items_by_category`, `catalog.get_best_items`, later
/// `search.query`) in the envelope `{"items": [...], "page": N,
/// "has_more": bool}` — [hasMore] comes straight from that envelope, so
/// callers must not infer it from the page length.
class PagedItems<T> {
  const PagedItems({required this.items, this.page = 1, required this.hasMore});

  final List<T> items;
  final int page;

  /// Whether another page exists after this one (envelope `has_more`).
  final bool hasMore;

  /// Parses a paged payload tolerantly:
  ///
  /// - A Map is the real contract: `items` / `page` / `has_more` (a missing
  ///   or malformed `has_more` is treated as `false` — ending pagination is
  ///   the safe failure mode).
  /// - A bare List is accepted defensively (older/other endpoints): treated
  ///   as the items with `hasMore` inferred from a full page
  ///   (`items.length == pageSize`).
  /// - Anything else becomes an empty last page.
  factory PagedItems.fromJson(
    dynamic data, {
    required T Function(Map<String, dynamic>) itemFromJson,
    required int pageSize,
  }) {
    if (data is Map) {
      final rawItems = data['items'];
      final items = rawItems is List
          ? rawItems
                .map((e) => itemFromJson(e as Map<String, dynamic>))
                .toList()
          : <T>[];
      return PagedItems(
        items: items,
        page: toInt(data['page']) ?? 1,
        hasMore: toBool(data['has_more']),
      );
    }
    if (data is List) {
      final items = data
          .map((e) => itemFromJson(e as Map<String, dynamic>))
          .toList();
      return PagedItems(items: items, hasMore: items.length == pageSize);
    }
    return PagedItems(items: <T>[], hasMore: false);
  }
}
