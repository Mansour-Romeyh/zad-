/// Typed exceptions thrown by [ApiClient] for non-2xx responses and
/// network failures. Mapping is driven by HTTP status code per the
/// Zad backend-integration global constraints.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Connection-level failure: no network, timeout, DNS failure, etc.
/// There is no server response to read a message from.
class ApiNetworkException extends ApiException {
  const ApiNetworkException([super.message = 'Network error']);
}

/// HTTP 401 — the request requires a logged-in user.
class UnauthenticatedException extends ApiException {
  const UnauthenticatedException(super.message);
}

/// HTTP 401 from a `grocery.api.auth.*` credential check (wrong password on
/// login, wrong OLD password on change_password — frappe's `check_password`
/// raises `AuthenticationError`). A *rejection of entered credentials*, not a
/// dead session — so the UI shows "incorrect password" rather than "your
/// session has expired". Subtypes [UnauthenticatedException] so callers that
/// catch that type (e.g. ChangePasswordPage) and the guest-401 tests still
/// hold; [userErrorMessage] checks this subtype first.
class InvalidCredentialsException extends UnauthenticatedException {
  const InvalidCredentialsException(super.message);
}

/// HTTP 403 — the logged-in user's role does not permit this action.
class ForbiddenException extends ApiException {
  const ForbiddenException(super.message);
}

/// HTTP 409 — one or more cart/order items are out of stock.
class OutOfStockException extends ApiException {
  const OutOfStockException(super.message, this.items);

  /// Raw `items` payload the server reported as out of stock.
  final List<dynamic> items;
}

/// HTTP 417 with `exc_type == 'OutsideCoverageError'` — the resolved
/// address/coordinates fall outside delivery coverage. 417 is Frappe's default
/// for *any* validation error, so the exception type in the body (not the
/// status alone) is what identifies this one.
class OutsideCoverageException extends ApiException {
  const OutsideCoverageException(super.message);
}

/// HTTP 417 with `exc_type == 'OtpInvalidError'` — the submitted signup/login
/// OTP was incorrect. Shares 417 with generic validation errors, so it is
/// distinguished by the response's `exc_type` (see [ApiClient]).
class OtpInvalidException extends ApiException {
  const OtpInvalidException(super.message);
}

/// HTTP 417 with `exc_type == 'AccountNotFoundError'` — no enabled account
/// exists for the phone entered on the password-reset screen. Shares 417 with
/// generic validation errors, so it is distinguished by the response's
/// `exc_type` (see [ApiClient]).
class AccountNotFoundException extends ApiException {
  const AccountNotFoundException(super.message);
}

/// HTTP 400 — the chosen password fails the backend policy (too short).
/// Backend `WeakPasswordError`; surfaces on the register/reset screens.
class WeakPasswordException extends ApiException {
  const WeakPasswordException(super.message);
}

/// HTTP 425 — checkout attempted outside the store's working hours
/// (backend `StoreClosedError`).
class StoreClosedException extends ApiException {
  const StoreClosedException(super.message);
}

/// HTTP 423 — an OTP was requested again before the cooldown elapsed.
class OtpCooldownException extends ApiException {
  const OtpCooldownException(super.message, this.cooldownSec);

  final int cooldownSec;
}

/// HTTP 410 — the OTP has expired and must be re-requested.
class OtpExpiredException extends ApiException {
  const OtpExpiredException(super.message);
}

/// HTTP 422 — signup attempted with a phone number that already has an
/// account (backend `PhoneAlreadyRegisteredError`). Rejected up front at
/// `request_signup_otp`, so it surfaces on the register screen before OTP.
class PhoneAlreadyRegisteredException extends ApiException {
  const PhoneAlreadyRegisteredException(super.message);
}
