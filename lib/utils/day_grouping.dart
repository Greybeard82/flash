import '../models/article.dart';

/// Which label a day header gets. Computed from dates alone so it can be
/// tested without localisation or a BuildContext.
enum DayBucket {
  today,
  yesterday,

  /// Within the last seven days — labelled with the weekday name.
  withinWeek,

  /// Older — labelled with a day and month.
  older,
}

/// A row in the article list: either a day header or an article.
sealed class FeedRow {
  const FeedRow();
}

final class DayHeaderRow extends FeedRow {
  /// Local midnight of the day this header introduces.
  final DateTime day;
  final DayBucket bucket;

  const DayHeaderRow(this.day, this.bucket);
}

final class ArticleRow extends FeedRow {
  final Article article;

  const ArticleRow(this.article);
}

/// Local midnight for [dt] — the grouping key.
DateTime _startOfDay(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

DayBucket bucketFor(DateTime day, DateTime now) {
  final today = _startOfDay(now);
  final delta = today.difference(_startOfDay(day)).inDays;
  if (delta <= 0) return DayBucket.today;
  if (delta == 1) return DayBucket.yesterday;
  if (delta < 7) return DayBucket.withinWeek;
  return DayBucket.older;
}

/// The instant an article is filed under.
///
/// `published_at` is nullable and `fetched_at` is not, so the fallback keeps
/// every article in exactly one group. `applyFetchThresholds` already drops
/// articles with no publish date, so this is a guard rather than a common
/// path — but `_applyDisplayFilters` deliberately shows one if it ever gets
/// through, and an ungrouped article would break the row/height accounting.
int groupingInstant(Article a) => a.publishedAt ?? a.fetchedAt;

/// Interleaves day headers into [articles], which must already be in display
/// order.
///
/// A header is emitted whenever the day changes from the previous article, so
/// this is correct for both sort orders without knowing which is in use:
/// newest-first yields Today, Yesterday, …; oldest-first yields the reverse.
/// A future-dated article buckets as [DayBucket.today].
List<FeedRow> groupByDay(List<Article> articles, {required DateTime now}) {
  final today = _startOfDay(now);
  final rows = <FeedRow>[];
  DateTime? currentDay;

  for (final article in articles) {
    var day = _startOfDay(
      DateTime.fromMillisecondsSinceEpoch(groupingInstant(article)),
    );
    // [bucketFor] already clamps a future date to today, so the grouping key
    // has to be clamped too. Without this a clock-skewed feed — and there is
    // at least one in the wild, seen publishing an hour into tomorrow —
    // makes its own group, which then renders a second header reading
    // "Today" directly above the real one.
    if (day.isAfter(today)) day = today;
    if (currentDay == null || day != currentDay) {
      rows.add(DayHeaderRow(day, bucketFor(day, now)));
      currentDay = day;
    }
    rows.add(ArticleRow(article));
  }
  return rows;
}
