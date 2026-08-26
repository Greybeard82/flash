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

/// How many articles sit between the top of the viewport and the point at
/// which an article is retired.
///
/// Zero would retire the article the instant its last pixel left the screen,
/// which makes a small overscroll or a bounce feel like the list is eating
/// itself. Two is enough that no ordinary gesture reaches the frontier.
const int kRetirementBufferCards = 2;
