import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/remote_image.dart';
import '../../../models/app_banner.dart';

import 'package:provider/provider.dart';

import '../../../core/services/url_opener.dart';
import '../../../core/widgets/zad_snack.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/banner_action.dart';
import '../../category/category_browser_page.dart';
import '../../product/banner_items_page.dart';

/// Bundled fallback artwork used when a banner record has no image.
const _bannerPlaceholderImagePath = 'assets/images/banner_products.png';

/// Renders the home promo banner(s) (PRD F2 `home.get_banners`): a single
/// static card for one banner, a swipeable, auto-advancing [PageView] for
/// more than one. Zero banners collapse to nothing — `HomePage` omits the
/// whole slot (including its section gap) in that case; the
/// [SizedBox.shrink] here is only a defensive fallback for any other caller.
class PromoBanner extends StatelessWidget {
  const PromoBanner({required this.banners, super.key});

  final List<AppBannerModel> banners;

  @override
  Widget build(BuildContext context) {
    if (banners.isEmpty) return const SizedBox.shrink();
    if (banners.length > 1) return _BannerCarousel(banners: banners);
    return _BannerCard(banner: banners.first);
  }
}

/// A swipeable [PageView] of banners that also auto-advances one page every
/// [_autoScrollInterval], looping seamlessly forward. The [PageView] is
/// unbounded (no `itemCount`) and seeded a large multiple of `banners.length`
/// pages in, so `nextPage` always slides forward without a reverse "rewind"
/// at the wrap, and a manual back-swipe still has room to move. Manual swipes
/// stay in sync via the controller, and the timer keeps advancing from
/// wherever the user left off.
class _BannerCarousel extends StatefulWidget {
  const _BannerCarousel({required this.banners});

  final List<AppBannerModel> banners;

  @override
  State<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<_BannerCarousel> {
  static const _autoScrollInterval = Duration(seconds: 5);
  static const _transition = Duration(milliseconds: 400);

  // A multiple of the banner count so the first visible card is banners[0]
  // (index % length == 0) while leaving pages to swipe backwards into.
  late final int _initialPage = widget.banners.length * 1000;
  late final PageController _controller = PageController(
    initialPage: _initialPage,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_autoScrollInterval, (_) => _advance());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _advance() {
    // Guard the brief window before the PageView attaches its scroll
    // position (and any mid-frame detach), where `nextPage` would assert.
    if (!_controller.hasClients) return;
    _controller.nextPage(duration: _transition, curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    return SizedBox(
      height: 160,
      child: PageView.builder(
        controller: _controller,
        itemBuilder: (context, index) =>
            _BannerCard(banner: banners[index % banners.length]),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.banner});

  final AppBannerModel banner;

  @override
  Widget build(BuildContext context) {
    // Image-only banner: the artwork fills the whole card edge-to-edge
    // (BoxFit.cover), no overlaid headline or "Shop Now" CTA. The paleGreen
    // ground shows through only for the placeholder fallback (below) or the
    // brief moment before a network image paints.
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(ZadRadii.banner),
      child: Container(
        height: 160,
        width: double.infinity,
        color: ZadColors.paleGreen,
        child: RemoteImage(
          url: banner.imageUrl,
          fit: BoxFit.cover,
          placeholder: Image.asset(
            _bannerPlaceholderImagePath,
            fit: BoxFit.contain,
            alignment: AlignmentDirectional.bottomEnd,
          ),
        ),
      ),
    );

    // An unlinked banner (link_type None/blank or a blank value) renders
    // exactly as before — no tap target.
    final action = resolveBannerAction(banner);
    if (action is BannerNone) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _dispatch(context, action),
      child: card,
    );
  }

  /// Runs the banner's link: routes to the product/category page, or opens
  /// the external URL (mirroring `profile_tab.dart:_openUrl` for failures).
  Future<void> _dispatch(BuildContext context, BannerAction action) async {
    switch (action) {
      case BannerProduct(:final itemCode):
        Navigator.pushNamed(context, '/product', arguments: itemCode);
      case BannerItemGroup(:final groupId):
        Navigator.pushNamed(
          context,
          '/categories',
          arguments: CategoryBrowserArgs(initialGroupId: groupId),
        );
      case BannerItemList(:final itemCodes, :final title):
        Navigator.pushNamed(
          context,
          '/banner-items',
          arguments: BannerItemsArgs(itemCodes, title),
        );
      case BannerUrl(:final url):
        final l10n = AppLocalizations.of(context);
        final ok = await context.read<UrlOpener>().open(url);
        if (!ok && context.mounted) {
          showZadSnack(
            context,
            l10n.sectionErrorMessage,
            variant: ZadSnackVariant.error,
          );
        }
      case BannerNone():
        break;
    }
  }
}
