/// Age cutoff applied at fetch time: articles published longer ago than this
/// are never written to the database.
///
/// NB: this is *not* the same thing as `AppSettings.cleanupAgeDays`, which
/// deletes already-stored read articles. This one is hardcoded, so raising the
/// cleanup window above 7 days does not make older unread articles start
/// arriving — they are rejected before they reach the DB. Whether this should
/// follow the setting too is an open question, deliberately not changed here.
const int kFetchDayLimit = 7;

/// Default for "Max articles per feed" (`AppSettings.articleLimit`).
///
/// The *enforced* cap is the user's setting, resolved per feed — see
/// `RssService.effectiveArticleLimit`. This constant is only the fallback when
/// nothing has been stored, and exists so the default lives in one place
/// rather than being repeated as a literal in the settings model.
const int kFetchArticleLimit = 100;

/// How long a tombstone is kept.
///
/// Fetch thresholds discard anything older than [kFetchDayLimit] by publish
/// date, so a feed stops offering an article shortly after that. One extra day
/// covers clock skew and lazily back-dated feeds. Beyond this a tombstone can
/// only cost space.
const int kTombstoneDayLimit = kFetchDayLimit + 1;

/// Unread articles are deleted only once they are past the widest window the
/// user can select, not the window currently set.
///
/// The Filter bubble ranges to 15 days, so an article dropped under a 2-day
/// setting could still have been recovered by widening the slider. Past 15 it
/// is unreachable by any setting, and keeping it only inflates a badge that
/// counts rows the list is guaranteed not to show.
const int kUnreadRetentionDays = 15;

/// The `published_at` floor for a display window of [days].
///
/// The single source of this arithmetic. The unread badge and the visible list
/// must agree about what "too old to show" means — when they each computed it
/// their own way the badge counted 428 articles against a list of 5.
int displayCutoffMs(int days) =>
    DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
