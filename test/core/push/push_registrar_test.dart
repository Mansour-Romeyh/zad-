import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/push/push_registrar.dart';
import 'package:zad/core/push/push_service.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/data/profile_repository.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

class FakePushService implements PushService {
  FakePushService({this.token = 'tok-1', this.permissionGranted = true});

  String? token;
  bool permissionGranted;
  int permissionRequests = 0;
  final _refresh = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionGranted;
  }

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  void emitRefresh(String newToken) {
    token = newToken;
    _refresh.add(newToken);
  }
}

Response<dynamic> _envelope(RequestOptions options, dynamic message) =>
    Response(requestOptions: options, statusCode: 200, data: {'message': message});

/// A ProfileRepository over a fake server that accepts register_device;
/// [requests] records every call so tests can assert exactly what reached
/// the backend.
ProfileRepository _profileRepo(List<RequestOptions> requests) {
  final dio = buildFakeDio(
    (options) => _envelope(options, {'ok': true}),
    capturedRequests: requests,
  );
  return ProfileRepository(
    ApiClient(
      dio: dio,
      tokenStore: TokenStore(storage: FakeSecureStorage()),
      baseUrl: 'http://test.local',
    ),
  );
}

/// A guest SessionStore whose login endpoint succeeds, for driving the
/// guest -> authed transition.
SessionStore _loginCapableSession() {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  final dio = buildFakeDio(
    (options) => _envelope(options, {
      'api_key': 'key',
      'api_secret': 'secret',
      'profile': {'user': 'jane@app.local', 'full_name': 'Jane'},
    }),
  );
  return SessionStore(
    authRepository: AuthRepository(
      ApiClient(dio: dio, tokenStore: tokenStore, baseUrl: 'http://test.local'),
    ),
    tokenStore: tokenStore,
  );
}

List<RequestOptions> _deviceCalls(List<RequestOptions> requests) => requests
    .where((r) => r.path.endsWith('profile.register_device'))
    .toList();

void main() {
  test('registers the token at start when the session is already authed', () async {
    final requests = <RequestOptions>[];
    final session = await buildAuthedSessionStore();
    final registrar = PushRegistrar(
      pushService: FakePushService(),
      profileRepository: _profileRepo(requests),
      sessionStore: session,
    );

    await registrar.start();

    final calls = _deviceCalls(requests);
    expect(calls, hasLength(1));
    expect(calls.single.data, {'token': 'tok-1'});
    registrar.dispose();
  });

  test('guest at start registers nothing, then registers on login', () async {
    final requests = <RequestOptions>[];
    final session = _loginCapableSession();
    final registrar = PushRegistrar(
      pushService: FakePushService(),
      profileRepository: _profileRepo(requests),
      sessionStore: session,
    );

    await registrar.start();
    expect(_deviceCalls(requests), isEmpty);

    await session.login(phone: '+9647701234567', password: 'pw');
    await pumpEventQueue();

    final calls = _deviceCalls(requests);
    expect(calls, hasLength(1));
    expect(calls.single.data, {'token': 'tok-1'});
    registrar.dispose();
  });

  test('a token refresh while authed re-registers the new token', () async {
    final requests = <RequestOptions>[];
    final push = FakePushService();
    final session = await buildAuthedSessionStore();
    final registrar = PushRegistrar(
      pushService: push,
      profileRepository: _profileRepo(requests),
      sessionStore: session,
    );
    await registrar.start();

    push.emitRefresh('tok-2');
    await pumpEventQueue();

    final calls = _deviceCalls(requests);
    expect(calls, hasLength(2));
    expect(calls.last.data, {'token': 'tok-2'});
    registrar.dispose();
  });

  test('a token refresh while guest registers nothing', () async {
    final requests = <RequestOptions>[];
    final push = FakePushService();
    final registrar = PushRegistrar(
      pushService: push,
      profileRepository: _profileRepo(requests),
      sessionStore: buildGuestSessionStore(),
    );
    await registrar.start();

    push.emitRefresh('tok-2');
    await pumpEventQueue();

    expect(_deviceCalls(requests), isEmpty);
    registrar.dispose();
  });

  test('a null token (Firebase unavailable) registers nothing', () async {
    final requests = <RequestOptions>[];
    final session = await buildAuthedSessionStore();
    final registrar = PushRegistrar(
      pushService: FakePushService(token: null),
      profileRepository: _profileRepo(requests),
      sessionStore: session,
    );

    await registrar.start();

    expect(_deviceCalls(requests), isEmpty);
    registrar.dispose();
  });

  test('a denied permission still registers the token (data pushes stay valid)',
      () async {
    final requests = <RequestOptions>[];
    final push = FakePushService(permissionGranted: false);
    final session = await buildAuthedSessionStore();
    final registrar = PushRegistrar(
      pushService: push,
      profileRepository: _profileRepo(requests),
      sessionStore: session,
    );

    await registrar.start();

    expect(push.permissionRequests, 1);
    expect(_deviceCalls(requests), hasLength(1));
    registrar.dispose();
  });

  test('after dispose, session and token events register nothing', () async {
    final requests = <RequestOptions>[];
    final push = FakePushService();
    final session = _loginCapableSession();
    final registrar = PushRegistrar(
      pushService: push,
      profileRepository: _profileRepo(requests),
      sessionStore: session,
    );
    await registrar.start();
    registrar.dispose();

    await session.login(phone: '+9647701234567', password: 'pw');
    push.emitRefresh('tok-9');
    await pumpEventQueue();

    expect(_deviceCalls(requests), isEmpty);
  });
}
