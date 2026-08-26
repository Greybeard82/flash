import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../utils/day_grouping.dart';

/// Fixed header height.
///
/// `FeedScreen._onScroll` walks the row list summing heights to decide which
/// articles have passed the viewport midpoint. It can measure article cards
/// through their GlobalKeys, but headers have none — so this height is
/// declared here and *enforced* by the SizedBox below rather than estimated.
/// If you change one, change both, or mark-as-read starts firing at the wrong
/// scroll offset and the error compounds down the list.
const double kDayHeaderHeight = 36.0;

class DayHeader extends StatelessWidget {
  final DayHeaderRow row;

  const DayHeader({super.key, required this.row});

  /// The label for [row], in the active locale.
  ///
  /// `DateFormat` needs date symbols loaded for the locale it is handed.
  /// `GlobalMaterialLocalizations.delegate` — already installed in `app.dart`
  /// — initialises them for the active locale, and this only ever formats in
  /// that locale, so no explicit `initializeDateFormatting` call is needed.
  static String labelFor(
    DayHeaderRow row,
    AppLocalizations l10n,
    String localeName,
  ) {
    switch (row.bucket) {
      case DayBucket.today:
        return l10n.dayToday;
      case DayBucket.yesterday:
        return l10n.dayYesterday;
      case DayBucket.withinWeek:
        return DateFormat.EEEE(localeName).format(row.day);
      case DayBucket.older:
        return DateFormat.MMMd(localeName).format(row.day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final localeName = Localizations.localeOf(context).toLanguageTag();

    return SizedBox(
      height: kDayHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            labelFor(row, l10n, localeName).toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}
