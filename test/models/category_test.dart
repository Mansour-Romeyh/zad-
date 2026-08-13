import 'package:flutter_test/flutter_test.dart';
import 'package:zad/models/category.dart';

void main() {
  group('GroceryCategory.fromJson', () {
    test('parses a full payload', () {
      final category = GroceryCategory.fromJson(
        {
          'name': 'Vegetables & Fruits',
          'label': 'Vegetables & Fruits',
          'image': '/files/veg.png',
          'item_count': 42,
        },
        resolveImageUrl: (p) => p == null ? null : 'http://test.local$p',
      );

      expect(category.name, 'Vegetables & Fruits');
      expect(category.label, 'Vegetables & Fruits');
      expect(category.imageUrl, 'http://test.local/files/veg.png');
      expect(category.itemCount, 42);
      expect(category.nameFor('en'), 'Vegetables & Fruits');
      expect(category.id, 'Vegetables & Fruits');
    });

    test('parses a minimal payload with nulls tolerated', () {
      final category = GroceryCategory.fromJson({'name': 'Dairy'});

      expect(category.name, 'Dairy');
      expect(category.label, isNull);
      expect(category.imageUrl, isNull);
      expect(category.itemCount, isNull);
      expect(category.nameFor('en'), '');
    });
  });

  test('old mock-style const construction still compiles and works', () {
    const category = GroceryCategory(
      id: 'veg_fruits',
      nameEn: 'Vegetables & Fruits',
      nameAr: 'خضروات وفواكه',
      imagePath: 'assets/images/cat_vegetables_fruits.png',
    );

    expect(category.nameFor('ar'), 'خضروات وفواكه');
    expect(category.name, isNull);
    expect(category.itemCount, isNull);
  });
}
