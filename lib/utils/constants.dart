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
/// Re-enabled at the end of pass 07, after the three causes of the regression
/// were fixed and a structural guard was added.
///
/// It was disabled because retirement deleted articles that were still on
/// screen: row heights were guessed at 120px for every row the ListView had
/// disposed (real cards measure 96.8dp and 121.9dp, so the guess was wrong in
/// both directions and the error accumulated); `jumpTo` dispatches
/// ScrollEndNotification, so every programmatic scroll ran retirement; and it
/// re-entered through its own offset correction.
///
/// Heights are now measured and remembered, retirement consults
/// [MarkReadGate], a flag blocks re-entry, and — the part that makes a
/// recurrence impossible rather than merely unlikely — retirement is confined
/// to rows the ListView has *disposed*, so no arithmetic error here can reach
/// something the user can see.
const bool kEnableScrollRetirement = true;

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

/// Minimum articles between the top of the viewport and the retirement point.
///
/// A **floor**, not the operative rule. The real mechanism is the built-row
/// ceiling in `planRetirement`: retirement is confined to rows `ListView`
/// has disposed, and with the feed's `cacheExtent: 500` and ~110dp cards that
/// keeps roughly 4.5 rows above the viewport alive — more than this buffer.
/// So in normal operation the ceiling binds first and this constant does
/// nothing.
///
/// It still earns its place for the cases where the ceiling is *not* the
/// larger of the two: a small `cacheExtent`, very tall cards, or a large
/// text scale. The effective distance is
/// `max(kRetirementBufferCards, builtRowsAboveViewport)`, which
/// retirement_frontier_test.dart pins.
///
/// Zero would retire an article the instant its last pixel left the screen,
/// which makes a small overscroll or a bounce feel like the list is eating
/// itself.
const int kRetirementBufferCards = 2;
