import 'app_banner.dart';

/// A typed intent describing what tapping a home banner should do (PRD F2).
/// Produced by [resolveBannerAction] from a banner's `link_type`/`link_value`.
sealed class BannerAction {
  const BannerAction();
}

/// Open the product detail page for [itemCode] (`/product`).
class BannerProduct extends BannerAction {
  const BannerProduct(this.itemCode);
  final String itemCode;
}

/// Open the category browser focused on [groupId] (`/categories`).
class BannerItemGroup extends BannerAction {
  const BannerItemGroup(this.groupId);
  final String groupId;
}

/// Open [url] in the external browser.
class BannerUrl extends BannerAction {
  const BannerUrl(this.url);
  final String url;
}

/// Open a screen (`/banner-items`) listing [itemCodes], titled [title].
class BannerItemList extends BannerAction {
  const BannerItemList(this.itemCodes, this.title);
  final List<String> itemCodes;
  final String title;
}

/// The banner is not linked — render it, but do not make it tappable.
class BannerNone extends BannerAction {
  const BannerNone();
}

/// Maps a banner's `link_type`/`link_value` to the action a tap performs.
/// Unknown or `None` types, and any type whose value is blank, resolve to
/// [BannerNone].
BannerAction resolveBannerAction(AppBannerModel banner) {
  // Multi-item banners carry their targets in `linkItems`, not `linkValue`,
  // so they're resolved before the blank-`link_value` guard below.
  if (banner.linkType == 'Items') {
    return banner.linkItems.isEmpty
        ? const BannerNone()
        : BannerItemList(banner.linkItems, banner.title);
  }
  final value = banner.linkValue?.trim() ?? '';
  if (value.isEmpty) return const BannerNone();
  switch (banner.linkType) {
    case 'Item':
      return BannerProduct(value);
    case 'Item Group':
      return BannerItemGroup(value);
    case 'URL':
      // Only ever launch web links from backend-controlled banner content —
      // a tel:/sms:/intent:/market: URL must not be openable from a banner.
      // (The backend also validates this at save time; this is the app-side
      // trust boundary.) A non-web URL makes the banner non-tappable.
      final uri = Uri.tryParse(value);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return const BannerNone();
      }
      return BannerUrl(value);
    default:
      return const BannerNone();
  }
}
