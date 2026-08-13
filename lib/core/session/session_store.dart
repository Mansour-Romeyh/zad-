import 'package:flutter/foundation.dart';

import '../api/token_store.dart';
import '../../data/auth_repository.dart';

/// Coarse session state; pair with [SessionStore.isLoading] for the brief
/// instant while [SessionStore.restore] is reading storage.
enum SessionStatus { guest, authed }

/// App-wide auth session (PRD F1/A3), exposed via `provider` above
/// `MaterialApp`. Wraps [AuthRepository] with local persistence
/// ([TokenStore]) and notifies listeners on every state change so gated
/// screens (cart, favourites, checkout, profile) can react.
class SessionStore extends ChangeNotifier {
  SessionStore({required AuthRepository authRepository, required TokenStore tokenStore})
    : _authRepository = authRepository,
      _tokenStore = tokenStore;

  final AuthRepository _authRepository;
  final TokenStore _tokenStore;

  SessionStatus _status = SessionStatus.guest;
  bool _isLoading = false;
  String? _user;
  String? _fullName;
  String? _phone;

  SessionStatus get status => _status;
  bool get isLoading => _isLoading;
  bool get isAuthed => _status == SessionStatus.authed;
  String? get user => _user;
  String? get fullName => _fullName;
  String? get phone => _phone;

  /// Reads any previously saved session from [TokenStore] and applies it.
  /// Never throws — a storage failure (e.g. platform channel unavailable)
  /// is treated the same as "no saved session", i.e. guest.
  Future<void> restore() async {
    _setLoading(true);
    TokenCredentials? creds;
    try {
      creds = await _tokenStore.read();
    } catch (_) {
      creds = null;
    }
    if (creds != null) {
      _applyCredentials(user: creds.user, fullName: creds.fullName, phone: creds.phone);
      _status = SessionStatus.authed;
    } else {
      _status = SessionStatus.guest;
    }
    _setLoading(false);
  }

  Future<void> login({required String phone, required String password}) async {
    _setLoading(true);
    try {
      final session = await _authRepository.login(phone: phone, password: password);
      await _persist(session);
    } finally {
      _setLoading(false);
    }
  }

  /// Requests a signup OTP; returns the cooldown so the caller (RegisterPage
  /// → OtpPage) can drive the resend countdown.
  Future<OtpRequestResult> requestSignupOtp(String phone) =>
      _authRepository.requestSignupOtp(phone);

  Future<void> register({
    required String fullName,
    required String phone,
    required String password,
    required String otp,
  }) async {
    _setLoading(true);
    try {
      final session = await _authRepository.verifyAndRegister(
        fullName: fullName,
        phone: phone,
        password: password,
        otp: otp,
      );
      await _persist(session);
    } finally {
      _setLoading(false);
    }
  }

  Future<OtpRequestResult> requestResetOtp(String phone) =>
      _authRepository.requestResetOtp(phone);

  Future<void> resetPassword({
    required String phone,
    required String otp,
    required String newPassword,
  }) {
    return _authRepository.resetPassword(phone: phone, otp: otp, newPassword: newPassword);
  }

  Future<void> changePassword({required String oldPassword, required String newPassword}) {
    return _authRepository.changePassword(oldPassword: oldPassword, newPassword: newPassword);
  }

  /// Logs out with the server (best-effort — the local session is dropped
  /// even if the network call fails) and returns to guest.
  Future<void> logout() async {
    _setLoading(true);
    try {
      await _authRepository.logout();
    } catch (_) {
      // Local session still clears below; nothing else to do for a
      // best-effort key revocation.
    }
    await _clearLocal();
    _setLoading(false);
  }

  /// Drops straight to guest without a server round trip. Wired to
  /// [ApiClient.onUnauthenticated] in `app.dart` so a 401 from any call
  /// (an expired/revoked token) logs the whole app out immediately.
  Future<void> forceLogout() => _clearLocal();

  /// Deletes the account server-side, then drops to guest. On failure the
  /// session is kept (the caller surfaces the error) — we only clear locally
  /// once the server has accepted the deletion and revoked the token.
  Future<void> deleteAccount() async {
    _setLoading(true);
    try {
      await _authRepository.deleteAccount();
      await _clearLocal();
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _persist(AuthSession session) async {
    await _tokenStore.save(
      apiKey: session.apiKey,
      apiSecret: session.apiSecret,
      user: session.user,
      fullName: session.fullName,
      phone: session.phone,
    );
    _applyCredentials(user: session.user, fullName: session.fullName, phone: session.phone);
    _status = SessionStatus.authed;
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    await _tokenStore.clear();
    _user = null;
    _fullName = null;
    _phone = null;
    _status = SessionStatus.guest;
    notifyListeners();
  }

  void _applyCredentials({required String user, String? fullName, String? phone}) {
    _user = user;
    _fullName = fullName;
    _phone = phone;
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }
}
