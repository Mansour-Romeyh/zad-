import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/theme.dart';
import '../../../core/widgets/zad_snack.dart';
import '../../../l10n/app_localizations.dart';

/// Owns the add-to-basket "fly" feedback: the basket target's position and
/// the landing counter the basket icon watches to bounce. The `fly(...)`
/// method (Task 3) animates a thumbnail from a source point to the basket.
///
/// One instance lives on the Home shell (`_HomePageState`), shared by the
/// bottom-nav basket icon (which attaches [basketKey]) and the item cards
/// (which trigger flies) via [CartFlyScope].
class CartFlyController {
  /// Attached by the bottom-nav basket icon so the controller can read the
  /// fly target's global center from its `RenderBox`.
  final GlobalKey basketKey = GlobalKey();

  final ValueNotifier<int> _landings = ValueNotifier<int>(0);

  /// Increments once each time a flying thumbnail lands on the basket — the
  /// basket icon listens and plays its bounce.
  ValueListenable<int> get landings => _landings;

  final Set<OverlayEntry> _entries = <OverlayEntry>{};

  /// Animates [image] (or a bag icon when null) from [from] to the basket
  /// icon's center, then bounces the basket. No-op if the basket target is
  /// not on screen / not laid out yet.
  ///
  /// Multiple flies can be in flight at once (e.g. the user taps add on two
  /// products in quick succession); each one animates to completion and
  /// bumps [landings] independently.
  void fly({
    required Offset from,
    ImageProvider? image,
    required OverlayState overlay,
  }) {
    final to = _basketCenter();
    if (to == null) return;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _FlyingThumb(
        from: from,
        to: to,
        image: image,
        onDone: () => _onLanded(entry),
      ),
    );
    _entries.add(entry);
    overlay.insert(entry);
  }

  void _onLanded(OverlayEntry entry) {
    // Guard so a stray late callback (e.g. after dispose) can neither
    // double-count nor touch a disposed notifier.
    if (_entries.remove(entry)) {
      entry.remove();
      _landings.value++;
    }
  }

  Offset? _basketCenter() {
    final context = basketKey.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void dispose() {
    for (final entry in _entries) {
      entry.remove();
    }
    _entries.clear();
    _landings.dispose();
  }
}

/// Marks the Home shell subtree so item cards inside it can find the
/// [CartFlyController]. Pushed routes (category, search, detail) are not
/// descendants, so [maybeOf] returns null there and those cards fall back to
/// the "Added" toast.
class CartFlyScope extends InheritedWidget {
  const CartFlyScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final CartFlyController controller;

  /// No dependency is registered (uses `getInheritedWidgetOfExactType`), so
  /// this is safe to call from tap handlers, not just `build`.
  static CartFlyController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CartFlyScope>()?.controller;

  static CartFlyController of(BuildContext context) {
    final controller = maybeOf(context);
    assert(controller != null, 'CartFlyScope.of() found no CartFlyScope ancestor');
    return controller!;
  }

  @override
  bool updateShouldNotify(CartFlyScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Test-only alias for the private flying thumbnail.
@visibleForTesting
typedef FlyingThumbForTest = _FlyingThumb;

/// A small rounded thumbnail that arcs from [from] to [to] while shrinking and
/// fading, then calls [onDone]. Rendered in the root overlay above the nav bar.
class _FlyingThumb extends StatefulWidget {
  const _FlyingThumb({
    required this.from,
    required this.to,
    required this.image,
    required this.onDone,
  });

  final Offset from;
  final Offset to;
  final ImageProvider? image;
  final VoidCallback onDone;

  @override
  State<_FlyingThumb> createState() => _FlyingThumbState();
}

class _FlyingThumbState extends State<_FlyingThumb>
    with SingleTickerProviderStateMixin {
  static const _startSize = 48.0;
  static const _endSize = 20.0;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Removing an overlay entry must not happen mid-frame.
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone());
      }
    });

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Quadratic-bezier arc: a raised control point gives the photo a curved
  /// path toward the basket instead of a straight line.
  Offset _arc(double t) {
    final control = Offset(
      (widget.from.dx + widget.to.dx) / 2,
      (widget.from.dy < widget.to.dy ? widget.from.dy : widget.to.dy) - 80,
    );
    final u = 1 - t;
    return widget.from * (u * u) + control * (2 * u * t) + widget.to * (t * t);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_controller.value);
        final pos = _arc(t);
        final size = _startSize + (_endSize - _startSize) * t;
        final opacity = t < 0.85 ? 1.0 : (1 - (t - 0.85) / 0.15).clamp(0.0, 1.0);
        return Positioned(
          left: pos.dx - size / 2,
          top: pos.dy - size / 2,
          child: IgnorePointer(
            child: Opacity(opacity: opacity, child: _thumb(size)),
          ),
        );
      },
    );
  }

  Widget _thumb(double size) {
    final image = widget.image;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ZadColors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: ZadColors.ink.withValues(alpha: 0.18),
            blurRadius: 8,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null
          ? const Icon(Iconsax.bag_2, size: 16, color: ZadColors.primary)
          : Image(
              image: image,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Iconsax.bag_2, size: 16, color: ZadColors.primary),
            ),
    );
  }
}

/// Brief confirmation shown when the item was added but no fly is possible
/// (pushed route with no basket icon, or reduce-motion). Guard `context.mounted`.
void showAddedToBasketSnackBar(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  showZadSnack(context, l10n.addedToBasket, variant: ZadSnackVariant.success);
}
