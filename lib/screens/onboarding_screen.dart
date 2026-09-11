import 'dart:async';

import 'package:flutter/material.dart';
import '../data/starter_pack.dart';
import '../l10n/app_localizations.dart';
import '../services/starter_pack_service.dart';
import '../widgets/flash_bolt.dart';
import '../widgets/starter_pack_picker.dart';
import '../repositories/settings_repository.dart';

/// First run.
///
/// This screen used to end at a single "Add a feed" button, which dropped the
/// user on Categories with an empty add sheet. Google Play removed the app
/// under the News and Magazines policy on 11 Sep 2026 for exactly that: the
/// reviewer installed it, followed the only button available, and found no
/// news anywhere in the app. Onboarding is therefore no longer an
/// introduction — it is the moment the app has to acquire content, and the
/// primary button now ends with articles on screen rather than with an empty
/// form.
///
/// The three feature bullets are gone. They were the only thing between the
/// tagline and the button, and the space is better spent on the thing the user
/// is actually deciding.
class OnboardingScreen extends StatefulWidget {
  /// Called when the user finishes onboarding.
  ///
  /// [withStarterPack] says which of the two exits was taken, because the
  /// shell has to land them somewhere different: with feeds, the Flash tab now
  /// has something to show; without, Categories is still the only useful
  /// destination.
  final void Function({required bool withStarterPack}) onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late Set<String> _selected = kStarterPack.map((c) => c.id).toSet();

  /// True while the seed is writing. Both buttons go dead: a second tap on
  /// Start reading would seed twice, and Skip would complete onboarding out
  /// from under a write in flight.
  bool _seeding = false;

  Future<void> _startReading() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _seeding = true);

    try {
      final service = StarterPackService();
      final result = await service.addCategories(
        kStarterPack.map((c) => c.id).where(_selected.contains).toList(),
        starterFolderNames(l10n),
      );
      // Deliberately not awaited. Favicons are decoration; the articles are
      // the point, and a dozen HTTP round trips here would be a dozen round
      // trips the user spends looking at onboarding.
      unawaited(service.warmFavicons(result.addedFeeds));

      await SettingsRepository().set('onboarding_complete', 'true');
      if (!mounted) return;
      widget.onDone(withStarterPack: true);
    } catch (_) {
      // Both buttons are disabled while seeding, so a throw that left the
      // flag set would strand the user on the first screen of the app with
      // nothing on it they can press — no feeds, no Skip, no way forward.
      // Re-enabling them is the whole fix: the pack can be retried, and Skip
      // is still there for someone who would rather just get in.
      //
      // Nothing is said about the failure because this screen has no banner
      // and gaining one is not worth it here: the DB write that failed is the
      // same one every other screen depends on, so an app that cannot do it
      // has larger problems than this message would describe.
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _skip() async {
    setState(() => _seeding = true);
    try {
      await SettingsRepository().set('onboarding_complete', 'true');
      if (!mounted) return;
      widget.onDone(withStarterPack: false);
    } catch (_) {
      if (mounted) setState(() => _seeding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final count = starterFeedCount(_selected);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The middle scrolls and the buttons are pinned below it. Five
              // checkbox rows plus the header do not fit under a short phone's
              // keyboard-less viewport, and a primary action that can scroll
              // off the bottom of a first-run screen is the same failure as
              // the empty one this replaces.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 32),

                      // Icon
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: FlashBolt(
                            size: 52,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Title
                      Text(
                        l10n.appTitle,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Tagline
                      Text(
                        l10n.onboardingTagline,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),

                      Text(
                        l10n.onboardingStarterTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.onboardingStarterSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 8),

                      StarterPackPicker(
                        selected: _selected,
                        enabled: !_seeding,
                        onChanged: (next) => setState(() => _selected = next),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),

              FilledButton(
                onPressed: (count == 0 || _seeding) ? null : _startReading,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  l10n.startReadingButton,
                  style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              // The old destination, kept as the quiet option. Someone who
              // already knows which feeds they want should not have to untick
              // five boxes to get past this screen.
              TextButton(
                onPressed: _seeding ? null : _skip,
                child: Text(l10n.skipAddOwnFeedsButton),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
