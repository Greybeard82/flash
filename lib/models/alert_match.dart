/// One row of `alert_matches`: a single (feed_id, guid, keyword) hit, with its
/// own copy of everything the card draws.
///
/// The fields duplicate an `articles` row on purpose. A match used to be the
/// `matched_alert_keyword` column on that row, so it had no existence apart
/// from the article: retirement deleted it on the next refresh, cleanup deleted
/// it on age, and the tombstone written on the way out stopped the re-fetch
/// bringing it back. Carrying its own title, url, thumbnail and feed identity
/// is what lets the match outlive all three — and the feed being unsubscribed
/// from, since [feedId] deliberately has no foreign key behind it.
class AlertMatch {
  final int? id;
  final int feedId;
  final String guid;
  final String keyword;
  final String title;
  final String url;
  final String? description;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final String? feedTitle;
  final String? feedFaviconPath;

  /// The folder the feed sat in *at match time*. A point-in-time copy, so it
  /// can name a folder that has since been renamed, moved or deleted;
  /// `setReadByFolder` reads it and nothing may treat a stale value as more
  /// than a hint.
  final int? folderId;

  final int? publishedAt;
  final int matchedAt;
  final bool isRead;

  const AlertMatch({
    this.id,
    required this.feedId,
    required this.guid,
    required this.keyword,
    required this.title,
    required this.url,
    this.description,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.feedTitle,
    this.feedFaviconPath,
    this.folderId,
    this.publishedAt,
    required this.matchedAt,
    this.isRead = false,
  });

  factory AlertMatch.fromMap(Map<String, dynamic> map) {
    return AlertMatch(
      id: map['id'] as int?,
      feedId: map['feed_id'] as int,
      guid: map['guid'] as String,
      keyword: map['keyword'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      description: map['description'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      feedTitle: map['feed_title'] as String?,
      feedFaviconPath: map['feed_favicon_path'] as String?,
      folderId: map['folder_id'] as int?,
      publishedAt: map['published_at'] as int?,
      matchedAt: map['matched_at'] as int,
      isRead: (map['is_read'] as int? ?? 0) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'feed_id': feedId,
      'guid': guid,
      'keyword': keyword,
      'title': title,
      'url': url,
      'description': description,
      'thumbnail_url': thumbnailUrl,
      'thumbnail_path': thumbnailPath,
      'feed_title': feedTitle,
      'feed_favicon_path': feedFaviconPath,
      'folder_id': folderId,
      'published_at': publishedAt,
      'matched_at': matchedAt,
      'is_read': isRead ? 1 : 0,
    };
  }

  AlertMatch copyWith({
    int? id,
    int? feedId,
    String? guid,
    String? keyword,
    String? title,
    String? url,
    String? description,
    String? thumbnailUrl,
    String? thumbnailPath,
    String? feedTitle,
    String? feedFaviconPath,
    int? folderId,
    int? publishedAt,
    int? matchedAt,
    bool? isRead,
  }) {
    return AlertMatch(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      guid: guid ?? this.guid,
      keyword: keyword ?? this.keyword,
      title: title ?? this.title,
      url: url ?? this.url,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      feedTitle: feedTitle ?? this.feedTitle,
      feedFaviconPath: feedFaviconPath ?? this.feedFaviconPath,
      folderId: folderId ?? this.folderId,
      publishedAt: publishedAt ?? this.publishedAt,
      matchedAt: matchedAt ?? this.matchedAt,
      isRead: isRead ?? this.isRead,
    );
  }
}
