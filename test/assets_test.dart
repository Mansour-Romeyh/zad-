import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const expectedImages = <String>[
  'assets/images/produce_spread.png',
  'assets/images/onboarding_delivery.png',
  'assets/images/cat_vegetables_fruits.png',
  'assets/images/cat_dairy_breakfast.png',
  'assets/images/cat_cold_drinks.png',
  'assets/images/cat_instant_frozen.png',
  'assets/images/cat_tea_coffee.png',
  'assets/images/cat_atta_rice_dal.png',
  'assets/images/cat_masala_oil.png',
  'assets/images/cat_chicken_meat_fish.png',
  'assets/images/product_surf_excel.png',
  'assets/images/product_toor_dal.png',
  'assets/images/product_sunflower_oil.png',
  'assets/images/banner_products.png',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all design images are bundled', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    for (final path in expectedImages) {
      expect(assets, contains(path), reason: '$path missing from bundle');
    }
  });

  test('Poppins and Cairo font families are bundled', () async {
    final fontManifest = await rootBundle.loadString('FontManifest.json');
    expect(fontManifest, contains('Poppins'));
    expect(fontManifest, contains('Cairo'));
  });
}
