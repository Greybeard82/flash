import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../repositories/settings_repository.dart';
import '../services/settings_notifier.dart';
import 'bubble_panel.dart';

/// Filter panel: how many articles to keep per feed, and how far back to keep
/// them.
///
/// Both sliders write the same two settings the Settings screen already edits
/// (`article_limit`, `cleanup_age_days`) through the same repository, and ping
/// [SettingsNotifier] exactly as `settings_screen.dart` does — so the feed
/// picks the change up live rather than through a second, parallel path.
class FilterBubble extends StatefulWidget {
  final AppSettings initial;

  const FilterBubble({super.key, required this.initial});

  /// 20–150 in steps of 10. Thirteen divisions, not fourteen: a Slider's
  /// `divisions` counts intervals, so (150 − 20) / 13 = 10 exactly. Fourteen
  /// would land on 9.29-unit steps and never sit on a round number.
  static const double minArticles = 20;
  static const double maxArticles = 150;
  static const int articleDivisions = 13;

  /// 2–15 days in steps of 1 — thirteen intervals again. A step of 10 would be
  /// meaningless across a 13-day span; whole days is the only sensible unit
  /// here, and matches how the Settings screen's stepper already moves.
  static const double minDays = 2;
  static const double maxDays = 15;
  static const int dayDivisions = 13;

  @override
  State<FilterBubble> createState() => _FilterBubbleState();
}

class _FilterBubbleState extends State<FilterBubble> {
  final _repo = SettingsRepository();

  late double _articles;
  late double _days;
  late String _sortOrder;

  @override
  void initState() {
    super.initState();
    // Clamp on the way in: the Settings screen's dropdown offers values well
    // outside this slider's range (500, "unlimited"), and a Slider asserts if
    // handed a value outside min..max.
    _articles = widget.initial.articleLimit
        .toDouble()
        .clamp(FilterBubble.minArticles, FilterBubble.maxArticles);
    _days = widget.initial.cleanupAgeDays
        .toDouble()
        .clamp(FilterBubble.minDays, FilterBubble.maxDays);
    _sortOrder = widget.initial.articleSortOrder;
  }

  Future<void> _setSortOrder(String value) async {
    setState(() => _sortOrder = value);
    await _repo.set('article_sort_order', value);
    SettingsNotifier.instance.settingsChanged();
  }

  /// Persist on release rather than on every drag frame — a drag emits dozens
  /// of values and each one would otherwise be a DB write plus an app-wide
  /// notify.
  Future<void> _persist(String key, int value) async {
    await _repo.set(key, value.toString());
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
          title: l10n.filterBubbleTitle,
        ),
        const SizedBox(height: 4),
        _SliderRow(
          label: l10n.maxArticlesPerFeed,
          valueLabel: l10n.articlesCount(_articles.round()),
          value: _articles,
          min: FilterBubble.minArticles,
          max: FilterBubble.maxArticles,
          divisions: FilterBubble.articleDivisions,
          onChanged: (v) => setState(() => _articles = v),
          onChangeEnd: (v) => _persist('article_limit', v.round()),
        ),
        const SizedBox(height: 12),
        _SliderRow(
          label: l10n.articleAgeFilter,
          valueLabel: l10n.daysCount(_days.round()),
          value: _days,
          min: FilterBubble.minDays,
          max: FilterBubble.maxDays,
          divisions: FilterBubble.dayDivisions,
          onChanged: (v) => setState(() => _days = v),
          onChangeEnd: (v) => _persist('cleanup_age_days', v.round()),
        ),
        const SizedBox(height: 14),
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
        const SizedBox(height: 10),
        Text(
          l10n.filterBubbleFootnote,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium),
            ),
            Text(
              valueLabel,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          // Built-in discrete stops — the slider can only rest on a division,
          // so no custom drag handling is needed to make it snap.
          divisions: divisions,
          label: valueLabel,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}
