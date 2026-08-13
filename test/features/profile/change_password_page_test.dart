import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/features/profile/change_password_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

/// An authed [SessionStore] whose auth calls hit [handler] — so the test
/// controls exactly what `auth.change_password` answers.
Future<SessionStore> _authedSession(
  FakeDioHandler handler, {
  List<RequestOptions>? requests,
}) async {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  await tokenStore.save(apiKey: 'k', apiSecret: 's', user: 'jane@app.local');
  final session = SessionStore(
    authRepository: AuthRepository(
      ApiClient(
        dio: buildFakeDio(handler, capturedRequests: requests),
        tokenStore: tokenStore,
        baseUrl: 'http://test.local',
      ),
    ),
    tokenStore: tokenStore,
  );
  await session.restore();
  return session;
}

Widget _app(SessionStore session) => wrapPage(
      const ChangePasswordPage(),
      providers: [ChangeNotifierProvider<SessionStore>.value(value: session)],
    );

void main() {
  testWidgets('validates both fields as required', (tester) async {
    var calls = 0;
    final session = await _authedSession((options) {
      calls++;
      return Response(requestOptions: options, statusCode: 200, data: {'message': {'ok': true}});
    });
    await tester.pumpWidget(_app(session));

    await tester.tap(find.text('Save New Password'));
    await tester.pumpAndSettle();

    expect(find.text('This field is required'), findsNWidgets(2));
    expect(calls, 0);
  });

  testWidgets('submits {old, new} and pops with a success SnackBar', (tester) async {
    final requests = <RequestOptions>[];
    final session = await _authedSession(
      (options) => Response(
        requestOptions: options,
        statusCode: 200,
        data: {'message': {'ok': true}},
      ),
      requests: requests,
    );
    await tester.pumpWidget(
      wrapPage(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const ChangePasswordPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
        providers: [ChangeNotifierProvider<SessionStore>.value(value: session)],
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('oldPasswordField')), 'old-secret');
    await tester.enterText(find.byKey(const Key('newPasswordField')), 'new-secret');
    await tester.tap(find.text('Save New Password'));
    await tester.pumpAndSettle();

    final call = requests.single;
    expect(call.path, '/api/method/grocery.api.auth.change_password');
    expect(call.data, {'old': 'old-secret', 'new': 'new-secret'});
    expect(find.byType(ChangePasswordPage), findsNothing); // popped
    expect(find.text('Password changed'), findsOneWidget); // SnackBar
  });

  testWidgets('wrong old password (401) surfaces the localized error — and does NOT log the app out', (tester) async {
    final session = await _authedSession(
      (options) => Response(
        requestOptions: options,
        statusCode: 401,
        data: {'message': 'Incorrect User or Password'},
      ),
    );
    await tester.pumpWidget(_app(session));

    await tester.enterText(find.byKey(const Key('oldPasswordField')), 'wrong');
    await tester.enterText(find.byKey(const Key('newPasswordField')), 'new-secret');
    await tester.tap(find.text('Save New Password'));
    await tester.pumpAndSettle();

    expect(find.text('Current password is incorrect'), findsOneWidget);
    expect(find.byType(ChangePasswordPage), findsOneWidget); // still here
    expect(session.isAuthed, isTrue,
        reason: 'a wrong-old-password 401 must not force-log the app out');
  });

  testWidgets('other server errors surface their message inline', (tester) async {
    final session = await _authedSession(
      (options) => Response(
        requestOptions: options,
        statusCode: 500,
        data: {'message': 'Password too weak'},
      ),
    );
    await tester.pumpWidget(_app(session));

    await tester.enterText(find.byKey(const Key('oldPasswordField')), 'old-secret');
    await tester.enterText(find.byKey(const Key('newPasswordField')), 'x');
    await tester.tap(find.text('Save New Password'));
    await tester.pumpAndSettle();

    // A 500 with a raw server message maps to the generic ApiException ->
    // errorGeneric via userErrorMessage (lib/core/errors/user_error.dart);
    // the raw 'Password too weak' string is never shown to the user.
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
  });
}
