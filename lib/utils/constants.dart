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

/// How many articles sit between the top of the viewport and the point at
/// which an article is retired.
///
/// Zero would retire the article the instant its last pixel left the screen,
/// which makes a small overscroll or a bounce feel like the list is eating
/// itself. Two is enough that no ordinary gesture reaches the frontier.
const int kRetirementBufferCards = 2;
