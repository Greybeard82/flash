import '../models/alert_match.dart';

/// Decides what the keyword-alert notifications of one refresh pass should
/// say, and how many of them there are.
///
/// This lives apart from the code that posts them because two of the worst
/// alert bugs were decisions, not plumbing, and neither was reachable in a
/// test while the decision sat inline in `RefreshService` next to
/// `plugin.show()`:
///
/// The first was the single hardcoded id. Every alert was posted under
/// `_kKeywordNotificationId = 2`, and Android treats the id as the identity of
/// a notification — so the second alert of a pass did not join the first in
/// the shade, it OVERWROTE it. Three unrelated keywords hitting while the
/// phone was in a pocket left exactly one notification: whichever was posted
/// last. The other two were destroyed by the system, and nothing in the app
/// could tell they had ever existed.
///
/// The second was the body. It joined every keyword matched anywhere in the
/// pass into one sentence — `New articles matching "zelda", "crypto"` — so two
/// alerts that had nothing to do with each other arrived as a single
/// indivisible blob, with no way to see whether "crypto" had hit once or
/// forty times.
///
/// The fix for both is the same unit: the keyword SET an article matched. One
/// distinct set is one plan, one notification and one id, so sets can no
/// longer evict each other, and an article that matched two keywords is still
/// only one thing to read. The set is sorted here for the same reason
/// `AlertMatchRepository.notificationIdFor` sorts it — {mario, zelda} and
/// {zelda, mario} must resolve to the same id or the shade shows the same
/// article twice.
///
/// Pure by construction: no database, no `flutter_local_notifications`, no
/// Flutter import at all. The running total arrives through a callback so the
/// rules can be exercised against a staged history.
///
/// One deliberate design point, because it looks like an omission: THE RUNNING
/// TOTAL IS THE STATE. There is no "have I notified for this keyword before"
/// flag anywhere, and there must not be one — a flag records what the app did,
/// while the total records what the user still has waiting in the Alerts tab,
/// and it is the second of those the body is describing. Two consequences fall
/// straight out of that and are both intended. Binning every entry for a
/// keyword empties its group, so the next arrival counts one and reads as a
/// first appearance again — a flag would have stayed set through the deletion
/// and reported a stale tally forever. And adding a keyword backfills every
/// article already on the device, so a backfill of eight followed by one new
/// arrival counts nine and says "9 articles matched", never "appeared in an
/// article": the arrival is the first notification the user has seen for that
/// keyword, but it is not the first entry, and pointing at one article would
/// hide the eight sitting behind it.

/// Which sentence an alert notification uses.
enum AlertBodyKind {
  /// A single keyword with exactly one entry behind it. Nothing to tally, so
  /// the body names the article itself.
  first,

  /// A single keyword with more than one entry. The body reports the total
  /// waiting in the Alerts tab, not the row written this pass.
  count,

  /// Two or more keywords on the same article. Stays combined at any size —
  /// it never collapses to [first] just because the intersection total is 1,
  /// since "appeared in an article" cannot name which keywords were involved.
  combined,
}

/// One notification: the keyword set that earns it, the sentence it uses, and
/// the number that sentence quotes.
class AlertNotificationPlan {
  /// The matched set, sorted. Also the key the notification id is minted from.
  final List<String> keywords;

  final AlertBodyKind kind;

  /// Entries currently in the Alerts tab carrying every keyword in
  /// [keywords] — the intersection, not the sum of the individual groups.
  final int count;

  const AlertNotificationPlan({
    required this.keywords,
    required this.kind,
    required this.count,
  });
}

/// The separator that makes a keyword set into a single comparable key.
///
/// A NUL can't occur inside a keyword the user typed, so `['a\u0000b']` cannot
/// masquerade as `['a', 'b']`. Same character `notificationIdFor` keys on, so
/// the grouping here and the id minted from it can never disagree about which
/// sets are the same set.
const String _kSetSeparator = '\u0000';

/// Groups [newMatches] into one plan per distinct keyword set.
///
/// [newMatches] must be the rows `AlertMatchRepository.insertMatches`
/// genuinely wrote this pass, never everything the fetch parsed: RSS feeds
/// re-serve their last N items on every poll, so planning off re-seen articles
/// would notify about the same headline every thirty minutes.
///
/// [runningTotalFor] is handed the sorted keyword list and answers with how
/// many entries carry all of them — `AlertMatchRepository.countForKeywordSet`
/// in production. It is consulted once per distinct set, and not at all when
/// nothing was written.
List<AlertNotificationPlan> planAlertNotifications({
  required List<AlertMatch> newMatches,
  required int Function(List<String> sortedKeywords) runningTotalFor,
}) {
  // Two passes, because an article's set is only known once every one of its
  // rows has been seen: gather the keywords written for each article, then
  // collapse the articles that ended up with identical sets.
  final keywordsByArticle = <String, Set<String>>{};
  for (final match in newMatches) {
    keywordsByArticle
        .putIfAbsent(
            '${match.feedId}$_kSetSeparator${match.guid}', () => <String>{})
        .add(match.keyword);
  }

  final setsByKey = <String, List<String>>{};
  for (final keywords in keywordsByArticle.values) {
    final sorted = keywords.toList()..sort();
    setsByKey[sorted.join(_kSetSeparator)] = sorted;
  }

  // Sorted so the same pass produces the same plans in the same order however
  // the feeds happened to be fetched; otherwise one alert could be described
  // differently from one refresh to the next.
  final keys = setsByKey.keys.toList()..sort();

  return [
    for (final key in keys) _planFor(setsByKey[key]!, runningTotalFor),
  ];
}

AlertNotificationPlan _planFor(
  List<String> sortedKeywords,
  int Function(List<String>) runningTotalFor,
) {
  final total = runningTotalFor(sortedKeywords);
  final kind = sortedKeywords.length > 1
      ? AlertBodyKind.combined
      : (total > 1 ? AlertBodyKind.count : AlertBodyKind.first);
  return AlertNotificationPlan(
    keywords: sortedKeywords,
    kind: kind,
    count: total,
  );
}
