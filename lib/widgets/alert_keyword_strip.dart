import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// The keyword filter row that sits under the category pills while the Alerts
/// tab is selected: All, one chip per configured alert keyword, and a way into
/// the management panel.
///
/// It is shown only on that tab. On any other tab it would be filtering
/// something that isn't on screen.
class AlertKeywordStrip extends StatelessWidget {
  /// Total height including the padding, so callers can reserve space for the
  /// strip without measuring it.
  static const double stripHeight = 44.0;

  /// Live entry count per keyword, straight from
  /// `AlertMatchRepository.countsByKeyword()` — which includes configured
  /// keywords that have matched nothing, so those chips render "(0)" rather
  /// than disappearing and making a keyword the user just added look unsaved.
  final Map<String, int> countsByKeyword;

  /// Cards on the tab in total, which is **not** the sum of [countsByKeyword].
  ///
  /// An article that hit three keywords contributes to three of those counts
  /// and is one card. Summing them would show "All (12)" above a list of four,
  /// so the distinct-entry count is passed in rather than derived here.
  final int totalEntryCount;

  /// The keyword being filtered on, or null for All.
  final String? selectedKeyword;

  final ValueChanged<String?> onSelected;
  final VoidCallback onManageKeywords;

  const AlertKeywordStrip({
    super.key,
    required this.countsByKeyword,
    required this.totalEntryCount,
    required this.selectedKeyword,
    required this.onSelected,
    required this.onManageKeywords,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Alphabetical, so a chip does not jump position the moment its count
    // changes underneath the user's thumb.
    final keywords = countsByKeyword.keys.toList()..sort();

    return SizedBox(
      height: stripHeight,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Horizontal only. The 8dp above and below each chip is applied inside
        // the chip's own InkWell instead, so it counts toward the tap target
        // rather than forming a dead margin around it.
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _StripChip(
              label: l10n.alertsFilterAll,
              count: totalEntryCount,
              isSelected: selectedKeyword == null,
              onTap: () => onSelected(null),
            ),
            for (final keyword in keywords) ...[
              const SizedBox(width: 6),
              _StripChip(
                label: keyword,
                count: countsByKeyword[keyword] ?? 0,
                isSelected: keyword == selectedKeyword,
                onTap: () => onSelected(keyword),
              ),
            ],
            const SizedBox(width: 6),
            // No count: it is an action, not a filter, and a number beside it
            // would invite reading it as "manage (3) keywords".
            _StripChip(
              label: l10n.alertsManageKeywords,
              icon: Icons.tune_rounded,
              isSelected: false,
              onTap: onManageKeywords,
            ),
          ],
        ),
      ),
    );
  }
}

/// One chip in the strip.
///
/// Deliberately not [FolderTabBar]'s `_FolderTab`, and deliberately lighter
/// than it: the category pills above choose *what list you are looking at*,
/// this row only narrows the list already chosen. Given the same 36dp height,
/// the same labelLarge type and the same solid accent fill, the two rows read
/// as peers and the hierarchy inverts — the reader has to work out which one
/// is subordinate. 28dp, labelSmall, an outline when unselected and a tonal
/// (not solid-accent) fill when selected keeps the subordination legible
/// without making the chips hard to hit: the tap target is the full 44dp strip
/// height, since the strip's own padding sits inside the gesture area.
class _StripChip extends StatelessWidget {
  final String label;
  final int? count;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _StripChip({
    required this.label,
    this.count,
    this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final labelColor = isSelected
        ? scheme.onSecondaryContainer
        : scheme.onSurface.withValues(alpha: 0.65);

    // Zero is shown rather than hidden, unlike the folder pills: there the
    // count means "unread waiting for you" and zero is nothing to say, here it
    // means "this keyword has caught nothing yet", which is exactly what the
    // user opened the strip to find out.
    final text = count == null ? label : '$label ($count)';

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 28,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color:
                  isSelected ? scheme.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected
                    ? scheme.secondaryContainer
                    : scheme.outline.withValues(alpha: 0.6),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 13, color: labelColor),
                  const SizedBox(width: 5),
                ],
                Text(
                  text,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: labelColor,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
