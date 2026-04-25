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
