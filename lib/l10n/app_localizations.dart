import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Zad'**
  String get appTitle;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @onb1Title.
  ///
  /// In en, this message translates to:
  /// **'Buy Groceries Easily with Us'**
  String get onb1Title;

  /// No description provided for @onb1Body.
  ///
  /// In en, this message translates to:
  /// **'Order fresh groceries from your phone and skip the queue.'**
  String get onb1Body;

  /// No description provided for @onb2Title.
  ///
  /// In en, this message translates to:
  /// **'Fresh Products Every Day'**
  String get onb2Title;

  /// No description provided for @onb2Body.
  ///
  /// In en, this message translates to:
  /// **'Hand-picked fruits, vegetables and daily essentials delivered fresh.'**
  String get onb2Body;

  /// No description provided for @onb3Title.
  ///
  /// In en, this message translates to:
  /// **'Best Deals, Fast Delivery'**
  String get onb3Title;

  /// No description provided for @onb3Body.
  ///
  /// In en, this message translates to:
  /// **'Enjoy exclusive discounts and get your order at your door in minutes.'**
  String get onb3Body;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchHint;

  /// No description provided for @shopByCategory.
  ///
  /// In en, this message translates to:
  /// **'Shop By Category'**
  String get shopByCategory;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAll;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get sortBy;

  /// No description provided for @sortDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get sortDefault;

  /// No description provided for @sortPriceLowToHigh.
  ///
  /// In en, this message translates to:
  /// **'Price: Low to High'**
  String get sortPriceLowToHigh;

  /// No description provided for @sortPriceHighToLow.
  ///
  /// In en, this message translates to:
  /// **'Price: High to Low'**
  String get sortPriceHighToLow;

  /// No description provided for @bestDeal.
  ///
  /// In en, this message translates to:
  /// **'Best Deal'**
  String get bestDeal;

  /// No description provided for @bannerHeadline.
  ///
  /// In en, this message translates to:
  /// **'World Food Festival, Bring the world to your Kitchen!'**
  String get bannerHeadline;

  /// No description provided for @shopNow.
  ///
  /// In en, this message translates to:
  /// **'Shop Now'**
  String get shopNow;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addedToBasket.
  ///
  /// In en, this message translates to:
  /// **'Added to basket'**
  String get addedToBasket;

  /// No description provided for @increaseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Increase quantity'**
  String get increaseQuantity;

  /// No description provided for @decreaseQuantity.
  ///
  /// In en, this message translates to:
  /// **'Decrease quantity'**
  String get decreaseQuantity;

  /// No description provided for @homeLabel.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeLabel;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get navFavorites;

  /// No description provided for @navCart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get navCart;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @addToFavorites.
  ///
  /// In en, this message translates to:
  /// **'Add to favorites'**
  String get addToFavorites;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @authLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authLoginTitle;

  /// No description provided for @authPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get authPhoneLabel;

  /// No description provided for @authPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'7XX XXX XXXX'**
  String get authPhoneHint;

  /// No description provided for @authPhoneInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid Iraqi phone number'**
  String get authPhoneInvalid;

  /// No description provided for @authPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// No description provided for @authShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get authShowPassword;

  /// No description provided for @authHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get authHidePassword;

  /// No description provided for @authLoginButton.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authLoginButton;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get authNoAccount;

  /// No description provided for @authRegisterLink.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get authRegisterLink;

  /// No description provided for @authForgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get authForgotPassword;

  /// No description provided for @authRegisterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get authRegisterTitle;

  /// No description provided for @authFullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get authFullNameLabel;

  /// No description provided for @authSendOtpButton.
  ///
  /// In en, this message translates to:
  /// **'Send Code'**
  String get authSendOtpButton;

  /// No description provided for @authAlreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get authAlreadyHaveAccount;

  /// No description provided for @authLoginLink.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get authLoginLink;

  /// No description provided for @authOtpTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify Phone Number'**
  String get authOtpTitle;

  /// No description provided for @authOtpInstructions.
  ///
  /// In en, this message translates to:
  /// **'Enter the 4-digit code sent to {phone}'**
  String authOtpInstructions(String phone);

  /// No description provided for @authOtpHint.
  ///
  /// In en, this message translates to:
  /// **'4-digit code'**
  String get authOtpHint;

  /// No description provided for @authVerifyButton.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get authVerifyButton;

  /// No description provided for @authResendCode.
  ///
  /// In en, this message translates to:
  /// **'Resend Code'**
  String get authResendCode;

  /// No description provided for @authResendIn.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String authResendIn(int seconds);

  /// No description provided for @authResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get authResetTitle;

  /// No description provided for @authNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get authNewPasswordLabel;

  /// No description provided for @authResetSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get authResetSubmitButton;

  /// No description provided for @authResetSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password reset. Please log in.'**
  String get authResetSuccess;

  /// No description provided for @authFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get authFieldRequired;

  /// No description provided for @authPasswordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get authPasswordTooShort;

  /// No description provided for @authLoginRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to continue'**
  String get authLoginRequiredTitle;

  /// No description provided for @profileGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to view your profile'**
  String get profileGuestTitle;

  /// No description provided for @profileGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String profileGreeting(String name);

  /// No description provided for @profileLogoutButton.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get profileLogoutButton;

  /// No description provided for @addressPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Baghdad'**
  String get addressPlaceholder;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get outOfStock;

  /// No description provided for @inStock.
  ///
  /// In en, this message translates to:
  /// **'In Stock'**
  String get inStock;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @sectionErrorMessage.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get sectionErrorMessage;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @errorNetwork.
  ///
  /// In en, this message translates to:
  /// **'No internet connection. Please check and try again.'**
  String get errorNetwork;

  /// No description provided for @errorSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has expired. Please sign in again.'**
  String get errorSessionExpired;

  /// No description provided for @errorInvalidCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect phone number or password.'**
  String get errorInvalidCredentials;

  /// No description provided for @errorOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Some items are no longer available.'**
  String get errorOutOfStock;

  /// No description provided for @errorOutsideCoverage.
  ///
  /// In en, this message translates to:
  /// **'This address is outside our delivery area.'**
  String get errorOutsideCoverage;

  /// No description provided for @errorStoreClosed.
  ///
  /// In en, this message translates to:
  /// **'Sorry, the store is currently closed.'**
  String get errorStoreClosed;

  /// No description provided for @errorOtpExpired.
  ///
  /// In en, this message translates to:
  /// **'Your code has expired. Please request a new one.'**
  String get errorOtpExpired;

  /// No description provided for @errorOtpInvalid.
  ///
  /// In en, this message translates to:
  /// **'The code you entered is incorrect. Please try again.'**
  String get errorOtpInvalid;

  /// No description provided for @errorNoAccountForPhone.
  ///
  /// In en, this message translates to:
  /// **'No account is registered with this phone number.'**
  String get errorNoAccountForPhone;

  /// No description provided for @errorOtpCooldown.
  ///
  /// In en, this message translates to:
  /// **'Please wait {seconds}s before requesting a new code.'**
  String errorOtpCooldown(int seconds);

  /// No description provided for @errorPhoneAlreadyRegistered.
  ///
  /// In en, this message translates to:
  /// **'This phone number is already registered. Please log in instead.'**
  String get errorPhoneAlreadyRegistered;

  /// No description provided for @categoriesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No categories yet'**
  String get categoriesEmpty;

  /// No description provided for @bestItemsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No items yet'**
  String get bestItemsEmpty;

  /// No description provided for @categoryItemsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No items in this category yet'**
  String get categoryItemsEmpty;

  /// No description provided for @bannerItemsTitle.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get bannerItemsTitle;

  /// No description provided for @bannerItemsEmpty.
  ///
  /// In en, this message translates to:
  /// **'These items aren\'t available right now'**
  String get bannerItemsEmpty;

  /// No description provided for @unitGram.
  ///
  /// In en, this message translates to:
  /// **'g'**
  String get unitGram;

  /// No description provided for @unitKg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get unitKg;

  /// No description provided for @addToBasket.
  ///
  /// In en, this message translates to:
  /// **'Add to Basket'**
  String get addToBasket;

  /// No description provided for @addedToCart.
  ///
  /// In en, this message translates to:
  /// **'Added to cart'**
  String get addedToCart;

  /// No description provided for @searchRecentTitle.
  ///
  /// In en, this message translates to:
  /// **'Recent Searches'**
  String get searchRecentTitle;

  /// No description provided for @searchTrendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Trending'**
  String get searchTrendingTitle;

  /// No description provided for @searchClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get searchClearAll;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String searchNoResults(String query);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

  /// No description provided for @basketTitle.
  ///
  /// In en, this message translates to:
  /// **'Basket'**
  String get basketTitle;

  /// No description provided for @basketEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your basket is empty'**
  String get basketEmptyTitle;

  /// No description provided for @basketCheckout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get basketCheckout;

  /// No description provided for @basketSubtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get basketSubtotal;

  /// No description provided for @basketTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get basketTotal;

  /// No description provided for @basketClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get basketClearAll;

  /// No description provided for @basketClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear basket?'**
  String get basketClearTitle;

  /// No description provided for @basketClearMessage.
  ///
  /// In en, this message translates to:
  /// **'This will remove all items from your basket.'**
  String get basketClearMessage;

  /// No description provided for @basketRemoveItem.
  ///
  /// In en, this message translates to:
  /// **'Remove item'**
  String get basketRemoveItem;

  /// No description provided for @cartSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync your basket — will retry.'**
  String get cartSyncFailed;

  /// No description provided for @favouritesTitle.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favouritesTitle;

  /// No description provided for @favouritesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get favouritesEmptyTitle;

  /// No description provided for @favouritesGuestTitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to view your favorites'**
  String get favouritesGuestTitle;

  /// No description provided for @addressesTitle.
  ///
  /// In en, this message translates to:
  /// **'My Addresses'**
  String get addressesTitle;

  /// No description provided for @addressesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No addresses yet'**
  String get addressesEmptyTitle;

  /// No description provided for @addressAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Address'**
  String get addressAdd;

  /// No description provided for @addressNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New Address'**
  String get addressNewTitle;

  /// No description provided for @addressEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Address'**
  String get addressEditTitle;

  /// No description provided for @addressLabelHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get addressLabelHome;

  /// No description provided for @addressLabelWork.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get addressLabelWork;

  /// No description provided for @addressLabelOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get addressLabelOther;

  /// No description provided for @addressLineLabel.
  ///
  /// In en, this message translates to:
  /// **'Address line — optional (street, building...)'**
  String get addressLineLabel;

  /// No description provided for @addressCityLabel.
  ///
  /// In en, this message translates to:
  /// **'City — optional'**
  String get addressCityLabel;

  /// No description provided for @addressUseCurrentLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my current location'**
  String get addressUseCurrentLocation;

  /// No description provided for @addressLocationCaptured.
  ///
  /// In en, this message translates to:
  /// **'Location captured'**
  String get addressLocationCaptured;

  /// No description provided for @addressLocationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied — you can enter the address manually.'**
  String get addressLocationDenied;

  /// No description provided for @addressLocationDeniedForever.
  ///
  /// In en, this message translates to:
  /// **'Location permission is blocked — enable it in your system settings, or enter the address manually.'**
  String get addressLocationDeniedForever;

  /// No description provided for @addressLocationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t get your location — you can enter the address manually.'**
  String get addressLocationUnavailable;

  /// No description provided for @addressZoneCovered.
  ///
  /// In en, this message translates to:
  /// **'Within delivery zone: {zone}'**
  String addressZoneCovered(String zone);

  /// No description provided for @addressOutsideCoverage.
  ///
  /// In en, this message translates to:
  /// **'This address is outside our delivery coverage. It was saved, but delivery isn\'t available for it yet.'**
  String get addressOutsideCoverage;

  /// No description provided for @addressSaved.
  ///
  /// In en, this message translates to:
  /// **'Address saved'**
  String get addressSaved;

  /// No description provided for @addressDefaultBadge.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get addressDefaultBadge;

  /// No description provided for @addressSetDefault.
  ///
  /// In en, this message translates to:
  /// **'Set as default'**
  String get addressSetDefault;

  /// No description provided for @addressDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete address?'**
  String get addressDeleteTitle;

  /// No description provided for @addressDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This address will be removed.'**
  String get addressDeleteMessage;

  /// No description provided for @addressDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get addressDelete;

  /// No description provided for @addressSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get addressSave;

  /// No description provided for @addressSelectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select your delivery address'**
  String get addressSelectPrompt;

  /// No description provided for @addressNudgeTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your delivery address'**
  String get addressNudgeTitle;

  /// No description provided for @addressNudgeBody.
  ///
  /// In en, this message translates to:
  /// **'Save an address so we can deliver your order to your door.'**
  String get addressNudgeBody;

  /// No description provided for @addressNudgeSkip.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get addressNudgeSkip;

  /// No description provided for @checkoutDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery Address'**
  String get checkoutDeliveryAddress;

  /// No description provided for @checkoutManageAddresses.
  ///
  /// In en, this message translates to:
  /// **'Add or edit addresses'**
  String get checkoutManageAddresses;

  /// No description provided for @checkoutNoAddressTitle.
  ///
  /// In en, this message translates to:
  /// **'No delivery address yet — add one to place your order.'**
  String get checkoutNoAddressTitle;

  /// No description provided for @checkoutOrderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order Summary'**
  String get checkoutOrderSummary;

  /// No description provided for @checkoutDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get checkoutDelivery;

  /// No description provided for @checkoutDeliveryFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get checkoutDeliveryFree;

  /// No description provided for @checkoutPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get checkoutPaymentMethod;

  /// No description provided for @checkoutCashOnDelivery.
  ///
  /// In en, this message translates to:
  /// **'Cash on Delivery'**
  String get checkoutCashOnDelivery;

  /// No description provided for @checkoutPlaceOrder.
  ///
  /// In en, this message translates to:
  /// **'Place Order'**
  String get checkoutPlaceOrder;

  /// No description provided for @checkoutConfirmingTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirming your order…'**
  String get checkoutConfirmingTitle;

  /// No description provided for @checkoutConfirmingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You can still cancel and edit.'**
  String get checkoutConfirmingSubtitle;

  /// No description provided for @checkoutSendingIn.
  ///
  /// In en, this message translates to:
  /// **'Sending in {seconds}s'**
  String checkoutSendingIn(int seconds);

  /// No description provided for @checkoutSendNow.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get checkoutSendNow;

  /// No description provided for @checkoutCancelAndEdit.
  ///
  /// In en, this message translates to:
  /// **'Cancel & edit'**
  String get checkoutCancelAndEdit;

  /// No description provided for @checkoutStoreClosed.
  ///
  /// In en, this message translates to:
  /// **'The store is currently closed. Please try again during working hours.'**
  String get checkoutStoreClosed;

  /// No description provided for @checkoutStoreClosedHours.
  ///
  /// In en, this message translates to:
  /// **'The store is currently closed. Working hours: {open}–{close}'**
  String checkoutStoreClosedHours(String open, String close);

  /// No description provided for @checkoutOutOfStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Some items are unavailable'**
  String get checkoutOutOfStockTitle;

  /// No description provided for @checkoutOutOfStockMessage.
  ///
  /// In en, this message translates to:
  /// **'These items are no longer available in the requested quantity:'**
  String get checkoutOutOfStockMessage;

  /// No description provided for @checkoutRefreshBasket.
  ///
  /// In en, this message translates to:
  /// **'Refresh Basket'**
  String get checkoutRefreshBasket;

  /// No description provided for @checkoutOutsideCoverageTitle.
  ///
  /// In en, this message translates to:
  /// **'Outside delivery coverage'**
  String get checkoutOutsideCoverageTitle;

  /// No description provided for @checkoutOutsideCoverageMessage.
  ///
  /// In en, this message translates to:
  /// **'This address is outside our delivery coverage or has no location pin. Choose a different address, or set this address\'s location from your address book.'**
  String get checkoutOutsideCoverageMessage;

  /// No description provided for @checkoutGoToAddresses.
  ///
  /// In en, this message translates to:
  /// **'Manage Addresses'**
  String get checkoutGoToAddresses;

  /// No description provided for @orderSuccessTitle.
  ///
  /// In en, this message translates to:
  /// **'Your order has been placed!'**
  String get orderSuccessTitle;

  /// No description provided for @orderSuccessNumber.
  ///
  /// In en, this message translates to:
  /// **'Order number: {number}'**
  String orderSuccessNumber(String number);

  /// No description provided for @orderSuccessViewOrders.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get orderSuccessViewOrders;

  /// No description provided for @orderSuccessGoHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get orderSuccessGoHome;

  /// No description provided for @ordersTitle.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get ordersTitle;

  /// No description provided for @ordersEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get ordersEmptyTitle;

  /// No description provided for @ordersItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String ordersItemCount(int count);

  /// No description provided for @orderDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get orderDetailTitle;

  /// No description provided for @orderStatusTimelineTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Status'**
  String get orderStatusTimelineTitle;

  /// No description provided for @orderItemsTitle.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get orderItemsTitle;

  /// No description provided for @orderChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Order Changes'**
  String get orderChangesTitle;

  /// No description provided for @orderAdjustedBadge.
  ///
  /// In en, this message translates to:
  /// **'Adjusted'**
  String get orderAdjustedBadge;

  /// No description provided for @orderEstimatedQty.
  ///
  /// In en, this message translates to:
  /// **'Estimated: {qty}'**
  String orderEstimatedQty(String qty);

  /// No description provided for @orderActualQty.
  ///
  /// In en, this message translates to:
  /// **'Actual: {qty}'**
  String orderActualQty(String qty);

  /// No description provided for @orderStatusPendingAssignment.
  ///
  /// In en, this message translates to:
  /// **'Pending Assignment'**
  String get orderStatusPendingAssignment;

  /// No description provided for @orderStatusAssigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get orderStatusAssigned;

  /// No description provided for @orderStatusPicking.
  ///
  /// In en, this message translates to:
  /// **'Picking'**
  String get orderStatusPicking;

  /// No description provided for @orderStatusPicked.
  ///
  /// In en, this message translates to:
  /// **'Picked'**
  String get orderStatusPicked;

  /// No description provided for @orderStatusReadyForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Ready for Delivery'**
  String get orderStatusReadyForDelivery;

  /// No description provided for @orderStatusOutForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Out for Delivery'**
  String get orderStatusOutForDelivery;

  /// No description provided for @orderStatusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get orderStatusDelivered;

  /// No description provided for @orderStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get orderStatusExpired;

  /// No description provided for @orderStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get orderStatusCancelled;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordTitle;

  /// No description provided for @changePasswordOldLabel.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get changePasswordOldLabel;

  /// No description provided for @changePasswordSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save New Password'**
  String get changePasswordSubmit;

  /// No description provided for @changePasswordSuccess.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get changePasswordSuccess;

  /// No description provided for @changePasswordWrongOld.
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect'**
  String get changePasswordWrongOld;

  /// No description provided for @profileTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get profileTermsTitle;

  /// No description provided for @profilePrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get profilePrivacyTitle;

  /// No description provided for @supportTitle.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportTitle;

  /// No description provided for @supportCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy number'**
  String get supportCopy;

  /// No description provided for @supportCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get supportCall;

  /// No description provided for @supportWhatsapp.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get supportWhatsapp;

  /// No description provided for @supportPhoneCopied.
  ///
  /// In en, this message translates to:
  /// **'Phone number copied'**
  String get supportPhoneCopied;

  /// No description provided for @supportUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Support contact is currently unavailable'**
  String get supportUnavailable;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @profileLogoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log out?'**
  String get profileLogoutConfirmTitle;

  /// No description provided for @profileLogoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You will need to log in again to access your account.'**
  String get profileLogoutConfirmMessage;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notificationsEmptyTitle;

  /// No description provided for @maintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll be back soon'**
  String get maintenanceTitle;

  /// No description provided for @maintenanceBody.
  ///
  /// In en, this message translates to:
  /// **'The app is under maintenance right now. Please try again in a little while.'**
  String get maintenanceBody;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @profileOrderSoundLabel.
  ///
  /// In en, this message translates to:
  /// **'Order confirmation sound'**
  String get profileOrderSoundLabel;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'Your account will be disabled immediately and your personal data removed after 30 days. Your past orders are kept. This cannot be undone.'**
  String get deleteAccountWarning;

  /// No description provided for @deleteAccountConfirmCheckbox.
  ///
  /// In en, this message translates to:
  /// **'I understand my account will be permanently deleted'**
  String get deleteAccountConfirmCheckbox;

  /// No description provided for @deleteAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccountButton;

  /// No description provided for @deleteAccountSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your account is scheduled for deletion'**
  String get deleteAccountSuccess;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
