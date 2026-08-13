import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/session/session_store.dart';
import '../../core/stores/favourites_store.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../../models/product.dart';
import '../auth/widgets/zad_primary_button.dart';
import '../home/widgets/async_section.dart';
import '../home/widgets/product_card.dart';
import '../home/widgets/section_state.dart';

/// Bottom-nav Favourites tab (PRD F8 wishlist, hosted inside the
/// `HomePage` IndexedStack shell): a 2-column grid of favourite ItemCards
/// reusing [ProductCard] — its heart un-favourites straight from the grid,
/// its Add button adds to the cart — with loading/error/retry/empty states
/// consistent with the home sections. Guests get a login prompt instead
/// (favourites are a logged-in-only feature, PRD A3).
///
/// Data comes from [FavouritesStore]: hydrated at app start/login, and
/// re-pulled by the `HomePage` shell every time this tab is activated.
class FavouritesTab extends StatelessWidget {
  const FavouritesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isAuthed = context.watch<SessionStore>().isAuthed;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ZadSpacing.screenPadding,
              12,
              ZadSpacing.screenPadding,
              0,
            ),
            child: Text(
              l10n.favouritesTitle,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: ZadColors.ink,
              ),
            ),
          ),
          Expanded(
            child: isAuthed ? const _FavouritesBody() : _GuestPrompt(l10n: l10n),
          ),
        ],
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
            const Icon(Iconsax.heart, size: 48, color: ZadColors.muted),
            const SizedBox(height: 16),
            Text(
              l10n.favouritesGuestTitle,
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

class _FavouritesBody extends StatelessWidget {
  const _FavouritesBody();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = context.watch<FavouritesStore>();

    // Map the store's lifecycle onto the shared SectionState machinery:
    // once hydrated, always render data (a background refresh keeps the
    // previous grid on screen instead of flashing a skeleton); until then
    // show the skeleton while fetching and the retry prompt on failure.
    final SectionState<List<Product>> state;
    if (store.hydrated) {
      state = SectionState.data(store.items);
    } else if (store.error != null && !store.busy) {
      state = SectionState.error(store.error!);
    } else {
      state = const SectionState.loading();
    }

    return AsyncSection<List<Product>>(
      state: state,
      // Static skeleton (not a spinner): this tab lives offstage in the
      // IndexedStack shell, and the home sections' skeleton is the house
      // loading style anyway.
      skeleton: const Padding(
        padding: EdgeInsets.all(ZadSpacing.screenPadding),
        child: SectionSkeleton(height: 244),
      ),
      onRetry: store.refresh,
      isEmpty: (items) => items.isEmpty,
      emptyBuilder: (context) => _EmptyFavourites(l10n: l10n),
      builder: (context, items) => GridView.builder(
        padding: const EdgeInsets.all(ZadSpacing.screenPadding),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 14,
          childAspectRatio: 0.62,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) =>
            Center(child: ProductCard(product: items[index])),
      ),
    );
  }
}

class _EmptyFavourites extends StatelessWidget {
  const _EmptyFavourites({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ZadSpacing.screenPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.heart, size: 48, color: ZadColors.muted),
            const SizedBox(height: 16),
            Text(
              l10n.favouritesEmptyTitle,
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
