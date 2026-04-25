class Article {
  final int? id;
  final int feedId;
  final String guid;
  final String title;
  final String url;
  final String? description;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final int? publishedAt;
  final int fetchedAt;
  final bool isRead;
  final bool isBlocked;
  final bool isSaved;
  final String? blockedKeyword;

  // Joined fields (not stored in DB)
  final String? feedTitle;
  final String? feedFaviconPath;

  const Article({
    this.id,
    required this.feedId,
    required this.guid,
    required this.title,
    required this.url,
    this.description,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.publishedAt,
    required this.fetchedAt,
    this.isRead = false,
    this.isBlocked = false,
    this.isSaved = false,
    this.blockedKeyword,
    this.feedTitle,
    this.feedFaviconPath,
  });

  factory Article.fromMap(Map<String, dynamic> map) {
    return Article(
      id: map['id'] as int?,
      feedId: map['feed_id'] as int,
      guid: map['guid'] as String,
      title: map['title'] as String,
      url: map['url'] as String,
      description: map['description'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      thumbnailPath: map['thumbnail_path'] as String?,
      publishedAt: map['published_at'] as int?,
      fetchedAt: map['fetched_at'] as int,
      isRead: (map['is_read'] as int? ?? 0) == 1,
      isBlocked: (map['is_blocked'] as int? ?? 0) == 1,
      isSaved: (map['is_saved'] as int? ?? 0) == 1,
      blockedKeyword: map['blocked_keyword'] as String?,
      feedTitle: map['feed_title'] as String?,
      feedFaviconPath: map['feed_favicon_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'feed_id': feedId,
      'guid': guid,
      'title': title,
      'url': url,
      'description': description,
      'thumbnail_url': thumbnailUrl,
      'thumbnail_path': thumbnailPath,
      'published_at': publishedAt,
      'fetched_at': fetchedAt,
      'is_read': isRead ? 1 : 0,
      'is_blocked': isBlocked ? 1 : 0,
      'is_saved': isSaved ? 1 : 0,
      'blocked_keyword': blockedKeyword,
    };
  }

  Article copyWith({
    int? id,
    int? feedId,
    String? guid,
    String? title,
    String? url,
    String? description,
    String? thumbnailUrl,
    String? thumbnailPath,
    int? publishedAt,
    int? fetchedAt,
    bool? isRead,
    bool? isBlocked,
    bool? isSaved,
    String? blockedKeyword,
    String? feedTitle,
    String? feedFaviconPath,
  }) {
    return Article(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      guid: guid ?? this.guid,
      title: title ?? this.title,
      url: url ?? this.url,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      publishedAt: publishedAt ?? this.publishedAt,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      isRead: isRead ?? this.isRead,
      isBlocked: isBlocked ?? this.isBlocked,
      isSaved: isSaved ?? this.isSaved,
      blockedKeyword: blockedKeyword ?? this.blockedKeyword,
      feedTitle: feedTitle ?? this.feedTitle,
      feedFaviconPath: feedFaviconPath ?? this.feedFaviconPath,
    );
  }

  DateTime? get publishedDateTime => publishedAt != null
      ? DateTime.fromMillisecondsSinceEpoch(publishedAt!)
      : null;
}
