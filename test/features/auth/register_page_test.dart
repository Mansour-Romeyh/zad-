import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/features/auth/register_page.dart';

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
      const RegisterPage(),
      providers: [ChangeNotifierProvider<SessionStore>.value(value: store)],
      routes: {
        '/auth/login': (_) => const Scaffold(body: Text('LOGIN_MARKER')),
      },
    );

void main() {
  testWidgets('shows full name, phone and password fields', (tester) async {
    await tester.pumpWidget(_app(_sessionWith(Dio())));
    expect(find.text('Full Name'), findsOneWidget);
    expect(find.text('+964'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Send Code'), findsOneWidget);
  });

  testWidgets('empty fields show validation errors instead of submitting', (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 400, {'message': 'should not be called'}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pump();

    expect(find.text('This field is required'), findsWidgets);
  });

  testWidgets('a non-Iraqi phone number blocks registration with a validation error',
      (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 400, {'message': 'should not be called'}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).at(0), 'Jane Doe');
    await tester.enterText(find.byType(TextFormField).at(1), '12345');
    await tester.enterText(find.byType(TextFormField).at(2), 'p@ssw0rd');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pump();

    expect(find.text('Enter a valid Iraqi phone number'), findsOneWidget);
    expect(find.text('should not be called'), findsNothing);
  });

  testWidgets('a password shorter than 8 characters blocks registration', (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 400, {'message': 'should not be called'}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).at(0), 'Jane Doe');
    await tester.enterText(find.byType(TextFormField).at(1), '7701234567');
    await tester.enterText(find.byType(TextFormField).at(2), 'short7'); // 6 chars
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pump();

    expect(find.text('Password must be at least 8 characters'), findsOneWidget);
    // Never hits the network — client-side validation stops it.
    expect(find.text('should not be called'), findsNothing);
    expect(find.text('Verify Phone Number'), findsNothing);
  });

  testWidgets('an already-registered phone (422) shows the duplicate-phone message',
      (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 422, {
        'message': 'An account with this phone number already exists.',
      }),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).at(0), 'Jane Doe');
    await tester.enterText(find.byType(TextFormField).at(1), '7701234567');
    await tester.enterText(find.byType(TextFormField).at(2), 'p@ssw0rd');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    // 422 -> PhoneAlreadyRegisteredException -> errorPhoneAlreadyRegistered.
    // The raw server string is never surfaced; the user stays on Register.
    expect(
      find.text('This phone number is already registered. Please log in instead.'),
      findsOneWidget,
    );
    expect(find.text('Verify Phone Number'), findsNothing);
  });

  testWidgets('requesting the OTP navigates to the OTP entry screen', (tester) async {
    final dio = buildFakeDio(
      (options) => _envelope(options, {'sent': true, 'cooldown_sec': 60}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).at(0), 'Jane Doe');
    await tester.enterText(find.byType(TextFormField).at(1), '7701234567');
    await tester.enterText(find.byType(TextFormField).at(2), 'p@ssw0rd');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    expect(find.text('Verify Phone Number'), findsOneWidget);
    expect(find.textContaining('+9647701234567'), findsOneWidget);
    expect(find.text('Resend in 60s'), findsOneWidget);
  });

  testWidgets('failure requesting the OTP shows an error banner', (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 423, {'message': 'Please wait before retrying', 'cooldown_sec': 20}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).at(0), 'Jane Doe');
    await tester.enterText(find.byType(TextFormField).at(1), '7701234567');
    await tester.enterText(find.byType(TextFormField).at(2), 'p@ssw0rd');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    // The raw server message ('Please wait before retrying') is no longer
    // surfaced; a 423 maps to OtpCooldownException -> errorOtpCooldown(20)
    // via userErrorMessage (lib/core/errors/user_error.dart).
    expect(find.text('Please wait 20s before requesting a new code.'), findsOneWidget);
    expect(find.text('Verify Phone Number'), findsNothing);
  });

  testWidgets('tapping the login link navigates to /auth/login', (tester) async {
    await tester.pumpWidget(_app(_sessionWith(Dio())));
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('LOGIN_MARKER'), findsOneWidget);
  });
}
