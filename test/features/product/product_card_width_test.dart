import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/home/widgets/product_card.dart';
import 'package:zad/models/product.dart';

import '../../helpers.dart';

Product _product() => const Product(
  id: 'ITEM-1',
  itemCode: 'ITEM-1',
  nameEn: 'Toor Dal',
  nameAr: 'Toor Dal',
  unitEn: '1 kg',
  unitAr: '1 kg',
  price: 10000,
  imagePath: '',
  pricePerUom: 10000,
  inStock: true,
);

void main() {
  testWidgets('ProductCard fills the (loose) width it is offered', (
    tester,
  ) async {
    // A *loose* constraint wider than the old fixed 160: an adaptive card
    // fills 200, whereas the old fixed-160 card would render at 160. (A tight
    // SizedBox would clamp either card to the same size and prove nothing.)
    await tester.pumpWidget(
      wrapPage(
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: ProductCard(product: _product()),
          ),
        ),
        providers: homeTestProviders(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ProductCard)).width, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in a narrow cell shows the price and a compact + add button', (
    tester,
  ) async {
    // ~ a 2-column category-browser cell on a phone. The add control must be a
    // compact "+" icon, not the wide "Add" text button that squeezes the price
    // out of the narrow row.
    await tester.pumpWidget(
      wrapPage(
        Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 124,
            height: 320,
            child: ProductCard(product: _product()),
          ),
        ),
        providers: homeTestProviders(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull); // nothing overflows the cell
    expect(find.byIcon(Icons.add), findsOneWidget); // compact + button
    expect(find.text('Add'), findsNothing); // the wide text button is gone
    expect(find.text('IQD 10,000'), findsOneWidget); // price is rendered
  });
}
