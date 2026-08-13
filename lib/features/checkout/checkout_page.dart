import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/audio/order_feedback_service.dart';
import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/session/session_store.dart';
import '../../core/stores/address_store.dart';
import '../../core/stores/app_config_store.dart';
import '../../core/stores/cart_store.dart';
import '../../core/stores/settings_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/zad_dialog.dart';
import '../../data/address_repository.dart';
import '../../data/cart_repository.dart' show CartTotals;
import '../../data/order_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../models/app_config.dart';
import '../addresses/address_label.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../home/widgets/async_section.dart';
import '../product/weight_selector.dart';
import 'order_success_page.dart';

/// `/checkout` (PRD E3/F5 `order.place_order`): delivery-address selector
/// (default preselected, link to the address book), the cart's summary
/// lines + totals, the fixed COD payment method, and the Place Order CTA.
///
/// Idempotency (PRD E3): ONE uuid v4 key is generated per checkout attempt
/// — i.e. per visit to this page — and held constant across every retry of
/// that attempt (network error, 409, 417), so a retried `place_order` can
/// never place a second order. Error contract: 409 → dialog naming the
/// unavailable items with a "تحديث السلة" action; 417 → dialog directing
/// the user to a different address or to set this one's location pin (a
/// manually-entered address has no coordinates and always fails coverage);
/// 425 (store closed) → the working-hours notice replaces the armed CTA;
/// anything else → SnackBar, the button stays armed with the same key.
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, this.clock = DateTime.now});

  /// "Now" source for the working-hours check — injectable so widget
  /// tests pin the instant; production uses the device clock. The server
  /// re-checks with its own clock at `place_order` either way.
  final DateTime Function() clock;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  /// The attempt's idempotency key — generated once when checkout opens,
  /// reused verbatim by every retry of this attempt (PRD E3).
  final String _idempotencyKey = const Uuid().v4();

  /// The user's explicit address choice; `null` until they tap one, in
  /// which case the store's default (or first) address is used.
  String? _selectedAddress;

  bool _placing = false;

  /// Non-null while the post-tap confirm hold is running: the seconds
  /// remaining before the held order is sent. The order is NOT on the server
  /// during this window (app-only hold, [kOrderCancelWindow]) — cancelling
  /// here sends nothing. The address captured at tap time is what gets sent.
  int? _pendingSeconds;
  Timer? _cancelTimer;
  AddressModel? _pendingAddress;

  /// Set when `place_order` came back 425 — the server's clock says
  /// closed even if the device clock disagrees; server wins.
  bool _serverSaysClosed = false;

  @override
  void initState() {
    super.initState();
    // Post-frame like AddressListPage: refresh() notifies synchronously
    // and the home header may be listening from another route.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AddressStore>().refresh();
    });
  }

  @override
  void dispose() {
    _cancelTimer?.cancel();
    super.dispose();
  }

  /// Tapping "Place Order" opens a [kOrderCancelWindow] hold instead of
  /// sending straightaway: the confirm overlay counts down and the order is
  /// only sent when it reaches zero (or the user taps "Send now"). Cancelling
  /// during the hold sends nothing — no order ever reaches the server.
  void _startConfirmCountdown(AddressModel address) {
    if (_placing || _pendingSeconds != null) return;
    _cancelTimer?.cancel();
    setState(() {
      _pendingAddress = address;
      _pendingSeconds = kOrderCancelWindow.inSeconds;
    });
    _cancelTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = (_pendingSeconds ?? 0) - 1;
      if (remaining <= 0) {
        timer.cancel();
        _sendNow(address);
      } else {
        setState(() => _pendingSeconds = remaining);
      }
    });
  }

  /// End the hold and send the order now — used both by the "Send now" button
  /// and by the countdown reaching zero.
  void _sendNow(AddressModel address) {
    _cancelTimer?.cancel();
    setState(() {
      _pendingSeconds = null;
      _pendingAddress = null;
    });
    _placeOrder(address);
  }

  /// Cancel the hold and drop back to the editable checkout. Nothing was sent.
  void _cancelConfirmCountdown() {
    _cancelTimer?.cancel();
    setState(() {
      _pendingSeconds = null;
      _pendingAddress = null;
    });
  }

  /// The address `place_order` will be sent: the user's tap if it still
  /// exists, else the default address, else the first one.
  AddressModel? _effectiveAddress(AddressStore store) {
    final addresses = store.addresses;
    if (addresses.isEmpty) return null;
    for (final address in addresses) {
      if (address.name == _selectedAddress) return address;
    }
    return store.defaultAddress ?? addresses.first;
  }

  /// Closed-notice copy: with the window when the config carries it,
  /// generic otherwise (e.g. a 425 against a stale cached config).
  String _closedMessage(AppLocalizations l10n, AppConfig config) {
    final open = config.storeOpenTime;
    final close = config.storeCloseTime;
    if (open == null || close == null) return l10n.checkoutStoreClosed;
    return l10n.checkoutStoreClosedHours(_hhmm(open), _hhmm(close));
  }

  /// `"HH:MM:SS"` → `"HH:MM"` for display.
  String _hhmm(String raw) => raw.length >= 5 ? raw.substring(0, 5) : raw;

  Future<void> _placeOrder(AddressModel address) async {
    // Re-entrancy guard: a double-tap lands before the loading rebuild
    // disables the CTA — the second call must never fire a second
    // `place_order`, idempotency key or not.
    if (_placing) return;
    final repository = context.read<OrderRepository>();
    final cart = context.read<CartStore>();
    final settings = context.read<SettingsStore>();
    final feedback = context.read<OrderFeedbackService>();
    setState(() => _placing = true);
    try {
      final placement = await repository.placeOrder(
        address: address.name,
        idempotencyKey: _idempotencyKey,
      );
      // The server closed the cart Quotation — re-pull so the basket badge
      // and tab reflect the now-empty cart. Best-effort: a refresh failure
      // must never hide the confirmation of an order that WAS placed.
      cart.refresh().catchError((_) {});
      // "Order created" cue (fire-and-forget; the service swallows its own
      // errors, so this never blocks or breaks the confirmation/navigation).
      // Matches cart.refresh() above: a chained catchError, not a guarding
      // try, so a misbehaving implementation still can't surface here.
      if (settings.orderSoundEnabled) {
        feedback.playOrderPlaced().catchError((_) {});
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(
          builder: (_) => OrderSuccessPage(
            orderName: placement.order,
            status: placement.status,
          ),
        ),
      );
    } on OutOfStockException catch (e) {
      if (!mounted) return;
      // Un-spin the CTA before the dialog: the attempt is over, only the
      // user's next move (refresh basket / retry) is pending.
      setState(() => _placing = false);
      await _showOutOfStockDialog(e, cart);
    } on OutsideCoverageException catch (_) {
      if (!mounted) return;
      setState(() => _placing = false);
      await _showOutsideCoverageDialog();
    } on StoreClosedException catch (_) {
      if (!mounted) return;
      setState(() {
        _placing = false;
        _serverSaysClosed = true;
      });
    } on ApiException catch (e) {
      // Network or other server error: the order may or may not exist —
      // the SAME key on the next tap makes the retry safe either way.
      if (!mounted) return;
      showErrorSnackBar(context, e);
    } finally {
      if (mounted && _placing) setState(() => _placing = false);
    }
  }

  /// 409 (PRD E3): name the short items (resolved to their cart-line names
  /// where possible) and offer "تحديث السلة" so the user sees the current
  /// availability before retrying.
  Future<void> _showOutOfStockDialog(OutOfStockException e, CartStore cart) async {
    final l10n = AppLocalizations.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    final lines = cart.items;
    final names = [
      for (final item in e.items)
        lines
            .where((line) => line.itemCode == item.toString())
            .map((line) => line.nameFor(languageCode))
            .firstOrNull ??
            item.toString(),
    ];
    await showZadDialog<void>(
      context,
      icon: Icons.remove_shopping_cart_outlined,
      title: l10n.checkoutOutOfStockTitle,
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.checkoutOutOfStockMessage),
          const SizedBox(height: 10),
          for (final name in names)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2),
              child: Text(
                '• $name',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      actions: [
        zadDialogPrimaryAction(
          label: l10n.checkoutRefreshBasket,
          onPressed: () {
            Navigator.pop(context);
            cart.refresh().catchError((_) {});
          },
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const Key('outOfStockCancelButton'),
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  /// 417 (PRD E3/J3): the server's authoritative zone re-check failed —
  /// either the address is genuinely outside coverage or it has no location
  /// pin at all (every manually-entered address: lat/lng 0). Both fixes
  /// live in the address book, so the dialog deep-links there.
  Future<void> _showOutsideCoverageDialog() async {
    final l10n = AppLocalizations.of(context);
    await showZadDialog<void>(
      context,
      icon: Icons.location_off_outlined,
      title: l10n.checkoutOutsideCoverageTitle,
      contentBuilder: (_) => Text(
        l10n.checkoutOutsideCoverageMessage,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14, color: ZadColors.muted, height: 1.4),
      ),
      actions: [
        zadDialogPrimaryAction(
          label: l10n.checkoutGoToAddresses,
          onPressed: () {
            Navigator.pop(context);
            Navigator.pushNamed(context, '/addresses');
          },
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const Key('zadDialogSecondary'),
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAuthed = context.watch<SessionStore>().isAuthed;
    // Capture the held address as a non-null local so the overlay's callbacks
    // never dereference the field after it's been cleared (e.g. a fast second
    // tap on "Send now" before the tree rebuilds).
    final pendingAddress = _pendingAddress;
    final pending = _pendingSeconds != null;
    return PopScope(
      canPop: !pending,
      onPopInvokedWithResult: (didPop, _) {
        // Back while the hold is running cancels it (nothing was sent) rather
        // than leaving the page with an order silently queued to fire.
        if (!didPop && pending) _cancelConfirmCountdown();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: ZadColors.ink,
          elevation: 0,
          title: Text(l10n.basketCheckout),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              isAuthed ? _buildBody(context, l10n) : _GuestPrompt(l10n: l10n),
              if (pending && pendingAddress != null)
                _ConfirmCountdownOverlay(
                  seconds: _pendingSeconds!,
                  onSendNow: () => _sendNow(pendingAddress),
                  onCancel: _cancelConfirmCountdown,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n) {
    final cart = context.watch<CartStore>();
    final addressStore = context.watch<AddressStore>();
    final items = cart.items;

    if (items.isEmpty) {
      return Center(
        child: Text(
          l10n.basketEmptyTitle,
          style: const TextStyle(fontSize: 16, color: ZadColors.muted),
        ),
      );
    }

    final selected = _effectiveAddress(addressStore);
    final config = context.watch<AppConfigStore>().config;
    final storeClosed =
        _serverSaysClosed || !config.isStoreOpenAt(widget.clock());

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(ZadSpacing.screenPadding),
            children: [
              _SectionTitle(text: l10n.checkoutDeliveryAddress),
              const SizedBox(height: 10),
              _buildAddressSection(l10n, addressStore, selected),
              const SizedBox(height: ZadSpacing.sectionGap),
              _SectionTitle(text: l10n.checkoutOrderSummary),
              const SizedBox(height: 10),
              _SummaryCard(
                items: items,
                totals: cart.totals,
                l10n: l10n,
                config: config,
              ),
              const SizedBox(height: ZadSpacing.sectionGap),
              _SectionTitle(text: l10n.checkoutPaymentMethod),
              const SizedBox(height: 10),
              const _CodTile(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (storeClosed) ...[
                Container(
                  key: const Key('storeClosedNotice'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF3E1),
                    borderRadius: BorderRadius.circular(ZadRadii.tile),
                  ),
                  child: Row(
                    children: [
                      const Icon(Iconsax.clock, size: 20, color: Color(0xFFB7791F)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _closedMessage(l10n, config),
                          style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              ZadPrimaryButton(
                key: const Key('placeOrderButton'),
                label: l10n.checkoutPlaceOrder,
                loading: _placing,
                onPressed: (selected == null || storeClosed)
                    ? null
                    : () => _startConfirmCountdown(selected),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAddressSection(
    AppLocalizations l10n,
    AddressStore store,
    AddressModel? selected,
  ) {
    if (!store.hydrated && store.busy) {
      // Mirrors the address-list lifecycle: skeleton only while there is
      // no snapshot at all; the manage-addresses link below always works.
      return const SectionSkeleton(height: 76);
    }
    final hydrateFailed = !store.hydrated && store.error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hydrateFailed)
          // The hydrate failed and there is no snapshot to fall back on:
          // without addresses the CTA stays disabled, so surface it with a
          // retry instead of silently rendering an empty section.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: ZadColors.surface,
              borderRadius: BorderRadius.circular(ZadRadii.tile),
            ),
            child: Row(
              children: [
                const Icon(Iconsax.warning_2, size: 20, color: ZadColors.muted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.sectionErrorMessage,
                    style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                  ),
                ),
                TextButton(
                  key: const Key('addressSectionRetryButton'),
                  onPressed: () => store.refresh(),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          )
        else if (store.hydrated && store.addresses.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFDF3E1),
              borderRadius: BorderRadius.circular(ZadRadii.tile),
            ),
            child: Row(
              children: [
                const Icon(Iconsax.warning_2, size: 20, color: Color(0xFFB7791F)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.checkoutNoAddressTitle,
                    style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                  ),
                ),
              ],
            ),
          )
        else
          for (final address in store.addresses)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 10),
              child: _AddressOption(
                address: address,
                l10n: l10n,
                selected: address.name == selected?.name,
                onTap: () => setState(() => _selectedAddress = address.name),
              ),
            ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('manageAddressesButton'),
            onPressed: () => Navigator.pushNamed(context, '/addresses'),
            icon: const Icon(Iconsax.add, size: 18),
            label: Text(l10n.checkoutManageAddresses),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: ZadColors.ink,
      ),
    );
  }
}

/// One selectable address card — radio-style, default address preselected.
class _AddressOption extends StatelessWidget {
  const _AddressOption({
    required this.address,
    required this.l10n,
    required this.selected,
    required this.onTap,
  });

  final AddressModel address;
  final AppLocalizations l10n;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = [
      address.addressLine,
      address.city,
    ].where((part) => part.isNotEmpty).join(', ');
    return InkWell(
      key: Key('addressOption-${address.name}'),
      borderRadius: BorderRadius.circular(ZadRadii.tile),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? ZadColors.paleGreen : ZadColors.surface,
          borderRadius: BorderRadius.circular(ZadRadii.tile),
          border: Border.all(
            color: selected ? ZadColors.primary : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? ZadColors.primary : ZadColors.muted,
            ),
            const SizedBox(width: 12),
            Icon(addressLabelIcon(address.label), size: 20, color: ZadColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizedAddressLabel(l10n, address.label),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ZadColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    details,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: ZadColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The cart's lines + totals, read-only (edits happen back in the basket).
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.items,
    required this.totals,
    required this.l10n,
    required this.config,
  });

  final List<CartLineView> items;
  final CartTotals totals;
  final AppLocalizations l10n;
  final AppConfig config;

  String _qtyLabel(CartLineView line) {
    if (line.soldByWeight) {
      return formatWeightGrams(
        line.qty * 1000,
        gramUnit: l10n.unitGram,
        kgUnit: l10n.unitKg,
      );
    }
    return '×${line.qty.round()}';
  }

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final deliveryFee = config.deliveryFeeFor(totals.netTotal);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
      ),
      child: Column(
        children: [
          for (final line in items)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      line.nameFor(languageCode),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _qtyLabel(line),
                    style: const TextStyle(fontSize: 12, color: ZadColors.muted),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatPrice(line.lineTotal, languageCode),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ZadColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.basketSubtotal,
                style: const TextStyle(fontSize: 13, color: ZadColors.muted),
              ),
              Text(
                formatPrice(totals.netTotal, languageCode),
                style: const TextStyle(fontSize: 13, color: ZadColors.ink),
              ),
            ],
          ),
          if (config.hasDeliveryFee) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.checkoutDelivery,
                  style: const TextStyle(fontSize: 13, color: ZadColors.muted),
                ),
                Text(
                  deliveryFee > 0
                      ? formatPrice(deliveryFee, languageCode)
                      : l10n.checkoutDeliveryFree,
                  style: const TextStyle(fontSize: 13, color: ZadColors.ink),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.basketTotal,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ZadColors.ink,
                ),
              ),
              Text(
                formatPrice(totals.netTotal + deliveryFee, languageCode),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: ZadColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one (fixed) payment method — cash on delivery (PRD MVP scope).
class _CodTile extends StatelessWidget {
  const _CodTile();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
        border: Border.all(color: ZadColors.primary),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.money_3, size: 22, color: ZadColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.checkoutCashOnDelivery,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ZadColors.ink,
              ),
            ),
          ),
          const Icon(Iconsax.tick_circle, size: 20, color: ZadColors.primary),
        ],
      ),
    );
  }
}

/// Defence in depth for deep links — normal entry (the basket CTA) is
/// already gated by `ensureLoggedIn`.
class _GuestPrompt extends StatelessWidget {
  const _GuestPrompt({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.bag_2, size: 48, color: ZadColors.muted),
            const SizedBox(height: 16),
            Text(
              l10n.authLoginRequiredTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ZadColors.ink,
              ),
            ),
            const SizedBox(height: 20),
            ZadPrimaryButton(
              label: l10n.authLoginButton,
              onPressed: () => Navigator.pushNamed(context, '/auth/login'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The post-"Place Order" confirm hold: a focused overlay with a live
/// countdown ring, in the app's dialog language (white card, 28px radius, soft
/// shadow, primary + secondary actions). The order is held client-side while
/// this is shown — "Send now" places it immediately, "Cancel & edit" discards
/// the hold (nothing was sent), and it auto-sends when the ring reaches zero.
class _ConfirmCountdownOverlay extends StatelessWidget {
  const _ConfirmCountdownOverlay({
    required this.seconds,
    required this.onSendNow,
    required this.onCancel,
  });

  final int seconds;
  final VoidCallback onSendNow;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final total = kOrderCancelWindow.inSeconds;
    final progress = total == 0 ? 0.0 : seconds / total;
    return Positioned.fill(
      key: const Key('confirmCountdownOverlay'),
      child: ColoredBox(
        // A scrim over the checkout catches taps so the page can't be edited
        // mid-hold — the only ways out are the two explicit actions.
        color: ZadColors.scrim,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Material(
              color: ZadColors.white,
              elevation: ZadElevation.dialog,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(ZadRadii.dialog),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: l10n.checkoutSendingIn(seconds),
                        child: SizedBox(
                          width: 84,
                          height: 84,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 84,
                                height: 84,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 5,
                                  backgroundColor: ZadColors.surface,
                                  valueColor: const AlwaysStoppedAnimation(
                                    ZadColors.primary,
                                  ),
                                ),
                              ),
                              Text(
                                '$seconds',
                                key: const Key('confirmCountdownSeconds'),
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                  color: ZadColors.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        l10n.checkoutConfirmingTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: ZadColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.checkoutConfirmingSubtitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: ZadColors.muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ZadPrimaryButton(
                          key: const Key('confirmSendNowButton'),
                          label: l10n.checkoutSendNow,
                          onPressed: onSendNow,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        key: const Key('confirmCancelButton'),
                        onPressed: onCancel,
                        child: Text(
                          l10n.checkoutCancelAndEdit,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: ZadColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
