import 'package:flutter_test/flutter_test.dart';
import 'package:zad/models/app_banner.dart';

void main() {
  test('fromJson parses a full payload', () {
    final banner = AppBannerModel.fromJson(
      {
        'image': '/files/banner.png',
        'title': 'Ramadan Sale',
        'link_type': 'category',
        'link_value': 'Dairy & Breakfast',
      },
      resolveImageUrl: (p) => p == null ? null : 'http://test.local$p',
    );

    expect(banner.imageUrl, 'http://test.local/files/banner.png');
    expect(banner.title, 'Ramadan Sale');
    expect(banner.linkType, 'category');
    expect(banner.linkValue, 'Dairy & Breakfast');
  });

  test('fromJson tolerates a minimal payload', () {
    final banner = AppBannerModel.fromJson({});

    expect(banner.imageUrl, isNull);
    expect(banner.title, '');
    expect(banner.linkType, isNull);
    expect(banner.linkValue, isNull);
    expect(banner.linkItems, isEmpty);
  });

  test('fromJson parses and cleans link_items for an Items banner', () {
    final banner = AppBannerModel.fromJson({
      'title': 'Picks',
      'link_type': 'Items',
      'link_items': ['ITEM-A', '  ITEM-B  ', '', 'ITEM-C'],
    });

    expect(banner.linkItems, ['ITEM-A', 'ITEM-B', 'ITEM-C']);
  });

  test('fromJson defaults link_items to empty when missing or not a list', () {
    expect(AppBannerModel.fromJson({}).linkItems, isEmpty);
    expect(AppBannerModel.fromJson({'link_items': 'nope'}).linkItems, isEmpty);
  });
}
