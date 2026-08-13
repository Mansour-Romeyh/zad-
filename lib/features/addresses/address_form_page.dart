import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/location/location_service.dart';
import '../../core/stores/address_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/zad_snack.dart';
import '../../data/address_repository.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../auth/widgets/zad_text_field.dart';
import 'address_label.dart';

/// Create/edit address form (PRD F4/A3): label chips (منزل/عمل/أخرى),
/// address line + city, and "استخدام موقعي الحالي" via the injectable
/// [LocationService] — a denied permission (or any other location failure)
/// surfaces a message and leaves manual entry fully usable. A captured
/// location resolves its delivery zone immediately (inline banner); saving
/// surfaces the server's zone result (coverage name or outside-coverage
/// warning — the address is saved either way, checkout blocks later,
/// PRD E5).
class AddressFormPage extends StatefulWidget {
  const AddressFormPage({this.existing, super.key});

  /// When set, the form edits this address instead of creating a new one.
  final AddressModel? existing;

  @override
  State<AddressFormPage> createState() => _AddressFormPageState();
}

class _AddressFormPageState extends State<AddressFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _lineController = TextEditingController(
    text: widget.existing?.addressLine ?? '',
  );
  late final TextEditingController _cityController = TextEditingController(
    text: widget.existing?.city ?? '',
  );

  late String _label = widget.existing?.label ?? AddressLabels.home;

  // (0, 0) is the backend's "no coordinates" sentinel — treat it as unset
  // so editing such an address doesn't pretend a location was captured.
  late double? _lat =
      (widget.existing?.hasCoordinates ?? false) ? widget.existing!.lat : null;
  late double? _lng =
      (widget.existing?.hasCoordinates ?? false) ? widget.existing!.lng : null;

  ZoneResult? _zone;
  bool _locating = false;
  bool _submitting = false;

  @override
  void dispose() {
    _lineController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  /// Permission flow + fix via the injected [LocationService]. Every
  /// failure is non-blocking: a message plus untouched manual fields.
  Future<void> _useCurrentLocation() async {
    final l10n = AppLocalizations.of(context);
    final locationService = context.read<LocationService>();
    final repository = context.read<AddressRepository>();
    setState(() => _locating = true);
    try {
      final location = await locationService.getCurrent();
      // Instant coverage feedback (PRD E5, informational) — a failed
      // resolve just skips the banner, never the capture.
      ZoneResult? zone;
      try {
        zone = await repository.resolveZone(location.lat, location.lng);
      } catch (_) {
        zone = null;
      }
      if (!mounted) return;
      setState(() {
        _lat = location.lat;
        _lng = location.lng;
        _zone = zone;
      });
    } on LocationException catch (e) {
      if (!mounted) return;
      showZadSnack(
        context,
        switch (e.reason) {
          LocationFailureReason.permissionDenied => l10n.addressLocationDenied,
          // Permanently blocked: re-asking is futile — only the system
          // settings can unblock it, so say that instead of the generic copy.
          LocationFailureReason.permissionDeniedForever =>
            l10n.addressLocationDeniedForever,
          LocationFailureReason.serviceDisabled ||
          LocationFailureReason.unavailable =>
            l10n.addressLocationUnavailable,
        },
        variant: ZadSnackVariant.warning,
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final l10n = AppLocalizations.of(context);
    final store = context.read<AddressStore>();
    setState(() => _submitting = true);
    try {
      final existing = widget.existing;
      final saved = existing == null
          ? await store.create(
              label: _label,
              addressLine: _lineController.text.trim(),
              city: _cityController.text.trim(),
              lat: _lat,
              lng: _lng,
            )
          : await store.update(
              existing.name,
              label: _label,
              addressLine: _lineController.text.trim(),
              city: _cityController.text.trim(),
              lat: _lat,
              lng: _lng,
            );
      if (!mounted) return;
      // Zone result surface (PRD E5): only meaningful when real
      // coordinates were saved — a manual-only address has nothing to
      // resolve, so it gets the plain confirmation. Shown on the root
      // messenger, so it survives the pop back to the list.
      final String message;
      final ZadSnackVariant variant;
      if (!saved.hasCoordinates && _lat == null) {
        message = l10n.addressSaved;
        variant = ZadSnackVariant.success;
      } else if (saved.outsideCoverage) {
        message = l10n.addressOutsideCoverage;
        variant = ZadSnackVariant.warning;
      } else if (saved.zoneName != null) {
        message = l10n.addressZoneCovered(saved.zoneName!);
        variant = ZadSnackVariant.success;
      } else {
        message = l10n.addressSaved;
        variant = ZadSnackVariant.success;
      }
      showZadSnack(context, message, variant: variant);
      Navigator.pop(context, saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e);
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEdit = widget.existing != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        title: Text(isEdit ? l10n.addressEditTitle : l10n.addressNewTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ZadSpacing.screenPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  children: [
                    for (final label in AddressLabels.all)
                      ChoiceChip(
                        key: Key('labelChip-$label'),
                        label: Text(localizedAddressLabel(l10n, label)),
                        selected: _label == label,
                        selectedColor: ZadColors.paleGreen,
                        onSelected: (_) => setState(() => _label = label),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                // Address line + city are optional — an address can be
                // defined by a captured GPS location (or just a label) alone.
                ZadTextField(
                  key: const Key('addressLineField'),
                  controller: _lineController,
                  hintText: l10n.addressLineLabel,
                ),
                const SizedBox(height: 16),
                ZadTextField(
                  key: const Key('addressCityField'),
                  controller: _cityController,
                  hintText: l10n.addressCityLabel,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  key: const Key('useCurrentLocationButton'),
                  onPressed: _locating ? null : _useCurrentLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Iconsax.gps, size: 20),
                  label: Text(
                    _lat != null
                        ? l10n.addressLocationCaptured
                        : l10n.addressUseCurrentLocation,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ZadColors.primary,
                    side: const BorderSide(color: ZadColors.primary),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZadRadii.button),
                    ),
                  ),
                ),
                if (_zone != null) ...[
                  const SizedBox(height: 16),
                  _ZoneBanner(zone: _zone!, l10n: l10n),
                ],
                const SizedBox(height: 24),
                ZadPrimaryButton(
                  key: const Key('saveAddressButton'),
                  label: l10n.addressSave,
                  onPressed: _save,
                  loading: _submitting,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline coverage feedback under the location button: zone name when the
/// captured point is covered, a warning when it is outside coverage.
class _ZoneBanner extends StatelessWidget {
  const _ZoneBanner({required this.zone, required this.l10n});

  final ZoneResult zone;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final covered = zone.covered;
    return Container(
      key: const Key('zoneBanner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: covered ? ZadColors.paleGreen : const Color(0xFFFDF3E1),
        borderRadius: BorderRadius.circular(ZadRadii.button),
      ),
      child: Row(
        children: [
          Icon(
            covered ? Iconsax.tick_circle : Iconsax.warning_2,
            size: 20,
            color: covered ? ZadColors.primary : const Color(0xFFB7791F),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              covered
                  ? l10n.addressZoneCovered(zone.zoneName!)
                  : l10n.addressOutsideCoverage,
              style: const TextStyle(fontSize: 13, color: ZadColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
