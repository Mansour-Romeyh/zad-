// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'زاد';

  @override
  String get skip => 'تخطي';

  @override
  String get onb1Title => 'اشترِ مقاضيك بسهولة معنا';

  @override
  String get onb1Body => 'اطلب مقاضيك الطازجة من هاتفك وتجنّب الطوابير.';

  @override
  String get onb2Title => 'منتجات طازجة كل يوم';

  @override
  String get onb2Body =>
      'فواكه وخضروات ومستلزمات يومية مختارة بعناية تصلك طازجة.';

  @override
  String get onb3Title => 'أفضل العروض وتوصيل سريع';

  @override
  String get onb3Body =>
      'استمتع بخصومات حصرية واستلم طلبك عند بابك خلال دقائق.';

  @override
  String get searchHint => 'ابحث';

  @override
  String get shopByCategory => 'تسوق حسب الفئة';

  @override
  String get seeAll => 'عرض الكل';

  @override
  String get sortBy => 'ترتيب حسب';

  @override
  String get sortDefault => 'الافتراضي';

  @override
  String get sortPriceLowToHigh => 'السعر: من الأقل إلى الأعلى';

  @override
  String get sortPriceHighToLow => 'السعر: من الأعلى إلى الأقل';

  @override
  String get bestDeal => 'أفضل العروض';

  @override
  String get bannerHeadline => 'مهرجان الطعام العالمي، اجلب العالم إلى مطبخك!';

  @override
  String get shopNow => 'تسوق الآن';

  @override
  String get add => 'أضف';

  @override
  String get addedToBasket => 'أُضيف إلى السلة';

  @override
  String get increaseQuantity => 'زيادة الكمية';

  @override
  String get decreaseQuantity => 'إنقاص الكمية';

  @override
  String get homeLabel => 'المنزل';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navFavorites => 'المفضلة';

  @override
  String get navCart => 'السلة';

  @override
  String get navProfile => 'الملف الشخصي';

  @override
  String get addToFavorites => 'أضف إلى المفضلة';

  @override
  String get next => 'التالي';

  @override
  String get authLoginTitle => 'تسجيل الدخول';

  @override
  String get authPhoneLabel => 'رقم الهاتف';

  @override
  String get authPhoneHint => '7XX XXX XXXX';

  @override
  String get authPhoneInvalid => 'أدخل رقم هاتف عراقي صحيح';

  @override
  String get authPasswordLabel => 'كلمة المرور';

  @override
  String get authShowPassword => 'إظهار كلمة المرور';

  @override
  String get authHidePassword => 'إخفاء كلمة المرور';

  @override
  String get authLoginButton => 'تسجيل الدخول';

  @override
  String get authNoAccount => 'ليس لديك حساب؟';

  @override
  String get authRegisterLink => 'إنشاء حساب';

  @override
  String get authForgotPassword => 'نسيت كلمة المرور؟';

  @override
  String get authRegisterTitle => 'إنشاء حساب جديد';

  @override
  String get authFullNameLabel => 'الاسم الكامل';

  @override
  String get authSendOtpButton => 'إرسال الرمز';

  @override
  String get authAlreadyHaveAccount => 'لديك حساب بالفعل؟';

  @override
  String get authLoginLink => 'تسجيل الدخول';

  @override
  String get authOtpTitle => 'تأكيد رقم الهاتف';

  @override
  String authOtpInstructions(String phone) {
    return 'أدخل الرمز المكوّن من 4 أرقام المُرسل إلى $phone';
  }

  @override
  String get authOtpHint => 'رمز مكوّن من 4 أرقام';

  @override
  String get authVerifyButton => 'تحقق';

  @override
  String get authResendCode => 'إعادة إرسال الرمز';

  @override
  String authResendIn(int seconds) {
    return 'إعادة الإرسال خلال $seconds ث';
  }

  @override
  String get authResetTitle => 'إعادة تعيين كلمة المرور';

  @override
  String get authNewPasswordLabel => 'كلمة المرور الجديدة';

  @override
  String get authResetSubmitButton => 'إعادة تعيين كلمة المرور';

  @override
  String get authResetSuccess =>
      'تمت إعادة تعيين كلمة المرور. الرجاء تسجيل الدخول.';

  @override
  String get authFieldRequired => 'هذا الحقل مطلوب';

  @override
  String get authPasswordTooShort =>
      'يجب أن تتكوّن كلمة المرور من 8 أحرف على الأقل';

  @override
  String get authLoginRequiredTitle => 'سجّل الدخول للمتابعة';

  @override
  String get profileGuestTitle => 'سجّل الدخول لعرض ملفك الشخصي';

  @override
  String profileGreeting(String name) {
    return 'مرحباً، $name';
  }

  @override
  String get profileLogoutButton => 'تسجيل الخروج';

  @override
  String get addressPlaceholder => 'بغداد';

  @override
  String get outOfStock => 'غير متوفر';

  @override
  String get inStock => 'متوفر';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get sectionErrorMessage => 'حدث خطأ ما';

  @override
  String get errorGeneric => 'حدث خطأ ما. يرجى المحاولة مرة أخرى.';

  @override
  String get errorNetwork =>
      'لا يوجد اتصال بالإنترنت. تحقق من اتصالك وحاول مجدداً.';

  @override
  String get errorSessionExpired =>
      'انتهت صلاحية جلستك. يرجى تسجيل الدخول مرة أخرى.';

  @override
  String get errorInvalidCredentials => 'رقم الهاتف أو كلمة المرور غير صحيحة.';

  @override
  String get errorOutOfStock => 'بعض المنتجات لم تعد متوفرة.';

  @override
  String get errorOutsideCoverage => 'هذا العنوان خارج نطاق التوصيل.';

  @override
  String get errorStoreClosed => 'عذراً، المتجر مغلق حالياً.';

  @override
  String get errorOtpExpired => 'انتهت صلاحية الرمز. يرجى طلب رمز جديد.';

  @override
  String get errorOtpInvalid => 'الرمز الذي أدخلته غير صحيح. حاول مرة أخرى.';

  @override
  String get errorNoAccountForPhone => 'لا يوجد حساب مسجّل بهذا الرقم.';

  @override
  String errorOtpCooldown(int seconds) {
    return 'يرجى الانتظار $seconds ث قبل طلب رمز جديد.';
  }

  @override
  String get errorPhoneAlreadyRegistered =>
      'رقم الهاتف هذا مسجّل بالفعل. يرجى تسجيل الدخول بدلاً من ذلك.';

  @override
  String get categoriesEmpty => 'لا توجد فئات بعد';

  @override
  String get bestItemsEmpty => 'لا توجد عناصر بعد';

  @override
  String get categoryItemsEmpty => 'لا توجد عناصر في هذه الفئة بعد';

  @override
  String get bannerItemsTitle => 'المنتجات';

  @override
  String get bannerItemsEmpty => 'هذه العناصر غير متوفرة حالياً';

  @override
  String get unitGram => 'غم';

  @override
  String get unitKg => 'كغم';

  @override
  String get addToBasket => 'أضف إلى السلة';

  @override
  String get addedToCart => 'تمت الإضافة إلى السلة';

  @override
  String get searchRecentTitle => 'عمليات البحث الأخيرة';

  @override
  String get searchTrendingTitle => 'الرائج';

  @override
  String get searchClearAll => 'مسح الكل';

  @override
  String searchNoResults(String query) {
    return 'لا توجد نتائج لـ \"$query\"';
  }

  @override
  String get cancel => 'إلغاء';

  @override
  String get comingSoon => 'قريباً';

  @override
  String get basketTitle => 'السلة';

  @override
  String get basketEmptyTitle => 'سلتك فارغة';

  @override
  String get basketCheckout => 'إتمام الطلب';

  @override
  String get basketSubtotal => 'المجموع الفرعي';

  @override
  String get basketTotal => 'الإجمالي';

  @override
  String get basketClearAll => 'مسح الكل';

  @override
  String get basketClearTitle => 'إفراغ السلة؟';

  @override
  String get basketClearMessage => 'سيؤدي هذا إلى إزالة جميع العناصر من سلتك.';

  @override
  String get basketRemoveItem => 'إزالة العنصر';

  @override
  String get cartSyncFailed => 'تعذر مزامنة السلة — ستتم إعادة المحاولة';

  @override
  String get favouritesTitle => 'المفضلة';

  @override
  String get favouritesEmptyTitle => 'لا توجد مفضلات';

  @override
  String get favouritesGuestTitle => 'سجّل الدخول لعرض المفضلة';

  @override
  String get addressesTitle => 'عناويني';

  @override
  String get addressesEmptyTitle => 'لا توجد عناوين بعد';

  @override
  String get addressAdd => 'إضافة عنوان';

  @override
  String get addressNewTitle => 'عنوان جديد';

  @override
  String get addressEditTitle => 'تعديل العنوان';

  @override
  String get addressLabelHome => 'منزل';

  @override
  String get addressLabelWork => 'عمل';

  @override
  String get addressLabelOther => 'أخرى';

  @override
  String get addressLineLabel =>
      'العنوان التفصيلي — اختياري (الشارع، البناية...)';

  @override
  String get addressCityLabel => 'المدينة — اختياري';

  @override
  String get addressUseCurrentLocation => 'استخدام موقعي الحالي';

  @override
  String get addressLocationCaptured => 'تم تحديد الموقع';

  @override
  String get addressLocationDenied =>
      'تم رفض إذن الموقع — يمكنك إدخال العنوان يدوياً.';

  @override
  String get addressLocationDeniedForever =>
      'إذن الموقع محظور — فعّل الموقع من إعدادات النظام، أو أدخل العنوان يدوياً.';

  @override
  String get addressLocationUnavailable =>
      'تعذر الحصول على موقعك — يمكنك إدخال العنوان يدوياً.';

  @override
  String addressZoneCovered(String zone) {
    return 'ضمن منطقة التوصيل: $zone';
  }

  @override
  String get addressOutsideCoverage =>
      'هذا العنوان خارج نطاق التغطية. تم حفظه، لكن التوصيل إليه غير متاح حالياً.';

  @override
  String get addressSaved => 'تم حفظ العنوان';

  @override
  String get addressDefaultBadge => 'افتراضي';

  @override
  String get addressSetDefault => 'تعيين كافتراضي';

  @override
  String get addressDeleteTitle => 'حذف العنوان؟';

  @override
  String get addressDeleteMessage => 'سيتم حذف هذا العنوان.';

  @override
  String get addressDelete => 'حذف';

  @override
  String get addressSave => 'حفظ';

  @override
  String get addressSelectPrompt => 'اختر عنوان التوصيل';

  @override
  String get addressNudgeTitle => 'أضف عنوان التوصيل';

  @override
  String get addressNudgeBody => 'احفظ عنوانك ليصل طلبك إلى باب بيتك.';

  @override
  String get addressNudgeSkip => 'ليس الآن';

  @override
  String get checkoutDeliveryAddress => 'عنوان التوصيل';

  @override
  String get checkoutManageAddresses => 'إضافة أو تعديل العناوين';

  @override
  String get checkoutNoAddressTitle =>
      'لا يوجد عنوان توصيل بعد — أضف عنواناً لإتمام طلبك.';

  @override
  String get checkoutOrderSummary => 'ملخص الطلب';

  @override
  String get checkoutDelivery => 'التوصيل';

  @override
  String get checkoutDeliveryFree => 'مجاني';

  @override
  String get checkoutPaymentMethod => 'طريقة الدفع';

  @override
  String get checkoutCashOnDelivery => 'الدفع عند الاستلام';

  @override
  String get checkoutPlaceOrder => 'تأكيد الطلب';

  @override
  String get checkoutConfirmingTitle => 'جارٍ تأكيد طلبك…';

  @override
  String get checkoutConfirmingSubtitle =>
      'يمكنك الإلغاء والتعديل خلال هذه المدة.';

  @override
  String checkoutSendingIn(int seconds) {
    return 'الإرسال خلال $seconds ثانية';
  }

  @override
  String get checkoutSendNow => 'أرسل الآن';

  @override
  String get checkoutCancelAndEdit => 'إلغاء وتعديل';

  @override
  String get checkoutStoreClosed =>
      'المتجر مغلق حالياً. يرجى المحاولة خلال ساعات العمل.';

  @override
  String checkoutStoreClosedHours(String open, String close) {
    return 'المتجر مغلق حالياً. ساعات العمل: $open–$close';
  }

  @override
  String get checkoutOutOfStockTitle => 'بعض العناصر غير متوفرة';

  @override
  String get checkoutOutOfStockMessage =>
      'هذه العناصر لم تعد متوفرة بالكمية المطلوبة:';

  @override
  String get checkoutRefreshBasket => 'تحديث السلة';

  @override
  String get checkoutOutsideCoverageTitle => 'خارج نطاق التوصيل';

  @override
  String get checkoutOutsideCoverageMessage =>
      'هذا العنوان خارج نطاق التغطية أو بدون موقع محدد على الخريطة. اختر عنواناً آخر، أو حدّد موقع العنوان من دفتر عناوينك.';

  @override
  String get checkoutGoToAddresses => 'إدارة العناوين';

  @override
  String get orderSuccessTitle => 'تم استلام طلبك!';

  @override
  String orderSuccessNumber(String number) {
    return 'رقم الطلب: $number';
  }

  @override
  String get orderSuccessViewOrders => 'طلباتي';

  @override
  String get orderSuccessGoHome => 'العودة إلى الرئيسية';

  @override
  String get ordersTitle => 'طلباتي';

  @override
  String get ordersEmptyTitle => 'لا توجد طلبات بعد';

  @override
  String ordersItemCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count منتج',
      many: '$count منتجاً',
      few: '$count منتجات',
      two: 'منتجان',
      one: 'منتج واحد',
      zero: 'لا منتجات',
    );
    return '$_temp0';
  }

  @override
  String get orderDetailTitle => 'تفاصيل الطلب';

  @override
  String get orderStatusTimelineTitle => 'حالة الطلب';

  @override
  String get orderItemsTitle => 'المنتجات';

  @override
  String get orderChangesTitle => 'تعديلات الطلب';

  @override
  String get orderAdjustedBadge => 'تم التعديل';

  @override
  String orderEstimatedQty(String qty) {
    return 'المقدّر: $qty';
  }

  @override
  String orderActualQty(String qty) {
    return 'الفعلي: $qty';
  }

  @override
  String get orderStatusPendingAssignment => 'بانتظار التجهيز';

  @override
  String get orderStatusAssigned => 'تم الإسناد';

  @override
  String get orderStatusPicking => 'قيد التجهيز';

  @override
  String get orderStatusPicked => 'تم التجهيز';

  @override
  String get orderStatusReadyForDelivery => 'جاهز للتوصيل';

  @override
  String get orderStatusOutForDelivery => 'قيد التوصيل';

  @override
  String get orderStatusDelivered => 'تم التوصيل';

  @override
  String get orderStatusExpired => 'منتهي الصلاحية';

  @override
  String get orderStatusCancelled => 'ملغي';

  @override
  String get changePasswordTitle => 'تغيير كلمة المرور';

  @override
  String get changePasswordOldLabel => 'كلمة المرور الحالية';

  @override
  String get changePasswordSubmit => 'حفظ كلمة المرور الجديدة';

  @override
  String get changePasswordSuccess => 'تم تغيير كلمة المرور';

  @override
  String get changePasswordWrongOld => 'كلمة المرور الحالية غير صحيحة';

  @override
  String get profileTermsTitle => 'الشروط والأحكام';

  @override
  String get profilePrivacyTitle => 'سياسة الخصوصية';

  @override
  String get supportTitle => 'الدعم';

  @override
  String get supportCopy => 'نسخ الرقم';

  @override
  String get supportCall => 'اتصال';

  @override
  String get supportWhatsapp => 'واتساب';

  @override
  String get supportPhoneCopied => 'تم نسخ رقم الهاتف';

  @override
  String get supportUnavailable => 'جهة اتصال الدعم غير متاحة حالياً';

  @override
  String get close => 'إغلاق';

  @override
  String get profileLogoutConfirmTitle => 'تسجيل الخروج؟';

  @override
  String get profileLogoutConfirmMessage =>
      'ستحتاج إلى تسجيل الدخول مجدداً للوصول إلى حسابك.';

  @override
  String get notificationsTitle => 'الإشعارات';

  @override
  String get notificationsEmptyTitle => 'لا توجد إشعارات بعد';

  @override
  String get maintenanceTitle => 'سنعود قريباً';

  @override
  String get maintenanceBody =>
      'التطبيق قيد الصيانة حالياً. يرجى المحاولة مرة أخرى بعد قليل.';

  @override
  String get languageTitle => 'اللغة';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get profileOrderSoundLabel => 'صوت تأكيد الطلب';

  @override
  String get deleteAccountTitle => 'حذف الحساب';

  @override
  String get deleteAccountWarning =>
      'سيتم تعطيل حسابك فوراً وحذف بياناتك الشخصية بعد ٣٠ يوماً. تبقى طلباتك السابقة محفوظة. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get deleteAccountConfirmCheckbox => 'أفهم أنه سيتم حذف حسابي نهائياً';

  @override
  String get deleteAccountButton => 'حذف الحساب';

  @override
  String get deleteAccountSuccess => 'تمت جدولة حذف حسابك';
}
