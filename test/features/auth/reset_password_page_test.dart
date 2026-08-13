import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/features/auth/reset_password_page.dart';

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
      const ResetPasswordPage(),
      providers: [ChangeNotifierProvider<SessionStore>.value(value: store)],
      routes: {
        '/auth/login': (_) => const Scaffold(body: Text('LOGIN_MARKER')),
      },
    );

void main() {
  testWidgets('starts on the phone entry step', (tester) async {
    await tester.pumpWidget(_app(_sessionWith(Dio())));
    expect(find.text('+964'), findsOneWidget);
    expect(find.text('Send Code'), findsOneWidget);
    expect(find.text('New Password'), findsNothing);
  });

  testWidgets('requesting the reset OTP advances to the OTP + new password step',
      (tester) async {
    final dio = buildFakeDio(
      (options) => _envelope(options, {'sent': true, 'cooldown_sec': 30}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).first, '7701234567');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    expect(find.text('New Password'), findsOneWidget);
    expect(find.text('Resend in 30s'), findsOneWidget);
  });

  testWidgets('failure requesting the reset OTP shows an error banner', (tester) async {
    final dio = buildFakeDio(
      (options) => _error(options, 404, {'message': 'No account for this phone'}),
    );
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).first, '7701234567');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    // A 404 with a raw server message maps to the generic ApiException ->
    // errorGeneric via userErrorMessage (lib/core/errors/user_error.dart).
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('New Password'), findsNothing);
  });

  testWidgets('submitting OTP and new password resets and returns to login', (tester) async {
    var step = 0;
    final dio = buildFakeDio((options) {
      step++;
      if (step == 1) return _envelope(options, {'sent': true, 'cooldown_sec': 30});
      return _envelope(options, {'ok': true});
    });
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).first, '7701234567');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '1234');
    await tester.enterText(find.byType(TextFormField), 'n3wp@ss');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reset Password'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN_MARKER'), findsOneWidget);
  });

  testWidgets('wrong OTP on the reset step shows an error banner', (tester) async {
    var step = 0;
    final dio = buildFakeDio((options) {
      step++;
      if (step == 1) return _envelope(options, {'sent': true, 'cooldown_sec': 30});
      return _error(options, 400, {'message': 'Invalid code'});
    });
    await tester.pumpWidget(_app(_sessionWith(dio)));

    await tester.enterText(find.byType(TextFormField).first, '7701234567');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send Code'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '0000');
    await tester.enterText(find.byType(TextFormField), 'n3wp@ss');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Reset Password'));
    await tester.pumpAndSettle();

    // A 400 with a raw server message maps to the generic ApiException ->
    // errorGeneric via userErrorMessage (lib/core/errors/user_error.dart).
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('LOGIN_MARKER'), findsNothing);
  });
}
