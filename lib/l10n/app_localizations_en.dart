// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Zad';

  @override
  String get skip => 'Skip';

  @override
  String get onb1Title => 'Buy Groceries Easily with Us';

  @override
  String get onb1Body =>
      'Order fresh groceries from your phone and skip the queue.';

  @override
  String get onb2Title => 'Fresh Products Every Day';

  @override
  String get onb2Body =>
      'Hand-picked fruits, vegetables and daily essentials delivered fresh.';

  @override
  String get onb3Title => 'Best Deals, Fast Delivery';

  @override
  String get onb3Body =>
      'Enjoy exclusive discounts and get your order at your door in minutes.';

  @override
  String get searchHint => 'Search';

  @override
  String get shopByCategory => 'Shop By Category';

  @override
  String get seeAll => 'See All';

  @override
  String get sortBy => 'Sort By';

  @override
  String get sortDefault => 'Default';

  @override
  String get sortPriceLowToHigh => 'Price: Low to High';

  @override
  String get sortPriceHighToLow => 'Price: High to Low';

  @override
  String get bestDeal => 'Best Deal';

  @override
  String get bannerHeadline =>
      'World Food Festival, Bring the world to your Kitchen!';

  @override
  String get shopNow => 'Shop Now';

  @override
  String get add => 'Add';

  @override
  String get addedToBasket => 'Added to basket';

  @override
  String get increaseQuantity => 'Increase quantity';

  @override
  String get decreaseQuantity => 'Decrease quantity';

  @override
  String get homeLabel => 'Home';

  @override
  String get navHome => 'Home';

  @override
  String get navFavorites => 'Favorites';

  @override
  String get navCart => 'Cart';

  @override
  String get navProfile => 'Profile';

  @override
  String get addToFavorites => 'Add to favorites';

  @override
  String get next => 'Next';

  @override
  String get authLoginTitle => 'Login';

  @override
  String get authPhoneLabel => 'Phone Number';

  @override
  String get authPhoneHint => '7XX XXX XXXX';

  @override
  String get authPhoneInvalid => 'Enter a valid Iraqi phone number';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authShowPassword => 'Show password';

  @override
  String get authHidePassword => 'Hide password';

  @override
  String get authLoginButton => 'Login';

  @override
  String get authNoAccount => 'Don\'t have an account?';

  @override
  String get authRegisterLink => 'Register';

  @override
  String get authForgotPassword => 'Forgot Password?';

  @override
  String get authRegisterTitle => 'Create Account';

  @override
  String get authFullNameLabel => 'Full Name';

  @override
  String get authSendOtpButton => 'Send Code';

  @override
  String get authAlreadyHaveAccount => 'Already have an account?';

  @override
  String get authLoginLink => 'Login';

  @override
  String get authOtpTitle => 'Verify Phone Number';

  @override
  String authOtpInstructions(String phone) {
    return 'Enter the 4-digit code sent to $phone';
  }

  @override
  String get authOtpHint => '4-digit code';

  @override
  String get authVerifyButton => 'Verify';

  @override
  String get authResendCode => 'Resend Code';

  @override
  String authResendIn(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get authResetTitle => 'Reset Password';

  @override
  String get authNewPasswordLabel => 'New Password';

  @override
  String get authResetSubmitButton => 'Reset Password';

  @override
  String get authResetSuccess => 'Password reset. Please log in.';

  @override
  String get authFieldRequired => 'This field is required';

  @override
  String get authPasswordTooShort => 'Password must be at least 8 characters';

  @override
  String get authLoginRequiredTitle => 'Log in to continue';

  @override
  String get profileGuestTitle => 'Log in to view your profile';

  @override
  String profileGreeting(String name) {
    return 'Hello, $name';
  }

  @override
  String get profileLogoutButton => 'Log out';

  @override
  String get addressPlaceholder => 'Baghdad';

  @override
  String get outOfStock => 'Out of Stock';

  @override
  String get inStock => 'In Stock';

  @override
  String get retry => 'Retry';

  @override
  String get sectionErrorMessage => 'Something went wrong';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorNetwork =>
      'No internet connection. Please check and try again.';

  @override
  String get errorSessionExpired =>
      'Your session has expired. Please sign in again.';

  @override
  String get errorInvalidCredentials => 'Incorrect phone number or password.';

  @override
  String get errorOutOfStock => 'Some items are no longer available.';

  @override
  String get errorOutsideCoverage =>
      'This address is outside our delivery area.';

  @override
  String get errorStoreClosed => 'Sorry, the store is currently closed.';

  @override
  String get errorOtpExpired =>
      'Your code has expired. Please request a new one.';

  @override
  String get errorOtpInvalid =>
      'The code you entered is incorrect. Please try again.';

  @override
  String get errorNoAccountForPhone =>
      'No account is registered with this phone number.';

  @override
  String errorOtpCooldown(int seconds) {
    return 'Please wait ${seconds}s before requesting a new code.';
  }

  @override
  String get errorPhoneAlreadyRegistered =>
      'This phone number is already registered. Please log in instead.';

  @override
  String get categoriesEmpty => 'No categories yet';

  @override
  String get bestItemsEmpty => 'No items yet';

  @override
  String get categoryItemsEmpty => 'No items in this category yet';

  @override
  String get unitGram => 'g';

  @override
  String get unitKg => 'kg';

  @override
  String get addToBasket => 'Add to Basket';

  @override
  String get addedToCart => 'Added to cart';

  @override
  String get searchRecentTitle => 'Recent Searches';

  @override
  String get searchTrendingTitle => 'Trending';

  @override
  String get searchClearAll => 'Clear All';

  @override
  String searchNoResults(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get basketTitle => 'Basket';

  @override
  String get basketEmptyTitle => 'Your basket is empty';

  @override
  String get basketCheckout => 'Checkout';

  @override
  String get basketSubtotal => 'Subtotal';

  @override
  String get basketTotal => 'Total';

  @override
  String get basketClearAll => 'Clear All';

  @override
  String get basketClearTitle => 'Clear basket?';

  @override
  String get basketClearMessage =>
      'This will remove all items from your basket.';

  @override
  String get basketRemoveItem => 'Remove item';

  @override
  String get cartSyncFailed => 'Couldn\'t sync your basket — will retry.';

  @override
  String get favouritesTitle => 'Favorites';

  @override
  String get favouritesEmptyTitle => 'No favorites yet';

  @override
  String get favouritesGuestTitle => 'Log in to view your favorites';

  @override
  String get addressesTitle => 'My Addresses';

  @override
  String get addressesEmptyTitle => 'No addresses yet';

  @override
  String get addressAdd => 'Add Address';

  @override
  String get addressNewTitle => 'New Address';

  @override
  String get addressEditTitle => 'Edit Address';

  @override
  String get addressLabelHome => 'Home';

  @override
  String get addressLabelWork => 'Work';

  @override
  String get addressLabelOther => 'Other';

  @override
  String get addressLineLabel =>
      'Address line — optional (street, building...)';

  @override
  String get addressCityLabel => 'City — optional';

  @override
  String get addressUseCurrentLocation => 'Use my current location';

  @override
  String get addressLocationCaptured => 'Location captured';

  @override
  String get addressLocationDenied =>
      'Location permission denied — you can enter the address manually.';

  @override
  String get addressLocationDeniedForever =>
      'Location permission is blocked — enable it in your system settings, or enter the address manually.';

  @override
  String get addressLocationUnavailable =>
      'Couldn\'t get your location — you can enter the address manually.';

  @override
  String addressZoneCovered(String zone) {
    return 'Within delivery zone: $zone';
  }

  @override
  String get addressOutsideCoverage =>
      'This address is outside our delivery coverage. It was saved, but delivery isn\'t available for it yet.';

  @override
  String get addressSaved => 'Address saved';

  @override
  String get addressDefaultBadge => 'Default';

  @override
  String get addressSetDefault => 'Set as default';

  @override
  String get addressDeleteTitle => 'Delete address?';

  @override
  String get addressDeleteMessage => 'This address will be removed.';

  @override
  String get addressDelete => 'Delete';

  @override
  String get addressSave => 'Save';

  @override
  String get addressSelectPrompt => 'Select your delivery address';

  @override
  String get addressNudgeTitle => 'Add your delivery address';

  @override
  String get addressNudgeBody =>
      'Save an address so we can deliver your order to your door.';

  @override
  String get addressNudgeSkip => 'Not now';

  @override
  String get checkoutDeliveryAddress => 'Delivery Address';

  @override
  String get checkoutManageAddresses => 'Add or edit addresses';

  @override
  String get checkoutNoAddressTitle =>
      'No delivery address yet — add one to place your order.';

  @override
  String get checkoutOrderSummary => 'Order Summary';

  @override
  String get checkoutDelivery => 'Delivery';

  @override
  String get checkoutDeliveryFree => 'Free';

  @override
  String get checkoutPaymentMethod => 'Payment Method';

  @override
  String get checkoutCashOnDelivery => 'Cash on Delivery';

  @override
  String get checkoutPlaceOrder => 'Place Order';

  @override
  String get checkoutConfirmingTitle => 'Confirming your order…';

  @override
  String get checkoutConfirmingSubtitle => 'You can still cancel and edit.';

  @override
  String checkoutSendingIn(int seconds) {
    return 'Sending in ${seconds}s';
  }

  @override
  String get checkoutSendNow => 'Send now';

  @override
  String get checkoutCancelAndEdit => 'Cancel & edit';

  @override
  String get checkoutStoreClosed =>
      'The store is currently closed. Please try again during working hours.';

  @override
  String checkoutStoreClosedHours(String open, String close) {
    return 'The store is currently closed. Working hours: $open–$close';
  }

  @override
  String get checkoutOutOfStockTitle => 'Some items are unavailable';

  @override
  String get checkoutOutOfStockMessage =>
      'These items are no longer available in the requested quantity:';

  @override
  String get checkoutRefreshBasket => 'Refresh Basket';

  @override
  String get checkoutOutsideCoverageTitle => 'Outside delivery coverage';

  @override
  String get checkoutOutsideCoverageMessage =>
      'This address is outside our delivery coverage or has no location pin. Choose a different address, or set this address\'s location from your address book.';

  @override
  String get checkoutGoToAddresses => 'Manage Addresses';

  @override
  String get orderSuccessTitle => 'Your order has been placed!';

  @override
  String orderSuccessNumber(String number) {
    return 'Order number: $number';
  }

  @override
  String get orderSuccessViewOrders => 'My Orders';

  @override
  String get orderSuccessGoHome => 'Back to Home';

  @override
  String get ordersTitle => 'My Orders';

  @override
  String get ordersEmptyTitle => 'No orders yet';

  @override
  String ordersItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get orderDetailTitle => 'Order Details';

  @override
  String get orderStatusTimelineTitle => 'Order Status';

  @override
  String get orderItemsTitle => 'Items';

  @override
  String get orderChangesTitle => 'Order Changes';

  @override
  String get orderAdjustedBadge => 'Adjusted';

  @override
  String orderEstimatedQty(String qty) {
    return 'Estimated: $qty';
  }

  @override
  String orderActualQty(String qty) {
    return 'Actual: $qty';
  }

  @override
  String get orderStatusPendingAssignment => 'Pending Assignment';

  @override
  String get orderStatusAssigned => 'Assigned';

  @override
  String get orderStatusPicking => 'Picking';

  @override
  String get orderStatusPicked => 'Picked';

  @override
  String get orderStatusReadyForDelivery => 'Ready for Delivery';

  @override
  String get orderStatusOutForDelivery => 'Out for Delivery';

  @override
  String get orderStatusDelivered => 'Delivered';

  @override
  String get orderStatusExpired => 'Expired';

  @override
  String get orderStatusCancelled => 'Cancelled';

  @override
  String get changePasswordTitle => 'Change Password';

  @override
  String get changePasswordOldLabel => 'Current Password';

  @override
  String get changePasswordSubmit => 'Save New Password';

  @override
  String get changePasswordSuccess => 'Password changed';

  @override
  String get changePasswordWrongOld => 'Current password is incorrect';

  @override
  String get profileTermsTitle => 'Terms & Conditions';

  @override
  String get profilePrivacyTitle => 'Privacy Policy';

  @override
  String get supportTitle => 'Support';

  @override
  String get supportCopy => 'Copy number';

  @override
  String get supportCall => 'Call';

  @override
  String get supportWhatsapp => 'WhatsApp';

  @override
  String get supportPhoneCopied => 'Phone number copied';

  @override
  String get supportUnavailable => 'Support contact is currently unavailable';

  @override
  String get close => 'Close';

  @override
  String get profileLogoutConfirmTitle => 'Log out?';

  @override
  String get profileLogoutConfirmMessage =>
      'You will need to log in again to access your account.';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsEmptyTitle => 'No notifications yet';

  @override
  String get maintenanceTitle => 'We\'ll be back soon';

  @override
  String get maintenanceBody =>
      'The app is under maintenance right now. Please try again in a little while.';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get profileOrderSoundLabel => 'Order confirmation sound';

  @override
  String get deleteAccountTitle => 'Delete account';

  @override
  String get deleteAccountWarning =>
      'Your account will be disabled immediately and your personal data removed after 30 days. Your past orders are kept. This cannot be undone.';

  @override
  String get deleteAccountConfirmCheckbox =>
      'I understand my account will be permanently deleted';

  @override
  String get deleteAccountButton => 'Delete account';

  @override
  String get deleteAccountSuccess => 'Your account is scheduled for deletion';
}
