import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../repositories/settings_repository.dart';
import '../services/settings_notifier.dart';
import '../theme/app_theme.dart';
import 'bubble_panel.dart';

/// The five palette keys (values stored under `color_palette`), in the order
/// the picker lists them.
const List<String> kPaletteKeys = ['green', 'blue', 'orange', 'red', 'teal_orange'];

String _paletteLabel(AppLocalizations l10n, String key) => switch (key) {
      'green' => l10n.paletteGreen,
      'blue' => l10n.paletteBlue,
      'orange' => l10n.paletteOrange,
      'red' => l10n.paletteRed,
      'teal_orange' => l10n.paletteTealOrange,
      _ => key,
    };

/// Quick settings panel: theme, color palette, and Newspaper mode.
///
/// The theme options are System / Light / Dark — the app's three [ThemeMode]
/// values. Nothing in this app distinguishes a true black/AMOLED mode from
/// dark (every palette's dark background is a generated tonal surface, not
/// pure black), so "black" is presented as Dark rather than implying a
/// fourth mode that does not exist.
///
/// Newspaper mode already overrides the theme *and* palette choice app-wide
/// — `app.dart` forces `ThemeMode.light` and the Newspaper palette whenever
/// it is on, and the Settings screen already greys out its own theme
/// selector to match. This panel reflects that same rule rather than
/// inventing a second one — the palette picker lives inside the same
/// greyed-out block as the theme selector, since a palette choice is equally
/// meaningless while Newspaper mode is overriding it.
class QuickSettingsBubble extends StatefulWidget {
  final AppSettings initial;

  /// Applies the theme immediately, ahead of the DB write. Supplied by the
  /// host screen because the live theme state lives above this widget.
  final ValueChanged<String>? onThemeChanged;

  /// Applies Newspaper mode immediately, same reason.
  final ValueChanged<bool>? onNewspaperChanged;

  /// Applies the color palette immediately, same reason.
  final ValueChanged<String>? onPaletteChanged;

  const QuickSettingsBubble({
    super.key,
    required this.initial,
    this.onThemeChanged,
    this.onNewspaperChanged,
    this.onPaletteChanged,
  });

  @override
  State<QuickSettingsBubble> createState() => _QuickSettingsBubbleState();
}

class _QuickSettingsBubbleState extends State<QuickSettingsBubble> {
  final _repo = SettingsRepository();

  late String _theme;
  late bool _newspaper;
  late String _palette;
  late bool _markReadOnScroll;
  late bool _markAllReadConfirm;

  @override
  void initState() {
    super.initState();
    _theme = widget.initial.theme;
    _newspaper = widget.initial.newspaperMode;
    _palette = widget.initial.colorPalette;
    _markReadOnScroll = widget.initial.markReadOnScroll;
    _markAllReadConfirm = widget.initial.markAllReadConfirm;
  }

  Future<void> _setTheme(String value) async {
    setState(() => _theme = value);
    widget.onThemeChanged?.call(value);
    await _repo.set('theme', value);
    SettingsNotifier.instance.settingsChanged();
  }

  Future<void> _setPalette(String value) async {
    setState(() => _palette = value);
    widget.onPaletteChanged?.call(value);
    await _repo.set('color_palette', value);
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

  /// The only way back on once the dialog's "Don't show again" has turned
  /// it off.
  Future<void> _setMarkAllReadConfirm(bool value) async {
    setState(() => _markAllReadConfirm = value);
    await _repo.set('mark_all_read_confirm', value.toString());
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
                const SizedBox(height: 16),
                Text(l10n.colorPalette, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                // Previewed at the currently active brightness — Theme.of
                // already resolved System/Light/Dark against live OS state by
                // the time this builds, so this is exactly the brightness the
                // person is looking at right now, not a guess.
                ...kPaletteKeys.map((key) => _PaletteRow(
                      selected: _palette == key,
                      label: _paletteLabel(l10n, key),
                      scheme: paletteColorScheme(
                        palette: key,
                        brightness: theme.brightness,
                      ),
                      onTap: () => _setPalette(key),
                    )),
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title:
              Text(l10n.confirmMarkAllRead, style: theme.textTheme.bodyMedium),
          value: _markAllReadConfirm,
          onChanged: _setMarkAllReadConfirm,
        ),
      ],
    );
  }
}

/// One selectable row in the palette picker: a strip previewing the
/// palette's actual generated tones, its name, and a checkmark when selected
/// — colors pulled from the real [ColorScheme] rather than a separate set of
/// preview constants that could drift from what the palette actually renders.
class _PaletteRow extends StatelessWidget {
  final bool selected;
  final String label;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _PaletteRow({
    required this.selected,
    required this.label,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.4),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              _PaletteSwatchStrip(scheme: scheme),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    color: theme.colorScheme.primary, size: 20)
              else
                const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three swatches — primary, secondary, surface — from one palette's
/// generated [ColorScheme], side by side as a single small strip.
class _PaletteSwatchStrip extends StatelessWidget {
  final ColorScheme scheme;

  const _PaletteSwatchStrip({required this.scheme});

  @override
  Widget build(BuildContext context) {
    Widget swatch(Color color) => Container(
          width: 18,
          height: 28,
          color: color,
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch(scheme.primary),
            swatch(scheme.secondary),
            swatch(scheme.surface),
          ],
        ),
      ),
    );
  }
}
