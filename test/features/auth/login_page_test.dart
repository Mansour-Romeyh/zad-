import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/features/auth/login_page.dart';

import '../../helpers.dart';
import '../../support/fake_dio.dart';
import '../../support/fake_secure_storage.dart';

Response<dynamic> _envelope(RequestOptions options, dynamic message) {
  return Response(requestOptions: options, statusCode: 200, data: {'message': message});
}

Response<dynamic> _error(RequestOptions options, int statusCode, Map<String, dynamic> data) {
  return Response(requestOptions: options, statusCode: statusCode, data: data);
}

SessionStore _sessionWith(Dio dio) {
  final tokenStore = TokenStore(storage: FakeSecureStorage());
  final client = ApiClient(dio: dio, tokenStore: tokenStore, baseUrl: 'http://test.local');
  return SessionStore(authRepository: AuthRepository(client), tokenStore: tokenStore);
}

Widget _app(SessionStore store) => wrapPage(
      const LoginPage(),
      providers: [ChangeNotifierProvider<SessionStore>.value(value: store)],
      routes: {
        '/auth/register': (_) => const Scaffold(body: Text('REGISTER_MARKER')),
        '/auth/reset': (_) => const Scaffold(body: Text('RESET_MARKER')),
        '/home': (_) => const Scaffold(body: Text('HOME_MARKER')),
      },
    );

void main() {
  testWidgets('shows phone and password fields plus the Iraqi +964 prefix', (tester) async {
    await tester.pumpWidget(_app(_sessionWith(Dio())));
    expect(find.text('+964'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
  });

  testWidgets('tapping register link navigates to /auth/register', (tester) async {
    await tester.pumpWidget(_app(_sessionWith(Dio())));
    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();
    expect(find.text('REGISTER_MARKER'), findsOneWidget);
  });

  testWidgets('tapping forgot password navigates to /auth/reset', (tester) async {
    await tester.pumpWidget(_app(_sessionWith(Dio())));
    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.text('RESET_MARKER'), findsOneWidget);
  });

  testWidgets('successful login navigates to home', (tester) async {
    final dio = buildFakeDio(
      // True PRD F1 login shape: identity fields nested in `profile`.
      (options) => _envelope(options, {
        'api_key': 'key',
        'api_secret': 'secret',
        'profile': {'user': 'jane@app.local', 'full_name': 'Jane Doe'},
      }),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).first, '7701234567');
    await tester.enterText(find.byType(TextFormField).last, 'p@ssw0rd');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.text('HOME_MARKER'), findsOneWidget);
  });

  testWidgets('failed login shows an error banner and stays on the page', (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 401, {'message': 'Invalid credentials'}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).first, '7701234567');
    await tester.enterText(find.byType(TextFormField).last, 'wrongpass');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    // The raw server message ('Invalid credentials') is no longer surfaced; a
    // 401 from grocery.api.auth.login is a credential rejection, so it maps to
    // InvalidCredentialsException -> errorInvalidCredentials (NOT the
    // session-expired message) via userErrorMessage.
    expect(find.text('Incorrect phone number or password.'), findsOneWidget);
    expect(find.text('Your session has expired. Please sign in again.'), findsNothing);
    expect(find.text('HOME_MARKER'), findsNothing);
  });

  testWidgets('empty fields show validation errors instead of submitting', (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 401, {'message': 'should not be called'}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();

    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets('a non-Iraqi phone number blocks login with a validation error', (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 401, {'message': 'should not be called'}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).first, '12345');
    await tester.enterText(find.byType(TextFormField).last, 'p@ssw0rd');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pump();

    expect(find.text('Enter a valid Iraqi phone number'), findsOneWidget);
    expect(find.text('should not be called'), findsNothing);
    expect(find.text('HOME_MARKER'), findsNothing);
  });
}
