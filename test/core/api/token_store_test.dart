import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/token_store.dart';

import '../../support/fake_secure_storage.dart';

void main() {
  late FakeSecureStorage storage;
  late TokenStore tokenStore;

  setUp(() {
    storage = FakeSecureStorage();
    tokenStore = TokenStore(storage: storage);
  });

  test('read returns null when nothing was saved', () async {
    expect(await tokenStore.read(), isNull);
  });

  test('save then read round-trips full credentials', () async {
    await tokenStore.save(
      apiKey: 'key123',
      apiSecret: 'secret456',
      user: 'user@app.local',
      fullName: 'Jane Doe',
      phone: '+9647701234567',
    );

    final creds = await tokenStore.read();
    expect(creds, isNotNull);
    expect(creds!.apiKey, 'key123');
    expect(creds.apiSecret, 'secret456');
    expect(creds.user, 'user@app.local');
    expect(creds.fullName, 'Jane Doe');
    expect(creds.phone, '+9647701234567');
  });

  test('save without optional fields leaves them null on read', () async {
    await tokenStore.save(
      apiKey: 'key123',
      apiSecret: 'secret456',
      user: 'user@app.local',
    );

    final creds = await tokenStore.read();
    expect(creds!.fullName, isNull);
    expect(creds.phone, isNull);
  });

  test('clear removes all saved credentials', () async {
    await tokenStore.save(
      apiKey: 'key123',
      apiSecret: 'secret456',
      user: 'user@app.local',
      fullName: 'Jane Doe',
      phone: '+9647701234567',
    );

    await tokenStore.clear();

    expect(await tokenStore.read(), isNull);
    expect(storage.data, isEmpty);
  });

  test('read returns null when credentials are only partially saved', () async {
    await storage.write(key: 'api_key', value: 'key123');
    // api_secret and user missing.
    expect(await tokenStore.read(), isNull);
  });

  test('read wipes the store and returns null when decryption fails', () async {
    // The Android Keystore key going out of sync with the stored ciphertext
    // surfaces as a PlatformException/BadPaddingException. read() runs on every
    // API request (ApiClient._authOptions), so it must degrade to a guest
    // session rather than propagate — otherwise a single corrupted entry
    // breaks every call *and* login. It should also wipe the corrupted data so
    // the next login writes cleanly.
    await storage.write(key: 'api_key', value: 'stale-cipher');
    await storage.write(key: 'api_secret', value: 'stale-cipher');
    await storage.write(key: 'user', value: 'stale-cipher');
    storage.readError = Exception('BadPaddingException');

    expect(await tokenStore.read(), isNull);

    storage.readError = null;
    expect(storage.data, isEmpty, reason: 'corrupted entries should be wiped');
  });
}
