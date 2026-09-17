import 'article.dart';

/// One card in the Alerts tab: an article, and every alert keyword it hit.
///
/// [AlertMatch] is one row per keyword, which is the right shape for the table
/// and the wrong shape for the screen — under first-match-wins an article that
/// hit two keywords was filed under one of them, and the naive fix of listing
/// the rows directly draws the same headline twice. An entry is the group:
/// every `alert_matches` row sharing a (feedId, guid), collapsed into a single
/// card carrying one badge per keyword.
class AlertEntry {
  final int feedId;
  final String guid;

  /// Sorted alphabetically, so the badges keep the same order across rebuilds
  /// rather than following whatever order SQLite handed the rows back in.
  final List<String> keywords;

  final String title;
  final String url;
  final String? description;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final String? feedTitle;
  final String? feedFaviconPath;
  final int? publishedAt;

  /// The newest [AlertMatch.matchedAt] in the group, so a keyword hitting an
  /// article the user has already scrolled past lifts it back to the top.
  final int matchedAt;

  /// True only when *every* keyword row in the group is read. The card is one
  /// thing to the user, and dimming it while one of its keyword rows is still
  /// unread would hide an alert they have never seen.
  final bool isRead;

  const AlertEntry({
    required this.feedId,
    required this.guid,
    required this.keywords,
    required this.title,
    required this.url,
    this.description,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.feedTitle,
    this.feedFaviconPath,
    this.publishedAt,
    required this.matchedAt,
    this.isRead = false,
  });

  /// The entry as an [Article], so `ArticleCard` renders an alert exactly like
  /// anything else in the list.
  ///
  /// **`id` is null by design and nothing may assume otherwise.** A snapshot
  /// has no `articles` identity: the row it was taken from may have been
  /// retired, cleaned up or never re-fetched, and inventing an id here would
  /// point every id-keyed operation — mark-read, bookmark, summary — at
  /// whatever article happens to hold that rowid now. The Alerts tab therefore
  /// keys off (feedId, guid) and looks the articles row up only when it needs
  /// one, tolerating its absence. `fetchedAt` carries [matchedAt] because the
  /// match is the only fetch-shaped timestamp the snapshot has.
  /// [isSaved] is a parameter rather than a field, and that is the fix for a
  /// bug that destroyed bookmarks.
  ///
  /// It used to default to `false` and nothing ever passed otherwise, so an
  /// article the user had saved showed an **unsaved** bookmark in the Alerts
  /// tab. Tapping it looked like "save this" and ran a toggle that read the
  /// real row, found it saved, and unsaved it. The bookmark was gone, the user
  /// had asked for the opposite, and nothing said so.
  ///
  /// A snapshot cannot know this on its own — saved state lives on the
  /// `articles` row, which is exactly what a snapshot does not have. So the
  /// caller resolves it, once for the whole visible set, and passes it in. The
  /// invariant that matters: **whatever draws the glyph and whatever performs
  /// the write must read the same source**, and that source is the real row.
  Article toArticle({bool isSaved = false}) {
    return Article(
      id: null,
      isSaved: isSaved,
      feedId: feedId,
      guid: guid,
      title: title,
      url: url,
      description: description,
      thumbnailUrl: thumbnailUrl,
      thumbnailPath: thumbnailPath,
      publishedAt: publishedAt,
      fetchedAt: matchedAt,
      isRead: isRead,
      feedTitle: feedTitle,
      feedFaviconPath: feedFaviconPath,
    );
  }
}
