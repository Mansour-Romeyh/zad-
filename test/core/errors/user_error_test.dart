import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/api/api_exceptions.dart';
import 'package:zad/core/errors/user_error.dart';
import 'package:zad/l10n/app_localizations.dart';

void main() {
  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  test('network error maps to friendly network message', () {
    expect(userErrorMessage(en, const ApiNetworkException()), en.errorNetwork);
  });

  test('unauthenticated maps to session-expired message', () {
    expect(userErrorMessage(en, const UnauthenticatedException('x')),
        en.errorSessionExpired);
  });

  test('invalid credentials maps to invalid-credentials message, not session-expired', () {
    // A wrong/short password on login answers 401 like an expired token, but
    // it is a credential rejection — it must not read as "session expired".
    expect(userErrorMessage(en, const InvalidCredentialsException('x')),
        en.errorInvalidCredentials);
    expect(userErrorMessage(en, const InvalidCredentialsException('x')),
        isNot(en.errorSessionExpired));
  });

  test('out of stock maps to friendly out-of-stock message', () {
    expect(userErrorMessage(en, const OutOfStockException('x', [])),
        en.errorOutOfStock);
  });

  test('outside coverage maps to coverage message', () {
    expect(userErrorMessage(en, const OutsideCoverageException('x')),
        en.errorOutsideCoverage);
  });

  test('store closed maps to store-closed message', () {
    expect(userErrorMessage(en, const StoreClosedException('x')),
        en.errorStoreClosed);
  });

  test('otp cooldown maps to cooldown message with seconds', () {
    expect(userErrorMessage(en, const OtpCooldownException('x', 30)),
        en.errorOtpCooldown(30));
  });

  test('otp expired maps to expired message', () {
    expect(userErrorMessage(en, const OtpExpiredException('x')),
        en.errorOtpExpired);
  });

  test('otp invalid maps to the incorrect-code message (not outside-coverage)', () {
    expect(userErrorMessage(en, const OtpInvalidException('Incorrect OTP.')),
        en.errorOtpInvalid);
  });

  test('account-not-found maps to the no-account message (not outside-coverage)', () {
    expect(userErrorMessage(en, const AccountNotFoundException('x')),
        en.errorNoAccountForPhone);
    expect(userErrorMessage(en, const AccountNotFoundException('x')),
        isNot(en.errorOutsideCoverage));
  });

  test('weak password maps to the password-too-short message', () {
    expect(userErrorMessage(en, const WeakPasswordException('x')),
        en.authPasswordTooShort);
  });

  test('forbidden maps to generic (never reveals permission internals)', () {
    final e = const ForbiddenException(
        'لا يملك المستخدم +964...@app.local حق الوصول الى المستند عبر اذن دور المستند Account');
    expect(userErrorMessage(en, e), en.errorGeneric);
    expect(userErrorMessage(en, e), isNot(contains('Account')));
  });

  test('generic ApiException never leaks the raw server string', () {
    expect(userErrorMessage(en, const ApiException('raw server traceback')),
        en.errorGeneric);
  });

  test('non-ApiException (Dart error) maps to generic', () {
    expect(userErrorMessage(en, StateError('boom')), en.errorGeneric);
  });
}
