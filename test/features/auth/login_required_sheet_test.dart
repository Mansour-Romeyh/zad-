import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zad/core/api/api_client.dart';
import 'package:zad/core/api/token_store.dart';
import 'package:zad/core/session/session_store.dart';
import 'package:zad/data/auth_repository.dart';
import 'package:zad/features/auth/login_required_sheet.dart';

import '../../helpers.dart';
import '../../support/fake_secure_storage.dart';

SessionStore _sessionWith(TokenStore tokenStore) => SessionStore(
      authRepository: AuthRepository(
        ApiClient(dio: Dio(), tokenStore: tokenStore, baseUrl: 'http://test.local'),
      ),
      tokenStore: tokenStore,
    );

class _GatedButtonHarness extends StatefulWidget {
  const _GatedButtonHarness();

  @override
  State<_GatedButtonHarness> createState() => _GatedButtonHarnessState();
}

class _GatedButtonHarnessState extends State<_GatedButtonHarness> {
  bool proceeded = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            if (await ensureLoggedIn(context)) {
              setState(() => proceeded = true);
            }
          },
          child: const Text('Add to cart'),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('guest tap shows the login-required sheet', (tester) async {
    final store = _sessionWith(TokenStore(storage: FakeSecureStorage()));
    await store.restore();
    await tester.pumpWidget(
      wrapPage(
        const _GatedButtonHarness(),
        providers: [ChangeNotifierProvider<SessionStore>.value(value: store)],
      ),
    );

    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();

    expect(find.text('Log in to continue'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
  });

  testWidgets('authed tap proceeds without showing the sheet', (tester) async {
    final tokenStore = TokenStore(storage: FakeSecureStorage());
    await tokenStore.save(apiKey: 'k', apiSecret: 's', user: 'u@app.local');
    final store = _sessionWith(tokenStore);
    await store.restore();
    await tester.pumpWidget(
      wrapPage(
        const _GatedButtonHarness(),
        providers: [ChangeNotifierProvider<SessionStore>.value(value: store)],
      ),
    );

    await tester.tap(find.text('Add to cart'));
    await tester.pump();

    expect(find.text('Log in to continue'), findsNothing);
    final state = tester.state<_GatedButtonHarnessState>(find.byType(_GatedButtonHarness));
    expect(state.proceeded, isTrue);
  });

  testWidgets('sheet login button navigates to /auth/login', (tester) async {
    final store = _sessionWith(TokenStore(storage: FakeSecureStorage()));
    await store.restore();
    await tester.pumpWidget(
      wrapPage(
        const _GatedButtonHarness(),
        providers: [ChangeNotifierProvider<SessionStore>.value(value: store)],
        routes: {
          '/auth/login': (_) => const Scaffold(body: Text('LOGIN_MARKER')),
        },
      ),
    );

    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN_MARKER'), findsOneWidget);
  });
}
