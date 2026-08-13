import 'package:flutter_test/flutter_test.dart';
import 'package:zad/models/paged_items.dart';

String _name(Map<String, dynamic> json) => json['item_name'] as String;

void main() {
  group('PagedItems.fromJson', () {
    test('parses the real backend envelope {items, page, has_more}', () {
      final paged = PagedItems.fromJson(
        {
          'items': [
            {'item_name': 'Milk'},
            {'item_name': 'Rice'},
          ],
          'page': 3,
          'has_more': true,
        },
        itemFromJson: _name,
        pageSize: 20,
      );

      expect(paged.items, ['Milk', 'Rice']);
      expect(paged.page, 3);
      expect(paged.hasMore, isTrue);
    });

    test('missing has_more defaults to false', () {
      final paged = PagedItems.fromJson(
        {
          'items': [
            {'item_name': 'Milk'},
          ],
        },
        itemFromJson: _name,
        pageSize: 20,
      );

      expect(paged.hasMore, isFalse);
      expect(paged.page, 1);
    });

    test('tolerates numeric has_more and string page defensively', () {
      final paged = PagedItems.fromJson(
        {'items': <dynamic>[], 'page': '2', 'has_more': 1},
        itemFromJson: _name,
        pageSize: 20,
      );

      expect(paged.page, 2);
      expect(paged.hasMore, isTrue);
    });

    test(
      'defensive fallback: bare list becomes items with full-page has_more heuristic',
      () {
        final full = PagedItems.fromJson(
          List.generate(2, (i) => {'item_name': 'Item $i'}),
          itemFromJson: _name,
          pageSize: 2,
        );
        expect(full.items, hasLength(2));
        expect(full.hasMore, isTrue); // length == pageSize

        final short = PagedItems.fromJson(
          [
            {'item_name': 'Only'},
          ],
          itemFromJson: _name,
          pageSize: 2,
        );
        expect(short.items, ['Only']);
        expect(short.hasMore, isFalse);
      },
    );

    test('unexpected payload shapes yield an empty last page', () {
      final paged = PagedItems.fromJson(
        'garbage',
        itemFromJson: _name,
        pageSize: 20,
      );
      expect(paged.items, isEmpty);
      expect(paged.hasMore, isFalse);

      final noItems = PagedItems.fromJson(
        {'page': 1},
        itemFromJson: _name,
        pageSize: 20,
      );
      expect(noItems.items, isEmpty);
      expect(noItems.hasMore, isFalse);
    });
  });
}
