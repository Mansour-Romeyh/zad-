import 'package:flutter/widgets.dart';
import 'package:iconsax/iconsax.dart';

import '../../data/address_repository.dart';
import '../../l10n/app_localizations.dart';

/// The Home/Work/Other server value rendered in the UI language
/// (منزل/عمل/أخرى in Arabic). Unknown values fall through unchanged.
String localizedAddressLabel(AppLocalizations l10n, String label) {
  switch (label) {
    case AddressLabels.home:
      return l10n.addressLabelHome;
    case AddressLabels.work:
      return l10n.addressLabelWork;
    case AddressLabels.other:
      return l10n.addressLabelOther;
    default:
      return label;
  }
}

/// Icon for a Home/Work/Other label (address cards + location header).
IconData addressLabelIcon(String label) {
  switch (label) {
    case AddressLabels.home:
      return Iconsax.home_2;
    case AddressLabels.work:
      return Iconsax.briefcase;
    default:
      return Iconsax.location;
  }
}
