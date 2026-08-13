import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Injectable "an order was created" feedback (PRD checkout). Screens depend on
/// this interface only, so tests substitute a fake and never touch the audio
/// platform channel — same seam pattern as `LocationService`.
abstract class OrderFeedbackService {
  /// Plays the confirmation pip + a subtle haptic. Best-effort: never throws.
  Future<void> playOrderPlaced();
}

/// No-op implementation — the default for pushless/test builds and any context
/// where audio isn't wanted.
class NoopOrderFeedbackService implements OrderFeedbackService {
  const NoopOrderFeedbackService();

  @override
  Future<void> playOrderPlaced() async {}
}

/// Real implementation over `audioplayers` — the ONLY file importing the
/// plugin (package-freeze exception). One reusable player, configured to honour
/// the phone's silent switch (Android notification usage; iOS ambient category),
/// so a silenced phone gets the haptic only.
class AudioOrderFeedbackService implements OrderFeedbackService {
  AudioOrderFeedbackService() : _player = AudioPlayer() {
    _player.setReleaseMode(ReleaseMode.stop);
    // Fire-and-forget context config; the service is created at app boot, long
    // before checkout, so it is applied by the time the pip plays.
    _player.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.ambient,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
        android: const AudioContextAndroid(
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.notification,
          audioFocus: AndroidAudioFocus.none,
        ),
      ),
    );
  }

  final AudioPlayer _player;

  @override
  Future<void> playOrderPlaced() async {
    // Best-effort: a sound/haptic failure must never affect the order
    // confirmation or navigation. Haptic fires even on vibrate/silent.
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    try {
      await _player.stop();
      await _player.play(AssetSource('audio/order_placed.wav'));
    } catch (_) {}
  }
}
