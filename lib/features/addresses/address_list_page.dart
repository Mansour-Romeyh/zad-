import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exceptions.dart';
import '../../core/constants.dart';
import '../../core/errors/user_error.dart';
import '../../core/session/session_store.dart';
import '../../core/stores/address_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/zad_dialog.dart';
import '../../data/address_repository.dart';
import '../../l10n/app_localizations.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/section_state.dart';
import 'address_form_page.dart';
import 'address_label.dart';

/// `/addresses` (PRD F4): the saved-address list — default badge,
/// set-default, edit, delete-with-confirm — plus the Add CTA into
/// [AddressFormPage]. Data comes from [AddressStore]; opening the page
/// re-pulls `address.list` so it never shows a stale book. Guests get a
/// login prompt (addresses are logged-in-only, PRD A3) — normal entry
/// points are already gated, this is defence in depth for deep links.
class AddressListPage extends StatefulWidget {
  const AddressListPage({super.key});

  @override
  State<AddressListPage> createState() => _AddressListPageState();
}

class _AddressListPageState extends State<AddressListPage> {
  @override
  void initState() {
    super.initState();
    // Post-frame: refresh() notifies immediately (busy flip), and other
    // listeners of the store (the home location header) must not be marked
    // dirty while this route's first build is still locked in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AddressStore>().refresh();
    });
  }

  /// Runs a mutation, turning any [ApiException] (including network
  /// failures) into an error SnackBar instead of an unhandled async error.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) {
        showErrorSnackBar(context, e);
      }
    }
  }

  Future<void> _confirmDelete(AddressModel address) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showZadConfirm(
      context,
      title: l10n.addressDeleteTitle,
      message: l10n.addressDeleteMessage,
      confirmLabel: l10n.addressDelete,
      cancelLabel: l10n.cancel,
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (confirmed && mounted) {
      final store = context.read<AddressStore>();
      await _guard(() => store.delete(address.name));
    }
  }

  void _openForm({AddressModel? existing}) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AddressFormPage(existing: existing),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAuthed = context.watch<SessionStore>().isAuthed;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ZadColors.ink,
        elevation: 0,
        title: Text(l10n.addressesTitle),
      ),
      body: SafeArea(
        child: isAuthed ? _buildList(context, l10n) : _GuestPrompt(l10n: l10n),
      ),
      bottomNavigationBar: isAuthed
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(ZadSpacing.screenPadding),
                child: ZadPrimaryButton(
                  key: const Key('addAddressButton'),
                  label: l10n.addressAdd,
                  onPressed: () => _openForm(),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildList(BuildContext context, AppLocalizations l10n) {
    final store = context.watch<AddressStore>();

    // Same lifecycle mapping as the favourites tab: once hydrated, always
    // render data (a background refresh keeps the list on screen instead
    // of flashing a skeleton); until then, skeleton while fetching and the
    // retry prompt on failure.
    final SectionState<List<AddressModel>> state;
    if (store.hydrated) {
      state = SectionState.data(store.addresses);
    } else if (store.error != null && !store.busy) {
      state = SectionState.error(store.error!);
    } else {
      state = const SectionState.loading();
    }

    return AsyncSection<List<AddressModel>>(
      state: state,
      skeleton: const Padding(
        padding: EdgeInsets.all(ZadSpacing.screenPadding),
        child: SectionSkeleton(height: 244),
      ),
      onRetry: store.refresh,
      isEmpty: (addresses) => addresses.isEmpty,
      emptyBuilder: (context) => _EmptyAddresses(l10n: l10n),
      builder: (context, addresses) => ListView.separated(
        padding: const EdgeInsets.all(ZadSpacing.screenPadding),
        itemCount: addresses.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _AddressCard(
          address: addresses[index],
          l10n: l10n,
          onEdit: () => _openForm(existing: addresses[index]),
          onDelete: () => _confirmDelete(addresses[index]),
          onSetDefault: () {
            final store = context.read<AddressStore>();
            _guard(() => store.setDefault(addresses[index].name));
          },
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.l10n,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  final AddressModel address;
  final AppLocalizations l10n;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  @override
  Widget build(BuildContext context) {
    final details = [
      address.addressLine,
      address.city,
    ].where((part) => part.isNotEmpty).join(', ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ZadColors.surface,
        borderRadius: BorderRadius.circular(ZadRadii.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(addressLabelIcon(address.label), color: ZadColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        localizedAddressLabel(l10n, address.label),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: ZadColors.ink,
                        ),
                      ),
                    ),
                    if (address.isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        key: Key('defaultBadge-${address.name}'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: ZadColors.paleGreen,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          l10n.addressDefaultBadge,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: ZadColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: ZadColors.muted),
                ),
                if (!address.isDefault)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: Key('setDefault-${address.name}'),
                      onPressed: onSetDefault,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(l10n.addressSetDefault),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            key: Key('editAddress-${address.name}'),
            onPressed: onEdit,
            icon: const Icon(Iconsax.edit, size: 20, color: ZadColors.ink),
          ),
          IconButton(
            key: Key('deleteAddress-${address.name}'),
            onPressed: onDelete,
            icon: const Icon(Iconsax.trash, size: 20, color: ZadColors.muted),
          ),
        ],
      ),
    );
  }
}

class _EmptyAddresses extends StatelessWidget {
  const _EmptyAddresses({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.location, size: 48, color: ZadColors.muted),
            const SizedBox(height: 16),
            Text(
              l10n.addressesEmptyTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: ZadColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
            const Icon(Iconsax.location, size: 48, color: ZadColors.muted),
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
