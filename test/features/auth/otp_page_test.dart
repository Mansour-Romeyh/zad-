import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/features/auth/otp_page.dart';

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

Widget _app(SessionStore store, {int initialCooldownSec = 30}) => wrapPage(
      OtpPage(
        phone: '+9647701234567',
        fullName: 'Jane Doe',
        password: 'p@ssw0rd',
        initialCooldownSec: initialCooldownSec,
      ),
      providers: [ChangeNotifierProvider<SessionStore>.value(value: store)],
      routes: {
        '/home': (_) => const Scaffold(body: Text('HOME_MARKER')),
      },
    );

void main() {
  testWidgets('shows the phone number in the instructions', (tester) async {
    await tester.pumpWidget(_app(_sessionWith(Dio())));
    expect(find.textContaining('+9647701234567'), findsOneWidget);
  });

  testWidgets('resend is disabled with a countdown until the cooldown elapses', (tester) async {
    await tester.pumpWidget(_app(_sessionWith(Dio()), initialCooldownSec: 3));

    expect(find.text('Resend in 3s'), findsOneWidget);
    final resendButtonFinder = find.widgetWithText(TextButton, 'Resend in 3s');
    expect(tester.widget<TextButton>(resendButtonFinder).onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend in 2s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend in 1s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Resend Code'), findsOneWidget);
    final enabledFinder = find.widgetWithText(TextButton, 'Resend Code');
    expect(tester.widget<TextButton>(enabledFinder).onPressed, isNotNull);
  });

  testWidgets('tapping resend after cooldown requests a new OTP and restarts the countdown',
      (tester) async {
    var callCount = 0;
    final dio = buildFakeDio((options) {
      callCount++;
      return _envelope(options, {'sent': true, 'cooldown_sec': 45});
    });
    await tester.pumpWidget(_app(_sessionWith(dio), initialCooldownSec: 0));

    expect(find.text('Resend Code'), findsOneWidget);
    await tester.tap(find.text('Resend Code'));
    await tester.pumpAndSettle();

    expect(callCount, 1);
    expect(find.text('Resend in 45s'), findsOneWidget);
  });

  testWidgets('423 on resend re-arms the countdown with the server cooldown', (tester) async {
    final dio = buildFakeDio(
      (options) =>
          _error(options, 423, {'message': 'Please wait before retrying', 'cooldown_sec': 37}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio), initialCooldownSec: 0));

    expect(find.text('Resend Code'), findsOneWidget);
    await tester.tap(find.text('Resend Code'));
    await tester.pumpAndSettle();

    // The error is surfaced AND the button is disabled again, counting down
    // from the server-provided cooldown_sec — not immediately re-tappable.
    // 423 maps to OtpCooldownException -> errorOtpCooldown(37) via
    // userErrorMessage (lib/core/errors/user_error.dart); the raw
    // 'Please wait before retrying' string is never shown to the user.
    expect(find.text('Please wait 37s before requesting a new code.'), findsOneWidget);
    expect(find.text('Resend in 37s'), findsOneWidget);
    final resendButtonFinder = find.widgetWithText(TextButton, 'Resend in 37s');
    expect(tester.widget<TextButton>(resendButtonFinder).onPressed, isNull);

    // Countdown actually ticks down from the re-armed value.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Resend in 36s'), findsOneWidget);

    // Drain the rest of the countdown so no timer outlives the test.
    await tester.pump(const Duration(seconds: 36));
    expect(find.text('Resend Code'), findsOneWidget);
  });

  testWidgets('correct code submits and navigates home', (tester) async {
    final dio = buildFakeDio(
      (options) => _envelope(options, {
        'api_key': 'key',
        'api_secret': 'secret',
        'user': 'jane@app.local',
      }),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pumpAndSettle();

    expect(find.text('HOME_MARKER'), findsOneWidget);
  });

  testWidgets('expired OTP shows an error banner', (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 410, {'message': 'Code expired'}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.pumpAndSettle();

    // 410 maps to OtpExpiredException -> errorOtpExpired via
    // userErrorMessage (lib/core/errors/user_error.dart).
    expect(find.text('Your code has expired. Please request a new one.'), findsOneWidget);
    expect(find.text('HOME_MARKER'), findsNothing);
  });
}
