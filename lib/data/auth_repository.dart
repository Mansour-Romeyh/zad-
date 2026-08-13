import '../core/api/api_client.dart';
import '../core/json_utils.dart';

/// Result of `request_signup_otp`/`request_reset_otp` (PRD F1):
/// `{sent, cooldown_sec}`. `cooldown_sec` drives the resend-cooldown
/// countdown; it defaults to 0 when the backend omits it.
class OtpRequestResult {
  const OtpRequestResult({required this.sent, this.cooldownSec = 0});

  final bool sent;
  final int cooldownSec;
}

/// Session credentials returned by `verify_and_register`/`login` (PRD F1).
/// [fullName]/[phone] are read defensively from the response `profile` map
/// when present, otherwise fall back to whatever the caller already knows
/// (the values it just sent in the request).
class AuthSession {
  const AuthSession({
    required this.apiKey,
    required this.apiSecret,
    required this.user,
    this.fullName,
    this.phone,
  });

  final String apiKey;
  final String apiSecret;
  final String user;
  final String? fullName;
  final String? phone;
}

/// Thin, typed wrapper over `grocery.api.auth.*` (PRD F1). Guest-accessible
/// except `change_password`/`logout`, which require a session — [ApiClient]
/// attaches the `Authorization` header automatically whenever one is saved.
class AuthRepository {
  AuthRepository(this._client);

  final ApiClient _client;

  Future<OtpRequestResult> requestSignupOtp(String phone) async {
    final data = await _client.post(
      'grocery.api.auth.request_signup_otp',
      data: {'phone': phone},
    );
    return _otpResultFromJson(data);
  }

  Future<AuthSession> verifyAndRegister({
    required String fullName,
    required String phone,
    required String password,
    required String otp,
  }) async {
    final data = await _client.post(
      'grocery.api.auth.verify_and_register',
      data: {
        'full_name': fullName,
        'phone': phone,
        'password': password,
        'otp': otp,
      },
    );
    return _sessionFromJson(data, fallbackFullName: fullName, fallbackPhone: phone);
  }

  Future<AuthSession> login({required String phone, required String password}) async {
    final data = await _client.post(
      'grocery.api.auth.login',
      data: {'phone': phone, 'password': password},
    );
    return _sessionFromJson(data, fallbackPhone: phone);
  }

  Future<OtpRequestResult> requestResetOtp(String phone) async {
    final data = await _client.post(
      'grocery.api.auth.request_reset_otp',
      data: {'phone': phone},
    );
    return _otpResultFromJson(data);
  }

  Future<void> resetPassword({
    required String phone,
    required String otp,
    required String newPassword,
  }) async {
    await _client.post(
      'grocery.api.auth.reset_password',
      data: {'phone': phone, 'otp': otp, 'new_password': newPassword},
    );
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _client.post(
      'grocery.api.auth.change_password',
      data: {'old': oldPassword, 'new': newPassword},
    );
  }

  Future<void> logout() async {
    await _client.post('grocery.api.auth.logout', data: const {});
  }

  Future<void> deleteAccount() async {
    await _client.post('grocery.api.auth.delete_account', data: const {});
  }

  OtpRequestResult _otpResultFromJson(dynamic data) {
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    return OtpRequestResult(
      sent: toBool(map['sent'], fallback: true),
      cooldownSec: toInt(map['cooldown_sec']) ?? 0,
    );
  }

  /// Maps a `login`/`verify_and_register` response to an [AuthSession].
  ///
  /// Per PRD F1 the two responses differ: login nests the identity fields
  /// in `profile` (`{api_key, api_secret, profile: {user, full_name, phone,
  /// customer}}`), while verify_and_register puts `user` at the top level
  /// (`{api_key, api_secret, user, customer}`). Prefer `profile` fields and
  /// fall back to top-level, so both shapes (and any hybrid) parse.
  AuthSession _sessionFromJson(
    dynamic data, {
    String? fallbackFullName,
    String? fallbackPhone,
  }) {
    final map = data is Map<String, dynamic> ? data : const <String, dynamic>{};
    final profile = map['profile'] is Map<String, dynamic>
        ? map['profile'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return AuthSession(
      apiKey: map['api_key'] as String? ?? '',
      apiSecret: map['api_secret'] as String? ?? '',
      user: (profile['user'] as String?) ?? (map['user'] as String?) ?? '',
      fullName: (profile['full_name'] as String?) ??
          (map['full_name'] as String?) ??
          fallbackFullName,
      phone: (profile['phone'] as String?) ?? (map['phone'] as String?) ?? fallbackPhone,
    );
  }
}
