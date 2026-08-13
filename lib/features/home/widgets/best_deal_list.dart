import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../models/product.dart';
import 'product_card.dart';

class BestDealList extends StatelessWidget {
  const BestDealList({required this.products, super.key});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 244 + kProductCardControlHeight + kProductCardControlGap,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: ZadSpacing.screenPadding,
        ),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) =>
            SizedBox(width: 160, child: ProductCard(product: products[index])),
      ),
    );
  }
}
