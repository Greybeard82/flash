import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'flash_bolt.dart';

class EmptyState extends StatelessWidget {
  final VoidCallback onAddFeed;

  /// Opens the starter-pack sheet. The second button here is the whole
  /// remedy for how the app got pulled from Google Play: the reviewer reached
  /// this screen, and the only thing on it sent them to an empty form. Now
  /// one tap fills it.
  final VoidCallback onAddStarterPack;

  const EmptyState({
    super.key,
    required this.onAddFeed,
    required this.onAddStarterPack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlashBolt(
              size: 80,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 24),
            Text(
              l10n.nothingHereYet,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.addFirstFeed,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onAddFeed,
              icon: const Icon(Icons.add),
              label: Text(l10n.addAFeedButton),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 52),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddStarterPack,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(l10n.addStarterPackButton),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(200, 52),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
