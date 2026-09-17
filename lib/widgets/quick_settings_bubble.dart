import 'package:flutter/material.dart';
import 'flash_switch.dart';

import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../repositories/settings_repository.dart';
import '../screens/settings_screen.dart';
import '../services/settings_notifier.dart';
import '../services/summary_formatter.dart'
    show kSummaryLengthShort, kSummaryLengthStandard, kSummaryLengthDetailed;
import '../services/unread_badge_service.dart';
import 'bubble_panel.dart';

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
  late bool _markAllReadConfirm;
  late bool _iconBadge;
  late String _summaryLength;

  @override
  void initState() {
    super.initState();
    _theme = widget.initial.theme;
    _newspaper = widget.initial.newspaperMode;
    _markReadOnScroll = widget.initial.markReadOnScroll;
    _markAllReadConfirm = widget.initial.markAllReadConfirm;
    _iconBadge = widget.initial.unreadBadgeNotification;
    _summaryLength = widget.initial.summaryLength;
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

  /// The only way back on once the dialog's "Don't show again" has turned
  /// it off.
  Future<void> _setMarkAllReadConfirm(bool value) async {
    setState(() => _markAllReadConfirm = value);
    await _repo.set('mark_all_read_confirm', value.toString());
    SettingsNotifier.instance.settingsChanged();
  }

  /// Turning it off takes the notification down now rather than at whatever
  /// point the unread count next happens to change.
  /// How long AI summaries should be. Lives here rather than in the full
  /// Settings screen because it is the kind of thing you change while
  /// reading — the same category as theme and palette, not a decide-once
  /// preference like the built-in viewer toggle.
  Future<void> _setSummaryLength(String value) async {
    setState(() => _summaryLength = value);
    await _repo.set('summary_length', value);
    SettingsNotifier.instance.settingsChanged();
  }

  Future<void> _setIconBadge(bool value) async {
    setState(() => _iconBadge = value);
    await _repo.set(kUnreadBadgeSettingKey, value.toString());
    await UnreadBadgeService.instance.onSettingChanged(enabled: value);
    SettingsNotifier.instance.settingsChanged();
  }

  /// Dismisses the bubble, then pushes Settings.
  ///
  /// The push uses the *navigator* captured before the dismiss, not this
  /// widget's context afterwards. Dismissing tears this subtree down, so
  /// reaching for `context` on the far side is reading a context that may
  /// already be unmounted — the same hazard `_reopenAsKeywordPanel` documents
  /// in feed_screen.dart, where the fix is likewise to do the work from
  /// something that outlives the panel.
  void _openFullSettings() {
    final navigator = Navigator.of(context);
    BubblePanelScope.maybeOf(context)?.dismiss();
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
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
                Text(l10n.summaryLength, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: kSummaryLengthShort,
                        label: Text(l10n.summaryShort)),
                    ButtonSegment(
                        value: kSummaryLengthStandard,
                        label: Text(l10n.summaryStandard)),
                    ButtonSegment(
                        value: kSummaryLengthDetailed,
                        label: Text(l10n.summaryDetailed)),
                  ],
                  selected: {_summaryLength},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setSummaryLength(s.first),
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
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),

        const SizedBox(height: 12),
        FlashSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.newspaperMode, style: theme.textTheme.bodyMedium),
          subtitle: Text(
            l10n.newspaperModeSubtitle,
            style: theme.textTheme.labelSmall,
          ),
          value: _newspaper,
          onChanged: _setNewspaper,
        ),
        FlashSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.markReadOnScroll, style: theme.textTheme.bodyMedium),
          subtitle: Text(
            l10n.markReadOnScrollSubtitle,
            style: theme.textTheme.labelSmall,
          ),
          value: _markReadOnScroll,
          onChanged: _setMarkReadOnScroll,
        ),
        FlashSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title:
              Text(l10n.confirmMarkAllRead, style: theme.textTheme.bodyMedium),
          value: _markAllReadConfirm,
          onChanged: _setMarkAllReadConfirm,
        ),
        // No subtitle, deliberately. What the badge looks like depends on the
        // launcher — a number on One UI, a dot on a Pixel — and explaining
        // that here made a one-line toggle carry a paragraph about vendor
        // launcher behaviour that nobody flicking a switch needs.
        FlashSwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.iconBadge, style: theme.textTheme.bodyMedium),
          value: _iconBadge,
          onChanged: _setIconBadge,
        ),

        const Divider(height: 20),
        // The only way to the full Settings screen. It is reached from this
        // panel rather than the nav bar, and this panel opens from all four
        // top-level screens, so the route in is the same wherever you are.
        InkWell(
          onTap: _openFullSettings,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.settings_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(l10n.moreSettings,
                      style: theme.textTheme.bodyMedium),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
