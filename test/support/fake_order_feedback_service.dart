import 'package:zad/core/audio/order_feedback_service.dart';

/// In-memory [OrderFeedbackService] for widget tests — no audioplayers, no
/// platform channel. Records how many times the pip was requested; optionally
/// throws to prove the caller tolerates a feedback failure.
class FakeOrderFeedbackService implements OrderFeedbackService {
  FakeOrderFeedbackService({this.throwOnPlay = false});

  final bool throwOnPlay;
  int playOrderPlacedCount = 0;

  @override
  Future<void> playOrderPlaced() async {
    playOrderPlacedCount++;
    if (throwOnPlay) throw Exception('feedback failure (test)');
  }
}
