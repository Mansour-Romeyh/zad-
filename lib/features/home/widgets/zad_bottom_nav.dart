import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../../core/stores/cart_store.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';
import 'cart_fly.dart';

/// Bottom-nav tab indices, shared by [ZadBottomNav] and the `HomePage`
/// IndexedStack shell it drives.
const kHomeNavIndex = 0;
const kFavouritesNavIndex = 1;
const kBasketNavIndex = 2;
const kProfileNavIndex = 3;

const _navIcons = <IconData>[
  Iconsax.home_2,
  Iconsax.heart,
  Iconsax.bag_2,
  Iconsax.user,
];

/// Display cap for the basket badge — 10 or more items shows "9+" rather
/// than growing the pill indefinitely.
const _kBadgeDisplayCap = 9;

class ZadBottomNav extends StatelessWidget {
  const ZadBottomNav({
    required this.activeIndex,
    required this.onTap,
    super.key,
  });

  final int activeIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = <String>[
      l10n.navHome,
      l10n.navFavorites,
      l10n.navCart,
      l10n.navProfile,
    ];
    // The basket badge count (PRD F5 cart count) — watched here so only the
    // nav bar rebuilds when the cart changes, not the whole shell.
    final cartCount = context.watch<CartStore>().count;
    return Container(
      decoration: BoxDecoration(
        color: ZadColors.white,
        boxShadow: [
          BoxShadow(
            color: ZadColors.ink.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < _navIcons.length; i++)
                _NavItem(
                  icon: _navIcons[i],
                  label: labels[i],
                  active: i == activeIndex,
                  onTap: () => onTap(i),
                  badgeCount: i == kBasketNavIndex ? cartCount : 0,
                  flyController:
                      i == kBasketNavIndex ? CartFlyScope.maybeOf(context) : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
    this.flyController,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Cart-count badge (basket tab only); 0 hides it.
  final int badgeCount;

  /// Non-null only for the basket item and only inside a [CartFlyScope]:
  /// drives the landing bounce and provides the fly target key.
  final CartFlyController? flyController;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: badgeCount > 0 ? '$label ($badgeCount)' : label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 5,
                decoration: BoxDecoration(
                  color: active ? ZadColors.primary : Colors.transparent,
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(4)),
                ),
              ),
              const SizedBox(height: 12),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _BasketBounce(
                    controller: flyController,
                    child: Icon(
                      icon,
                      key: flyController?.basketKey,
                      size: 24,
                      color: active ? ZadColors.primary : ZadColors.ink,
                    ),
                  ),
                  if (badgeCount > 0)
                    PositionedDirectional(
                      end: -8,
                      top: -6,
                      child: _CountBadge(count: badgeCount),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill showing [count], capped at "9+" so it never grows wide
/// enough to crowd the icon.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > _kBadgeDisplayCap ? '$_kBadgeDisplayCap+' : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: ZadColors.primary,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: ZadColors.white, width: 1.5),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: ZadColors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Scales [child] up-and-back each time [controller]'s landing counter ticks.
/// A null controller (non-basket items, or the nav outside a CartFlyScope)
/// renders [child] unchanged.
class _BasketBounce extends StatefulWidget {
  const _BasketBounce({required this.controller, required this.child});

  final CartFlyController? controller;
  final Widget child;

  @override
  State<_BasketBounce> createState() => _BasketBounceState();
}

class _BasketBounceState extends State<_BasketBounce>
    with SingleTickerProviderStateMixin {
  // Created only when widget.controller is non-null (see initState): most
  // nav items pass a null controller and must never touch `this` as a
  // vsync, or AnimationController's ancestor lookup can run during
  // dispose() — after the element has already been deactivated — and
  // throw. Lazily materializing these unconditionally in dispose() is
  // exactly that trap, so they stay nullable and are only ever built when
  // there's an actual controller driving them.
  AnimationController? _animationController;
  Animation<double>? _scale;

  int _lastLandings = 0;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    _lastLandings = controller?.landings.value ?? 0;
    if (controller != null) {
      final animationController = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 320),
      );
      _animationController = animationController;
      _scale = TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.28).chain(CurveTween(curve: Curves.easeOut)),
          weight: 45,
        ),
        TweenSequenceItem(
          tween: Tween(begin: 1.28, end: 1.0).chain(CurveTween(curve: Curves.easeIn)),
          weight: 55,
        ),
      ]).animate(animationController);
      controller.landings.addListener(_onLanding);
    }
  }

  void _onLanding() {
    final value = widget.controller?.landings.value ?? 0;
    if (value != _lastLandings) {
      _lastLandings = value;
      _animationController?.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.controller?.landings.removeListener(_onLanding);
    _animationController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _scale;
    if (scale == null) return widget.child;
    return ScaleTransition(scale: scale, child: widget.child);
  }
}
