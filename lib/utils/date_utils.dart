import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

String formatRelativeTime(DateTime? dateTime, AppLocalizations l10n) {
  if (dateTime == null) return '';
  final now = DateTime.now();
  final diff = now.difference(dateTime);

  if (diff.inSeconds < 60) return l10n.timeJustNow;
  if (diff.inMinutes < 60) return l10n.timeMinAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.timeHourAgo(diff.inHours);
  if (diff.inDays == 1) return l10n.timeYesterday;
  if (diff.inDays < 7) return l10n.timeDaysAgo(diff.inDays);
  if (diff.inDays < 30) return l10n.timeWeeksAgo((diff.inDays / 7).floor());
  if (diff.inDays < 365) return l10n.timeMonthsAgo((diff.inDays / 30).floor());
  return l10n.timeYearsAgo((diff.inDays / 365).floor());
}

String formatRelativeTimestamp(int? millis, AppLocalizations l10n) {
  if (millis == null) return '';
  return formatRelativeTime(DateTime.fromMillisecondsSinceEpoch(millis), l10n);
}

/// The article's publish date, spelled out, in the active locale.
///
/// Google Play's News and Magazines policy wants a clear publication date on
/// every article, and the relative stamp the cards carry ("3h ago") is not
/// one — it says how long ago without ever saying when. This is the absolute
/// form, shown beside the publisher wherever an article is opened.
///
/// [DateFormat.yMMMd] plus [DateFormat.add_jm] rather than a hand-built
/// pattern: the locale decides the field order *and* whether the clock is 12-
/// or 24-hour, which is the half a hardcoded 'h:mm a' gets wrong outside
/// English.
///
/// Same locale handling as `DayHeader.labelFor`: the caller passes
/// `Localizations.localeOf(context).toLanguageTag()`, and the date symbols for
/// it are already loaded by `GlobalMaterialLocalizations.delegate`, so no
/// `initializeDateFormatting` call is needed.
String formatPublishedDate(int? millis, String localeName) {
  if (millis == null) return '';
  return DateFormat.yMMMd(localeName)
      .add_jm()
      .format(DateTime.fromMillisecondsSinceEpoch(millis));
}
