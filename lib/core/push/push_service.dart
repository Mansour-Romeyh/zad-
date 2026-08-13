/// Seam over the push-notification platform (Firebase Cloud Messaging in
/// production). Kept minimal so [PushRegistrar]-style consumers and tests
/// never touch the plugin directly.
abstract class PushService {
  /// Asks the OS for notification permission (Android 13+ runtime prompt,
  /// iOS alert). Returns whether it was granted. A denial does NOT
  /// invalidate the device token — data pushes still arrive silently — so
  /// callers register the token regardless.
  Future<bool> requestPermission();

  /// The current FCM device token, or null when unavailable (Firebase not
  /// configured on this build, or the platform refused one).
  Future<String?> getToken();

  /// Fires whenever FCM rotates the device token; each event is the new
  /// token, which must be re-registered with the backend.
  Stream<String> get onTokenRefresh;
}

/// The no-push build: token-less and silent. Used whenever Firebase isn't
/// configured (no `google-services.json`) so the rest of the app never has
/// to know push exists.
class NoopPushService implements PushService {
  const NoopPushService();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
}
