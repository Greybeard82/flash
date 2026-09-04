import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../repositories/settings_repository.dart';
import '../services/settings_notifier.dart';
import 'bubble_panel.dart';

/// Filter panel: sort order, read visibility, and the two keyword tools.
///
/// The article-count and article-age sliders that used to live here were
/// removed; this panel's job is now the things a reader reaches for while
/// looking at the feed: how it's sorted, whether read articles stay visible,
/// and the keyword blocklist/alerts that shape what's in it. `article_limit`
/// and `cleanup_age_days` still exist on [AppSettings] and still govern
/// fetching/cleanup, but with the sliders gone there is currently no UI
/// control for either value anywhere in the app.
class FilterBubble extends StatefulWidget {
  final AppSettings initial;

  /// Reopens this bubble as the keyword blocklist panel, anchored to the same
  /// button. Owned by the caller (`feed_screen.dart`) rather than done here
  /// directly: by the time the dismiss animation this row starts has
  /// finished, this widget's own context is unmounted, so the reopen has to
  /// be a still-alive object's job, not this one's.
  final VoidCallback onOpenBlocklist;

  /// As [onOpenBlocklist], for the keyword alerts panel.
  final VoidCallback onOpenAlerts;

  const FilterBubble({
    super.key,
    required this.initial,
    required this.onOpenBlocklist,
    required this.onOpenAlerts,
  });

  @override
  State<FilterBubble> createState() => _FilterBubbleState();
}

class _FilterBubbleState extends State<FilterBubble> {
  final _repo = SettingsRepository();

  late String _sortOrder;
  late bool _showRead;

  @override
  void initState() {
    super.initState();
    _sortOrder = widget.initial.articleSortOrder;
    _showRead = widget.initial.showRead;
  }

  void _setSortOrder(String value) => setState(() => _sortOrder = value);

  /// Nothing here is written until Apply. Dragging a slider is exploratory —
  /// persisting on release meant a drag past 20 could re-query the feed
  /// several times on the way to the value the user actually wanted.
  bool get _hasPendingChanges =>
      _sortOrder != widget.initial.articleSortOrder ||
      _showRead != widget.initial.showRead;

  Future<void> _apply() async {
    await _repo.set('article_sort_order', _sortOrder);
    await _repo.set('show_read', _showRead.toString());
    // One notify for the whole set, so the feed re-queries once.
    SettingsNotifier.instance.settingsChanged();
    if (mounted) await BubblePanelScope.maybeOf(context)?.dismiss();
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
          title: l10n.filterBubbleTitle,
        ),
        const SizedBox(height: 4),
        Text(l10n.articleOrder, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: kSortNewestFirst,
              icon: const Icon(Icons.arrow_downward_rounded, size: 16),
              label: Text(l10n.newestFirst),
            ),
            ButtonSegment(
              value: kSortOldestFirst,
              icon: const Icon(Icons.arrow_upward_rounded, size: 16),
              label: Text(l10n.oldestFirst),
            ),
          ],
          selected: {_sortOrder},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _setSortOrder(s.first),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _showRead,
          title: Text(l10n.showRead, style: theme.textTheme.bodyMedium),
          subtitle: Text(
            l10n.showReadSubtitle,
            style: theme.textTheme.labelSmall,
          ),
          onChanged: (v) => setState(() => _showRead = v),
        ),
        const SizedBox(height: 6),
        const Divider(height: 1),
        _ToolRow(
          icon: Icons.block_rounded,
          label: l10n.keywordBlocklist,
          subtitle: l10n.keywordBlocklistSubtitle,
          onTap: () async {
            await BubblePanelScope.maybeOf(context)?.dismiss();
            widget.onOpenBlocklist();
          },
        ),
        const Divider(height: 1),
        _ToolRow(
          icon: Icons.notifications_active_outlined,
          label: l10n.keywordAlerts,
          subtitle: l10n.keywordAlertsSubtitle,
          onTap: () async {
            await BubblePanelScope.maybeOf(context)?.dismiss();
            widget.onOpenAlerts();
          },
        ),
        const SizedBox(height: 10),
        Text(
          l10n.filterBubbleFootnote,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 14),
        // Disabled until something actually differs, so the button doubles as
        // an indicator of whether there is anything pending.
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _hasPendingChanges ? _apply : null,
            child: Text(l10n.apply),
          ),
        ),
      ],
    );
  }
}

/// A tappable row for one of the two keyword tools, styled to sit inside
/// this bubble rather than as a Settings-style ListTile.
class _ToolRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
