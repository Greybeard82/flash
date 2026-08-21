import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../repositories/settings_repository.dart';
import '../services/settings_notifier.dart';
import 'bubble_panel.dart';

/// Quick settings panel: theme and Newspaper mode.
///
/// The theme options are System / Light / Dark — the app's three [ThemeMode]
/// values. Nothing in this app distinguishes a true black/AMOLED mode from
/// dark (the dark theme's background is `darkBg`, #0D1B2A, a navy rather than
/// black), so "black" is presented as Dark rather than implying a fourth mode
/// that does not exist.
///
/// Newspaper mode already overrides the theme choice app-wide — `app.dart`
/// forces `ThemeMode.light` and the Newspaper palette whenever it is on, and
/// the Settings screen already greys out its own theme selector to match. This
/// panel reflects that same rule rather than inventing a second one.
class QuickSettingsBubble extends StatefulWidget {
  final AppSettings initial;

  /// Applies the theme immediately, ahead of the DB write. Supplied by the
  /// host screen because the live theme state lives above this widget.
  final ValueChanged<String>? onThemeChanged;

  /// Applies Newspaper mode immediately, same reason.
  final ValueChanged<bool>? onNewspaperChanged;

  const QuickSettingsBubble({
    super.key,
    required this.initial,
    this.onThemeChanged,
    this.onNewspaperChanged,
  });

  @override
  State<QuickSettingsBubble> createState() => _QuickSettingsBubbleState();
}

class _QuickSettingsBubbleState extends State<QuickSettingsBubble> {
  final _repo = SettingsRepository();

  late String _theme;
  late bool _newspaper;
  late bool _markReadOnScroll;

  @override
  void initState() {
    super.initState();
    _theme = widget.initial.theme;
    _newspaper = widget.initial.newspaperMode;
    _markReadOnScroll = widget.initial.markReadOnScroll;
  }

  Future<void> _setTheme(String value) async {
    setState(() => _theme = value);
    widget.onThemeChanged?.call(value);
    await _repo.set('theme', value);
    SettingsNotifier.instance.settingsChanged();
  }

  Future<void> _setNewspaper(bool value) async {
    setState(() => _newspaper = value);
    widget.onNewspaperChanged?.call(value);
    await _repo.set('newspaper_mode', value.toString());
    SettingsNotifier.instance.settingsChanged();
  }

  /// No `onChanged` callback to the host: FeedScreen already re-applies its
  /// reading settings whenever [SettingsNotifier] fires, so notifying is
  /// enough — unlike theme and Newspaper mode, whose live state lives above
  /// this widget in `app.dart` and needs the extra hand-off.
  Future<void> _setMarkReadOnScroll(bool value) async {
    setState(() => _markReadOnScroll = value);
    await _repo.set('mark_read_on_scroll', value.toString());
    SettingsNotifier.instance.settingsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        BubblePanelHeader(
          icon: Icons.tune_rounded,
          title: l10n.quickSettingsTitle,
        ),
        const SizedBox(height: 4),

        // Greyed out while Newspaper mode is on, because Newspaper mode
        // overrides the theme choice entirely.
        Opacity(
          opacity: _newspaper ? 0.4 : 1.0,
          child: IgnorePointer(
            ignoring: _newspaper,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.theme, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'system', label: Text(l10n.themeSystem)),
                    ButtonSegment(value: 'light', label: Text(l10n.themeLight)),
                    ButtonSegment(value: 'dark', label: Text(l10n.themeDark)),
                  ],
                  selected: {_theme},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setTheme(s.first),
                ),
              ],
            ),
          ),
        ),
        if (_newspaper)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.newspaperModeOverridesTheme,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),

        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.newspaperMode, style: theme.textTheme.bodyMedium),
          subtitle: Text(
            l10n.newspaperModeSubtitle,
            style: theme.textTheme.labelSmall,
          ),
          value: _newspaper,
          onChanged: _setNewspaper,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.markReadOnScroll, style: theme.textTheme.bodyMedium),
          subtitle: Text(
            l10n.markReadOnScrollSubtitle,
            style: theme.textTheme.labelSmall,
          ),
          value: _markReadOnScroll,
          onChanged: _setMarkReadOnScroll,
        ),
      ],
    );
  }
}
