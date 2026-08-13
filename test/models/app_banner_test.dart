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
  });
}
