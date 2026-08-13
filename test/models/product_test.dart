import 'package:flutter_test/flutter_test.dart';
import 'package:zad/models/product.dart';

void main() {
  group('Product.fromJson', () {
    test('parses a full ItemCard payload', () {
      final product = Product.fromJson(
        {
          'item_code': 'ITEM-001',
          'item_name': 'Fresh Tomatoes',
          'image': '/files/tomatoes.png',
          'price_per_uom': 2.5,
          'uom': 'Kg',
          'sold_by_weight': true,
          'weight_step_g': 500,
          'min_g': 250,
          'max_g': 5000,
          'available_qty': 120.0,
          'in_stock': true,
          'is_favourite': true,
        },
        resolveImageUrl: (p) => p == null ? null : 'http://test.local$p',
      );

      expect(product.itemCode, 'ITEM-001');
      expect(product.nameEn, 'Fresh Tomatoes');
      expect(product.nameAr, 'Fresh Tomatoes');
      expect(product.nameFor('en'), 'Fresh Tomatoes');
      expect(product.nameFor('ar'), 'Fresh Tomatoes');
      expect(product.imageUrl, 'http://test.local/files/tomatoes.png');
      expect(product.pricePerUom, 2.5);
      expect(product.price, 2.5);
      expect(product.uom, 'Kg');
      expect(product.soldByWeight, isTrue);
      expect(product.weightStepG, 500);
      expect(product.minG, 250);
      expect(product.maxG, 5000);
      expect(product.availableQty, 120.0);
      expect(product.inStock, isTrue);
      expect(product.isFavourite, isTrue);
      expect(product.description, isNull);
    });

    test('parses the get_item description field when present', () {
      final product = Product.fromJson({
        'item_code': 'ITEM-010',
        'item_name': 'Fresh Tomatoes',
        'description': 'Locally grown, hand-picked daily.',
      });

      expect(product.description, 'Locally grown, hand-picked daily.');
    });

    test('parses a minimal payload with nulls tolerated', () {
      final product = Product.fromJson({
        'item_code': 'ITEM-002',
        'item_name': 'Basic Item',
      });

      expect(product.itemCode, 'ITEM-002');
      expect(product.nameEn, 'Basic Item');
      expect(product.imageUrl, isNull);
      expect(product.pricePerUom, isNull);
      expect(product.soldByWeight, isFalse);
      expect(product.weightStepG, isNull);
      expect(product.minG, isNull);
      expect(product.maxG, isNull);
      expect(product.availableQty, isNull);
      // in_stock defaults true when absent so items aren't hidden by mistake.
      expect(product.inStock, isTrue);
      expect(product.isFavourite, isNull);
    });

    test('treats numeric 0/1 booleans defensively', () {
      final product = Product.fromJson({
        'item_code': 'ITEM-003',
        'item_name': 'Numeric Bools',
        'sold_by_weight': 1,
        'in_stock': 0,
        'is_favourite': 0,
      });

      expect(product.soldByWeight, isTrue);
      expect(product.inStock, isFalse);
      expect(product.isFavourite, isFalse);
    });
  });

  test('old mock-style const construction still compiles and works', () {
    const product = Product(
      id: 'surf_excel',
      nameEn: 'Surf Excel',
      nameAr: 'سيرف اكسل',
      unitEn: '500 ml',
      unitAr: '500 مل',
      price: 12,
      oldPrice: 14,
      imagePath: 'assets/images/product_surf_excel.png',
    );

    expect(product.nameFor('en'), 'Surf Excel');
    expect(product.oldPrice, 14);
    expect(product.itemCode, isNull);
    expect(product.inStock, isTrue);
  });
}
