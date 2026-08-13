import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'push_service.dart';

/// [PushService] over Firebase Cloud Messaging — a thin plugin boundary
/// with no logic of its own (the registration brain lives in
/// `PushRegistrar`, which is what gets tested).
class FcmPushService implements PushService {
  FcmPushService(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  Future<bool> requestPermission() async {
    try {
      final settings = await _messaging.requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (_) {
      // No Play Services / registration failure — the app runs pushless.
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}

/// Boots Firebase and returns the FCM-backed service, or the noop service
/// when this build has no Firebase config (`google-services.json` absent —
/// its Gradle plugin is applied conditionally). The app must run
/// identically either way; push is strictly additive.
Future<PushService> initPushService() async {
  try {
    await Firebase.initializeApp();
    return FcmPushService(FirebaseMessaging.instance);
  } catch (_) {
    return const NoopPushService();
  }
}
