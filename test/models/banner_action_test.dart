import 'package:flutter_test/flutter_test.dart';
import 'package:zad/models/app_banner.dart';
import 'package:zad/models/banner_action.dart';

AppBannerModel _banner(String? type, String? value) =>
    AppBannerModel(title: 'T', linkType: type, linkValue: value);

void main() {
  test('Item type resolves to BannerProduct with the item code', () {
    final action = resolveBannerAction(_banner('Item', 'ITEM-1'));
    expect(action, isA<BannerProduct>());
    expect((action as BannerProduct).itemCode, 'ITEM-1');
  });

  test('Item Group type resolves to BannerItemGroup with the group id', () {
    final action = resolveBannerAction(_banner('Item Group', 'Products'));
    expect(action, isA<BannerItemGroup>());
    expect((action as BannerItemGroup).groupId, 'Products');
  });

  test('URL type resolves to BannerUrl with the url', () {
    final action = resolveBannerAction(_banner('URL', 'https://zad.example'));
    expect(action, isA<BannerUrl>());
    expect((action as BannerUrl).url, 'https://zad.example');
  });

  test('None type resolves to BannerNone', () {
    expect(resolveBannerAction(_banner('None', 'ignored')), isA<BannerNone>());
  });

  test('null type resolves to BannerNone', () {
    expect(resolveBannerAction(_banner(null, 'ITEM-1')), isA<BannerNone>());
  });

  test('a typed banner with a blank value resolves to BannerNone', () {
    expect(resolveBannerAction(_banner('Item', '   ')), isA<BannerNone>());
    expect(resolveBannerAction(_banner('URL', null)), isA<BannerNone>());
  });

  test('value is trimmed before use', () {
    final action = resolveBannerAction(_banner('Item', '  ITEM-9 '));
    expect((action as BannerProduct).itemCode, 'ITEM-9');
  });
}
