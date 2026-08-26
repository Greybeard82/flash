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

/// How long a read article stays restorable after being read. Switching
/// "Show read" back on brings back anything read inside this window; anything
/// older stays hidden even though the row is still in the database (deletion
/// is owned by `cleanup_age_days`, which is a different rule entirely).
const int kShowReadBufferHours = 48;

/// Sentinel `read_at` meaning "read and deliberately dismissed".
///
/// Epoch, so it is outside every possible buffer window and the article never
/// returns when "Show read" is switched on. Written by *Mark all as read*,
/// which is an act of dismissal rather than an act of reading. The end-of-feed
/// dwell timer deliberately does NOT use this — see the dwell-timer callers.
const int kDismissedReadAt = 0;
