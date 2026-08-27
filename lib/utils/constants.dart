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

/// Master switch for retirement-on-scroll.
///
/// DISABLED in pass 07. Scroll retirement was deleting articles that were
/// still on screen: heights were guessed at 120px for every row the ListView
/// had disposed, so the computed frontier drifted into the visible region and
/// the drift grew the further the user scrolled. Programmatic scrolls fired
/// it too, and it re-entered through its own offset correction.
///
/// With this off, marking read on scroll still works and articles still dim;
/// with Show read off they are retired at the next refresh instead of during
/// the scroll. Degraded, not broken.
const bool kEnableScrollRetirement = false;

/// How many articles sit between the top of the viewport and the point at
/// which an article is retired.
///
/// Zero would retire the article the instant its last pixel left the screen,
/// which makes a small overscroll or a bounce feel like the list is eating
/// itself. Two is enough that no ordinary gesture reaches the frontier.
const int kRetirementBufferCards = 2;
