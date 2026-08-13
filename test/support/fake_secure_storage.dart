import 'package:zad/core/api/token_store.dart';

/// In-memory [SecureStorage] double so tests never touch the platform
/// secure-storage channel.
class FakeSecureStorage implements SecureStorage {
  final Map<String, String> data = {};

  /// When set, [read] throws this instead of returning a value — simulates a
  /// keystore decryption failure (flutter_secure_storage surfaces an Android
  /// Keystore/ciphertext mismatch as a `PlatformException`/
  /// `BadPaddingException`).
  Object? readError;

  @override
  Future<String?> read({required String key}) async {
    if (readError != null) throw readError!;
    return data[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    data[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    data.remove(key);
  }
}
