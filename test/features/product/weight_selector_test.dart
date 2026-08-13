import 'package:flutter_test/flutter_test.dart';
import 'package:zad/features/product/weight_selector.dart';

void main() {
  group('WeightSelector', () {
    test('starts at weight_step_g grams', () {
      final selector = WeightSelector(stepG: 500, minG: 500, maxG: 5000);
      expect(selector.grams, 500);
      expect(selector.kg, 0.5);
    });

    test('J4: 500g base, "+" steps to 1.0kg then 1.5kg', () {
      final selector = WeightSelector(stepG: 500, minG: 500, maxG: 5000);

      selector.increment();
      expect(selector.grams, 1000);
      expect(selector.kg, 1.0);

      selector.increment();
      expect(selector.grams, 1500);
      expect(selector.kg, 1.5);
    });

    test('J4: price = kg_price × qty', () {
      final selector = WeightSelector(stepG: 500, minG: 500, maxG: 5000);
      selector.increment();
      selector.increment();

      expect(selector.totalPrice(2000), 3000); // 1.5kg * 2000/kg
    });

    test('clamps at max_g', () {
      final selector = WeightSelector(stepG: 500, minG: 500, maxG: 1200);

      selector.increment(); // 1000
      selector.increment(); // would be 1500, clamps to 1200
      selector.increment(); // stays clamped

      expect(selector.grams, 1200);
      expect(selector.canIncrement, isFalse);
    });

    test('clamps at min_g and cannot go below it', () {
      final selector = WeightSelector(stepG: 500, minG: 500, maxG: 5000);

      selector.decrement(); // already at floor
      expect(selector.grams, 500);
      expect(selector.canDecrement, isFalse);
    });

    test('decrement steps back down within bounds', () {
      final selector = WeightSelector(stepG: 500, minG: 500, maxG: 5000);
      selector.increment();
      selector.increment();
      expect(selector.grams, 1500);

      selector.decrement();
      expect(selector.grams, 1000);
    });

    test('falls back to stepG as the floor when min_g is absent', () {
      final selector = WeightSelector(stepG: 250);
      expect(selector.grams, 250);
      selector.decrement();
      expect(selector.grams, 250);
    });

    test('has no upper clamp when max_g is absent', () {
      final selector = WeightSelector(stepG: 500);
      for (var i = 0; i < 20; i++) {
        selector.increment();
      }
      expect(selector.grams, 500 + 20 * 500);
      expect(selector.canIncrement, isTrue);
    });
  });

  group('formatWeightGrams', () {
    test('formats sub-kilogram amounts as whole grams', () {
      expect(
        formatWeightGrams(500, gramUnit: 'g', kgUnit: 'kg'),
        '500 g',
      );
    });

    test('formats exact kilograms without a decimal', () {
      expect(
        formatWeightGrams(1000, gramUnit: 'g', kgUnit: 'kg'),
        '1 kg',
      );
    });

    test('formats fractional kilograms with one decimal', () {
      expect(
        formatWeightGrams(1500, gramUnit: 'g', kgUnit: 'kg'),
        '1.5 kg',
      );
    });

    test('uses Arabic unit labels when passed', () {
      expect(
        formatWeightGrams(500, gramUnit: 'غم', kgUnit: 'كغم'),
        '500 غم',
      );
      expect(
        formatWeightGrams(1500, gramUnit: 'غم', kgUnit: 'كغم'),
        '1.5 كغم',
      );
    });
  });
}
