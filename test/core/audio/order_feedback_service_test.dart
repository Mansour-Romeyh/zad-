import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/audio/order_feedback_service.dart';

import '../../support/fake_order_feedback_service.dart';

void main() {
  test('NoopOrderFeedbackService.playOrderPlaced completes and never throws',
      () async {
    await const NoopOrderFeedbackService().playOrderPlaced();
  });

  test('FakeOrderFeedbackService records calls and can simulate a failure',
      () async {
    final fake = FakeOrderFeedbackService();
    await fake.playOrderPlaced();
    await fake.playOrderPlaced();
    expect(fake.playOrderPlacedCount, 2);

    final boom = FakeOrderFeedbackService(throwOnPlay: true);
    expect(boom.playOrderPlaced(), throwsA(isA<Exception>()));
  });
}
