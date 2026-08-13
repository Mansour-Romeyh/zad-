import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../orders/order_status_chip.dart';

/// Post-checkout confirmation (PRD E3): the new order's number and its
/// fulfilment status ("بانتظار التجهيز" — Pending Assignment), with CTAs to
/// the orders list or back home. Pushed with `pushReplacement` over the
/// checkout page, so back never returns to a spent checkout attempt.
class OrderSuccessPage extends StatelessWidget {
  const OrderSuccessPage({required this.orderName, required this.status, super.key});

  /// The Sales Order name from `place_order` (e.g. `SAL-ORD-2026-00042`).
  final String orderName;

  /// The order's fulfilment status (`Pending Assignment` right after
  /// checkout — but an idempotent replay may return a further-along one).
  final String status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: const BoxDecoration(
                          color: ZadColors.paleGreen,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Iconsax.tick_circle,
                          size: 52,
                          color: ZadColors.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        l10n.orderSuccessTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: ZadColors.ink,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.orderSuccessNumber(orderName),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: ZadColors.muted),
                      ),
                      const SizedBox(height: 14),
                      OrderStatusChip(status: status),
                    ],
                  ),
                ),
              ),
              ZadPrimaryButton(
                key: const Key('successViewOrdersButton'),
                label: l10n.orderSuccessViewOrders,
                onPressed: () =>
                    Navigator.pushReplacementNamed(context, '/orders'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  key: const Key('successGoHomeButton'),
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/home',
                    (route) => false,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZadColors.primary,
                    side: const BorderSide(color: ZadColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZadRadii.button),
                    ),
                  ),
                  child: Text(
                    l10n.orderSuccessGoHome,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
