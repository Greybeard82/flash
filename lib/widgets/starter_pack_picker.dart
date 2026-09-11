import 'dart:async';

import 'package:flutter/material.dart';

import '../data/starter_pack.dart';
import '../l10n/app_localizations.dart';
import '../services/starter_pack_service.dart';

/// The localised folder name for each starter category.
///
/// The single place the pack's ids meet the ARB, so the onboarding screen, the
/// sheet and the service cannot disagree about what a category is called — and
/// a name resolved here is what gets written to the folder, in the device
/// language at the moment of seeding.
Map<String, String> starterFolderNames(AppLocalizations l10n) => {
      'world_news': l10n.starterCategoryWorldNews,
      'tech': l10n.starterCategoryTech,
      'fitness_health': l10n.starterCategoryFitnessHealth,
      'travel': l10n.starterCategoryTravel,
      'sports': l10n.starterCategorySports,
    };

/// How many feeds the ticked categories add up to.
int starterFeedCount(Set<String> selected) => kStarterPack
    .where((c) => selected.contains(c.id))
    .fold<int>(0, (sum, c) => sum + c.feeds.length);

/// The category checklist, shared by the onboarding screen and the sheet.
///
/// Everything ticked by default. The pack exists because a fresh install
/// showed an empty app, so the path of least resistance has to be the one that
/// ends with articles on screen; a user who wants fewer unticks a box, and one
/// who wants none has the Skip button beside it.
class StarterPackPicker extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  /// Greyed out while a seed is in flight, so the selection cannot change
  /// under the write that is already using it.
  final bool enabled;

  const StarterPackPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final names = starterFolderNames(l10n);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final category in kStarterPack)
          CheckboxListTile(
            value: selected.contains(category.id),
            onChanged: enabled
                ? (checked) {
                    final next = Set<String>.of(selected);
                    if (checked ?? false) {
                      next.add(category.id);
                    } else {
                      next.remove(category.id);
                    }
                    onChanged(next);
                  }
                : null,
            title: Text(names[category.id] ?? category.id),
            // The publishers, named. "Tech" alone asks the user to take the
            // app's word for it; "Ars Technica, The Verge, WIRED" is the
            // thing they are actually deciding about.
            subtitle: Text(
              category.feeds.map((f) => f.title).join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            // 48dp is the Material minimum touch target, and the two-line
            // subtitle already exceeds it — this only stops a single-feed
            // category (Fitness / Health, Travelling) collapsing below it.
            visualDensity: VisualDensity.standard,
          ),
      ],
    );
  }
}

/// The starter pack offered after onboarding, from either empty state.
///
/// Pops with the [StarterPackResult] when it seeds, and with null when the
/// user dismisses it — so a caller can tell "added nothing" from "changed
/// their mind" without inspecting counts.
class StarterPackSheet extends StatefulWidget {
  const StarterPackSheet({super.key});

  @override
  State<StarterPackSheet> createState() => _StarterPackSheetState();
}

class _StarterPackSheetState extends State<StarterPackSheet> {
  late Set<String> _selected = kStarterPack.map((c) => c.id).toSet();
  bool _adding = false;

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context)!;
    final navigator = Navigator.of(context);
    setState(() => _adding = true);

    final service = StarterPackService();
    final result = await service.addCategories(
      kStarterPack.map((c) => c.id).where(_selected.contains).toList(),
      starterFolderNames(l10n),
    );
    // Not awaited: a dozen favicon round trips must not stand between the tap
    // and the articles. The monogram fallback covers the gap.
    unawaited(service.warmFavicons(result.addedFeeds));

    if (mounted) navigator.pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final count = starterFeedCount(_selected);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle, title and spacing all copied from _AddFeedSheet: this is
          // the second way of adding feeds and should not look like a
          // different app.
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.starterPackSheetTitle,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Flexible(
            child: SingleChildScrollView(
              child: StarterPackPicker(
                selected: _selected,
                enabled: !_adding,
                onChanged: (next) => setState(() => _selected = next),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: (count == 0 || _adding) ? null : _add,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
            child: Text(l10n.addStarterFeedsButton(count)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
