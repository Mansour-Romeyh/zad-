import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_exceptions.dart';
import '../widgets/zad_snack.dart';

/// Maps any thrown [error] to a friendly, localized, app-owned message.
///
/// Selection is by exception *type*. Raw server strings
/// ([ApiException.message]) are NEVER returned: `ForbiddenException`, the
/// generic `ApiException`, and any non-`ApiException` (Dart errors,
/// `e.toString()`) all fall through to [AppLocalizations.errorGeneric], so no
/// backend or framework internals ever reach the user. The specific subtypes
/// are checked before the generic fall-through because they all extend
/// `ApiException`. See
/// docs/superpowers/specs/2026-07-21-friendly-errors-and-cart-permission-design.md.
String userErrorMessage(AppLocalizations l10n, Object error) {
  if (error is ApiNetworkException) return l10n.errorNetwork;
  // Checked before UnauthenticatedException — it is a subtype (a credential
  // rejection), and must read as "incorrect password", not "session expired".
  if (error is InvalidCredentialsException) return l10n.errorInvalidCredentials;
  if (error is UnauthenticatedException) return l10n.errorSessionExpired;
  if (error is OutOfStockException) return l10n.errorOutOfStock;
  if (error is OutsideCoverageException) return l10n.errorOutsideCoverage;
  if (error is StoreClosedException) return l10n.errorStoreClosed;
  if (error is OtpCooldownException) {
    return l10n.errorOtpCooldown(error.cooldownSec);
  }
  if (error is OtpExpiredException) return l10n.errorOtpExpired;
  if (error is OtpInvalidException) return l10n.errorOtpInvalid;
  if (error is AccountNotFoundException) return l10n.errorNoAccountForPhone;
  if (error is WeakPasswordException) return l10n.authPasswordTooShort;
  if (error is PhoneAlreadyRegisteredException) {
    return l10n.errorPhoneAlreadyRegistered;
  }
  return l10n.errorGeneric;
}

/// Shows [error] as a friendly error SnackBar. Callers must guard
/// `context.mounted`.
void showErrorSnackBar(BuildContext context, Object error) {
  showZadSnack(
    context,
    userErrorMessage(AppLocalizations.of(context), error),
    variant: ZadSnackVariant.error,
  );
}
