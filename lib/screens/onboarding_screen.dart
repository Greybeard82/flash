import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../repositories/settings_repository.dart';

class OnboardingScreen extends StatelessWidget {
  /// Called when the user finishes onboarding. The shell uses this to
  /// switch to the Feeds tab so they can add their first feed immediately.
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  Future<void> _finish(BuildContext context) async {
    await SettingsRepository().set('onboarding_complete', 'true');
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),

              // Icon
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.bolt_rounded,
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
              const SizedBox(height: 48),

              // Feature bullets
              _Bullet(
                icon: Icons.rss_feed_rounded,
                text: l10n.onboardingBullet1,
                colorScheme: colorScheme,
                theme: theme,
              ),
              const SizedBox(height: 16),
              _Bullet(
                icon: Icons.auto_awesome_rounded,
                text: l10n.onboardingBullet2,
                colorScheme: colorScheme,
                theme: theme,
              ),
              const SizedBox(height: 16),
              _Bullet(
                icon: Icons.shield_outlined,
                text: l10n.onboardingBullet3,
                colorScheme: colorScheme,
                theme: theme,
              ),

              const Spacer(flex: 3),

              FilledButton(
                onPressed: () => _finish(context),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  l10n.addAFeedButton,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;
  final ColorScheme colorScheme;
  final ThemeData theme;

  const _Bullet({
    required this.icon,
    required this.text,
    required this.colorScheme,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: colorScheme.onSecondaryContainer),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
