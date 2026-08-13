import '../core/api/api_client.dart';

/// The caller's profile (PRD F2/profile `profile.get`):
/// `{user, full_name, phone, email?, customer}`. `phone` is the account
/// identity (PRD F1) and immutable server-side.
class ProfileData {
  const ProfileData({
    required this.user,
    this.fullName,
    this.phone,
    this.email,
    this.customer,
  });

  final String user;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? customer;

  factory ProfileData.fromJson(Map<String, dynamic> json) => ProfileData(
        user: json['user'] as String? ?? '',
        fullName: json['full_name'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        customer: json['customer'] as String?,
      );
}

/// Thin, typed wrapper over `grocery.api.profile.*`. Every method requires
/// a logged-in session — the backend returns 401/403 for guests, which
/// [ApiClient] surfaces as typed exceptions.
class ProfileRepository {
  ProfileRepository(this._client);

  final ApiClient _client;

  Future<ProfileData> get() async {
    final data = await _client.get('grocery.api.profile.get');
    return ProfileData.fromJson(data as Map<String, dynamic>);
  }

  /// Updates the caller's own profile. Only the provided fields are sent —
  /// `phone` is never sent (immutable identity; the backend rejects a
  /// changed value outright). An empty-string [email] clears the stored
  /// contact email.
  Future<ProfileData> update({String? fullName, String? email}) async {
    final data = await _client.post(
      'grocery.api.profile.update',
      data: {'full_name': ?fullName, 'email': ?email},
    );
    return ProfileData.fromJson(data as Map<String, dynamic>);
  }

  /// Registers an FCM device token for the caller (`profile.register_device`,
  /// PRD Part G). Deliberately swallows every failure: push is optional
  /// infrastructure — an unconfigured backend, an expired session racing
  /// the call, or a network blip must never surface an error to the UI for
  /// a fire-and-forget registration.
  Future<void> registerDevice(String token) async {
    if (token.isEmpty) return;
    try {
      await _client.post(
        'grocery.api.profile.register_device',
        data: {'token': token},
      );
    } catch (_) {
      // Safe no-op by contract — see doc comment.
    }
  }
}
