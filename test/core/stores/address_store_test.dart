import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/core/stores/address_store.dart';
import 'package:zad/data/address_repository.dart';
import 'package:zad/data/auth_repository.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

Map<String, dynamic> _row(String name, {String label = 'Home', int isDefault = 0}) => {
      'name': name,
      'label': label,
      'address_line': 'Street $name',
      'city': 'Baghdad',
      'lat': 33.31,
      'lng': 44.37,
      'is_default': isDefault,
    };

/// A guest [SessionStore] whose `login()` succeeds against a fake dio, for
/// tests that need a real guest→authed transition to fire the listener.
SessionStore _guestSessionWithFakeLogin() {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  final dio = buildFakeDio(
    (options) => _envelope(options, {
      'api_key': 'key789',
      'api_secret': 'secretabc',
      'profile': {'user': 'jane@app.local', 'full_name': 'Jane Doe'},
    }),
  );
  return SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: dio, tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
}

Future<SessionStore> _authedSession() async {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  await tokenStore.save(apiKey: 'k', apiSecret: 's', user: 'jane@app.local');
  final dio = buildFakeDio((options) => _envelope(options, null));
  final store = SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: dio, tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
  await store.restore();
  return store;
}

Iterable<RequestOptions> _calls(List<RequestOptions> requests, String suffix) =>
    requests.where((r) => r.path.endsWith(suffix));

void main() {
  group('AddressStore', () {
    test('guest restore/refresh are no-ops (zero server calls)', () async {
      final requests = <RequestOptions>[];
      final session = _guestSessionWithFakeLogin();
      final store = AddressStore(
        repository: buildFakeAddressRepository(capturedRequests: requests),
        session: session,
      );

      await store.restore();
      await store.refresh();

      expect(requests, isEmpty);
      expect(store.hydrated, isFalse);
      expect(store.addresses, isEmpty);
      expect(store.shouldShowNudge, isFalse);
    });

    test('authed restore hydrates the server list, default first', () async {
      final session = await _authedSession();
      final store = AddressStore(
        repository: buildFakeAddressRepository(initialAddresses: [
          _row('ADDR-1'),
          _row('ADDR-2', label: 'Work', isDefault: 1),
        ]),
        session: session,
      );

      await store.restore();

      expect(store.hydrated, isTrue);
      expect(store.addresses, hasLength(2));
      expect(store.addresses.first.name, 'ADDR-2'); // default first
      expect(store.defaultAddress?.name, 'ADDR-2');
      expect(store.shouldShowNudge, isFalse); // has addresses
    });

    test('a failed list lands on error (never throws); a later refresh recovers', () async {
      final session = await _authedSession();
      var fail = true;
      final dio = buildFakeDio((options) {
        if (fail) {
          return Response(requestOptions: options, statusCode: 500, data: {'message': 'boom'});
        }
        return _envelope(options, [_row('ADDR-1', isDefault: 1)]);
      });
      final store = AddressStore(
        repository: AddressRepository(
          ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
        ),
        session: session,
      );

      await store.restore(); // must not throw
      expect(store.error, isA<ApiException>());
      expect(store.hydrated, isFalse);
      expect(store.busy, isFalse);

      fail = false;
      await store.refresh();
      expect(store.error, isNull);
      expect(store.hydrated, isTrue);
      expect(store.defaultAddress?.name, 'ADDR-1');
    });

    test('concurrent refreshes share a single list request', () async {
      final requests = <RequestOptions>[];
      final session = await _authedSession();
      final store = AddressStore(
        repository: buildFakeAddressRepository(capturedRequests: requests),
        session: session,
      );

      await Future.wait([store.refresh(), store.refresh(), store.refresh()]);

      expect(_calls(requests, 'address.list'), hasLength(1));
    });

    test('create() posts, re-lists, and returns the zone result; first address becomes default', () async {
      final requests = <RequestOptions>[];
      final session = await _authedSession();
      final store = AddressStore(
        repository: buildFakeAddressRepository(capturedRequests: requests),
        session: session,
      );
      await store.restore();

      final created = await store.create(
        label: 'Home',
        addressLine: 'House 12',
        city: 'Baghdad',
        lat: 33.31,
        lng: 44.37,
      );

      final createCall = _calls(requests, 'address.create').single;
      expect(createCall.data, {
        'label': 'Home',
        'address_line': 'House 12',
        'city': 'Baghdad',
        'lat': 33.31,
        'lng': 44.37,
        'is_default': 1, // the very first address defaults automatically
      });
      expect(created.zoneName, 'Central Baghdad'); // zone info surfaced
      expect(_calls(requests, 'address.list'), hasLength(2)); // restore + post-create refresh
      expect(store.addresses.single.name, created.name);
      expect(store.defaultAddress?.name, created.name);
    });

    test('create() with no captured location sends the 0 sentinel', () async {
      final requests = <RequestOptions>[];
      final session = await _authedSession();
      final store = AddressStore(
        repository: buildFakeAddressRepository(
          initialAddresses: [_row('ADDR-1', isDefault: 1)],
          capturedRequests: requests,
        ),
        session: session,
      );
      await store.restore();

      await store.create(label: 'Other', addressLine: 'Somewhere', city: 'Baghdad');

      final createCall = _calls(requests, 'address.create').single;
      expect(createCall.data['lat'], 0);
      expect(createCall.data['lng'], 0);
      expect(createCall.data['is_default'], 0); // not the first address
    });

    test('setDefault() posts then re-lists — exactly one default remains', () async {
      final requests = <RequestOptions>[];
      final session = await _authedSession();
      final store = AddressStore(
        repository: buildFakeAddressRepository(
          initialAddresses: [
            _row('ADDR-2', label: 'Work', isDefault: 1),
            _row('ADDR-1'),
          ],
          capturedRequests: requests,
        ),
        session: session,
      );
      await store.restore();
      expect(store.defaultAddress?.name, 'ADDR-2');

      await store.setDefault('ADDR-1');

      expect(_calls(requests, 'address.set_default').single.data, {'name': 'ADDR-1'});
      // Exclusivity comes from the refreshed list, not local bookkeeping.
      expect(store.addresses.where((a) => a.isDefault).single.name, 'ADDR-1');
      expect(store.addresses.first.name, 'ADDR-1'); // default sorts first
    });

    test('update() posts the changes and re-lists', () async {
      final requests = <RequestOptions>[];
      final session = await _authedSession();
      final store = AddressStore(
        repository: buildFakeAddressRepository(
          initialAddresses: [_row('ADDR-1', isDefault: 1)],
          capturedRequests: requests,
        ),
        session: session,
      );
      await store.restore();

      final updated = await store.update(
        'ADDR-1',
        label: 'Work',
        addressLine: 'New line',
        city: 'Baghdad',
      );

      final updateCall = _calls(requests, 'address.update').single;
      expect(updateCall.data['name'], 'ADDR-1');
      expect(updateCall.data['label'], 'Work');
      expect(updateCall.data.containsKey('lat'), isFalse); // omitted, not null
      expect(updated.label, 'Work');
      expect(store.addresses.single.label, 'Work');
    });

    test('delete() posts and drops the row locally', () async {
      final requests = <RequestOptions>[];
      final session = await _authedSession();
      final store = AddressStore(
        repository: buildFakeAddressRepository(
          initialAddresses: [
            _row('ADDR-2', isDefault: 1),
            _row('ADDR-1'),
          ],
          capturedRequests: requests,
        ),
        session: session,
      );
      await store.restore();

      await store.delete('ADDR-1');

      expect(_calls(requests, 'address.delete').single.data, {'name': 'ADDR-1'});
      expect(store.addresses.single.name, 'ADDR-2');
    });

    test('a failed mutation rethrows for the call site and keeps state', () async {
      final session = await _authedSession();
      final dio = buildFakeDio((options) {
        if (options.path.endsWith('address.list')) {
          return _envelope(options, [_row('ADDR-1', isDefault: 1)]);
        }
        return Response(requestOptions: options, statusCode: 500, data: {'message': 'boom'});
      });
      final store = AddressStore(
        repository: AddressRepository(
          ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
        ),
        session: session,
      );
      await store.restore();

      await expectLater(store.delete('ADDR-1'), throwsA(isA<ApiException>()));
      expect(store.addresses.single.name, 'ADDR-1'); // nothing dropped
      expect(store.error, isNull); // mutation failures never poison list state
    });

    test('login transition hydrates automatically', () async {
      final requests = <RequestOptions>[];
      final session = _guestSessionWithFakeLogin();
      final store = AddressStore(
        repository: buildFakeAddressRepository(
          initialAddresses: [_row('ADDR-1', isDefault: 1)],
          capturedRequests: requests,
        ),
        session: session,
      );
      expect(store.hydrated, isFalse);

      await session.login(phone: '+9647701234567', password: 'p@ss');
      await store.sessionSyncDone;

      expect(_calls(requests, 'address.list'), hasLength(1));
      expect(store.hydrated, isTrue);
      expect(store.defaultAddress?.name, 'ADDR-1');
    });

    test('logout clears everything and re-arms the nudge', () async {
      final session = await _authedSession();
      final store = AddressStore(
        repository: buildFakeAddressRepository(initialAddresses: [_row('ADDR-1', isDefault: 1)]),
        session: session,
      );
      await store.restore();
      store.consumeNudge();
      expect(store.addresses, isNotEmpty);

      await session.logout();

      expect(store.addresses, isEmpty);
      expect(store.hydrated, isFalse);
      expect(store.error, isNull);
      expect(store.defaultAddress, isNull);
      expect(store.shouldShowNudge, isFalse); // guest never nudges
    });

    group('shouldShowNudge', () {
      test('true exactly when authed + hydrated + zero addresses, until consumed', () async {
        final session = await _authedSession();
        final store = AddressStore(
          repository: buildFakeAddressRepository(),
          session: session,
        );
        expect(store.shouldShowNudge, isFalse); // not hydrated yet

        await store.restore();
        expect(store.shouldShowNudge, isTrue);

        store.consumeNudge();
        expect(store.shouldShowNudge, isFalse); // once per session

        await store.refresh();
        expect(store.shouldShowNudge, isFalse); // stays consumed
      });

      test('false when the user has addresses', () async {
        final session = await _authedSession();
        final store = AddressStore(
          repository: buildFakeAddressRepository(initialAddresses: [_row('ADDR-1', isDefault: 1)]),
          session: session,
        );
        await store.restore();
        expect(store.shouldShowNudge, isFalse);
      });

      test('re-login after logout gets a fresh nudge', () async {
        final requests = <RequestOptions>[];
        final session = _guestSessionWithFakeLogin();
        final store = AddressStore(
          repository: buildFakeAddressRepository(capturedRequests: requests),
          session: session,
        );

        await session.login(phone: '+9647701234567', password: 'p@ss');
        await store.sessionSyncDone;
        expect(store.shouldShowNudge, isTrue);
        store.consumeNudge();

        await session.logout();
        await session.login(phone: '+9647701234567', password: 'p@ss');
        await store.sessionSyncDone;

        expect(store.shouldShowNudge, isTrue); // logout re-armed it
      });
    });

    group('session-boundary races (review fixes on eba9af4)', () {
      test('logout invalidates the in-flight list: relogin fetches fresh and the stale snapshot is discarded', () async {
        // User A's address.list hangs → A logs out → B logs in. B's refresh
        // must NOT adopt A's hung fetch, and A's late snapshot (their home
        // address!) must never populate B's store.
        final firstListGate = Completer<void>();
        var listCalls = 0;
        final requests = <RequestOptions>[];
        final dio = Dio(BaseOptions(baseUrl: 'http://test.local'));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              requests.add(options);
              if (options.path.endsWith('address.list')) {
                listCalls += 1;
                if (listCalls == 1) {
                  await firstListGate.future;
                  handler.resolve(
                    _envelope(options, [_row('ADDR-OF-USER-A', isDefault: 1)]),
                  );
                  return;
                }
                handler.resolve(
                  _envelope(options, [_row('ADDR-OF-USER-B', isDefault: 1)]),
                );
                return;
              }
              handler.resolve(_envelope(options, null));
            },
          ),
        );
        final repo = AddressRepository(
          ApiClient(dio: dio, tokenStore: TokenStore(storage: FakeSecureStorage()), baseUrl: 'http://test.local'),
        );
        final session = _guestSessionWithFakeLogin();
        final store = AddressStore(repository: repo, session: session);

        await session.login(phone: '+9647700000001', password: 'p@ss');
        while (_calls(requests, 'address.list').isEmpty) {
          await Future<void>.delayed(Duration.zero);
        }

        await session.logout(); // A's fetch still hung
        await session.login(phone: '+9647700000002', password: 'p@ss');
        await store.sessionSyncDone; // B is FULLY hydrated first…
        expect(store.addresses.map((a) => a.name), contains('ADDR-OF-USER-B'));

        firstListGate.complete(); // …then A's straggler lands strictly last
        await Future<void>.delayed(Duration.zero); // let it settle

        expect(_calls(requests, 'address.list'), hasLength(2),
            reason: 'relogin must issue its own address.list, not adopt the hung one');
        final names = store.addresses.map((a) => a.name).toList();
        expect(names, contains('ADDR-OF-USER-B'),
            reason: "A's late snapshot must not overwrite B's applied hydrate");
        expect(names, isNot(contains('ADDR-OF-USER-A')),
            reason: "user A's stale snapshot must never populate user B's store");
      });

      test('create before hydrate never claims the default flag', () async {
        final requests = <RequestOptions>[];
        final store = AddressStore(
          repository: buildFakeAddressRepository(capturedRequests: requests),
          session: await _authedSession(),
        );
        // No restore()/refresh(): the store is authed but un-hydrated, as
        // after an offline boot — the server may hold a real default.
        expect(store.hydrated, isFalse);

        await store.create(label: 'Home', addressLine: 'X', city: 'Baghdad');

        final create = _calls(requests, 'address.create').single;
        expect((create.data as Map)['is_default'], 0,
            reason: 'an unhydrated create must not steal the server-side default');
      });

      test('a session that starts with addresses never nudges, even after delete-to-zero', () async {
        final session = _guestSessionWithFakeLogin();
        final store = AddressStore(
          repository: buildFakeAddressRepository(
            initialAddresses: [_row('ADDR-1', isDefault: 1)],
          ),
          session: session,
        );

        await session.login(phone: '+9647701234567', password: 'p@ss');
        await store.sessionSyncDone;
        expect(store.shouldShowNudge, isFalse);

        await store.delete('ADDR-1');
        expect(store.addresses, isEmpty);
        expect(store.shouldShowNudge, isFalse,
            reason: 'deleting the last address mid-session must not pop the first-login nudge');
      });
    });
  });
}
