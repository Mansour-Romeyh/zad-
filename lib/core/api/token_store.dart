import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal key-value secure storage contract, so [TokenStore] can be tested
/// without touching the platform secure-storage channel.
abstract class SecureStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
}

/// Default [SecureStorage] backed by the `flutter_secure_storage` plugin.
class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Keep the credential out of iCloud/iTunes encrypted backups and
            // off any restored second device — mirrors the Android
            // allowBackup="false" hardening (the default
            // `whenUnlocked` accessibility IS included in backups).
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}

/// Session credentials persisted after a successful login/registration.
class TokenCredentials {
  const TokenCredentials({
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

/// Persists and reads the Frappe token-auth credentials
/// (`api_key`/`api_secret`) plus lightweight profile fields, via
/// [flutter_secure_storage]. The backing [SecureStorage] is
/// constructor-injectable so tests never touch the platform channel.
class TokenStore {
  TokenStore({SecureStorage? storage})
    : _storage = storage ?? FlutterSecureStorageAdapter();

  final SecureStorage _storage;

  static const _kApiKey = 'api_key';
  static const _kApiSecret = 'api_secret';
  static const _kUser = 'user';
  static const _kFullName = 'full_name';
  static const _kPhone = 'phone';

  Future<void> save({
    required String apiKey,
    required String apiSecret,
    required String user,
    String? fullName,
    String? phone,
  }) async {
    await Future.wait([
      _storage.write(key: _kApiKey, value: apiKey),
      _storage.write(key: _kApiSecret, value: apiSecret),
      _storage.write(key: _kUser, value: user),
      fullName != null
          ? _storage.write(key: _kFullName, value: fullName)
          : _storage.delete(key: _kFullName),
      phone != null
          ? _storage.write(key: _kPhone, value: phone)
          : _storage.delete(key: _kPhone),
    ]);
  }

  /// Returns saved credentials, or `null` if no complete session is stored
  /// (i.e. the caller is a guest).
  ///
  /// A decryption failure never propagates. `flutter_secure_storage` throws a
  /// `PlatformException`/`BadPaddingException` when the Android Keystore key
  /// falls out of sync with the stored ciphertext (e.g. a reinstall whose
  /// auto-backup restored the encrypted prefs but not the device-bound key).
  /// Because [ApiClient] reads credentials on *every* request, letting that
  /// escape would break the whole app — guest calls included — and login. So a
  /// corrupted store is treated as "no session": the bad entries are wiped and
  /// the user simply logs in again, which self-heals the store.
  Future<TokenCredentials?> read() async {
    try {
      final apiKey = await _storage.read(key: _kApiKey);
      final apiSecret = await _storage.read(key: _kApiSecret);
      final user = await _storage.read(key: _kUser);
      if (apiKey == null || apiSecret == null || user == null) return null;

      final fullName = await _storage.read(key: _kFullName);
      final phone = await _storage.read(key: _kPhone);
      return TokenCredentials(
        apiKey: apiKey,
        apiSecret: apiSecret,
        user: user,
        fullName: fullName,
        phone: phone,
      );
    } on Object {
      // Corrupted/undecryptable store — wipe it (best effort) and fall back to
      // guest so the app keeps working and a fresh login can persist cleanly.
      try {
        await clear();
      } on Object {
        // Even delete can fail on a wedged store; nothing more we can do.
      }
      return null;
    }
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kApiKey),
      _storage.delete(key: _kApiSecret),
      _storage.delete(key: _kUser),
      _storage.delete(key: _kFullName),
      _storage.delete(key: _kPhone),
    ]);
  }
}
