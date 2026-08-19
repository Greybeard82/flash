class Feed {
  final int? id;
  final int folderId;
  final String title;
  final String url;
  final String? siteUrl;
  final String? faviconPath;
  final String? description;
  /// Per-feed override for "Max articles per feed". Null means "use the
  /// global setting", which is every feed today — no screen writes this, so
  /// the column is always null in practice. It is honoured at fetch time
  /// (`RssService.effectiveArticleLimit`) rather than ignored, so that a value
  /// arriving here — from a future editor, an import, or a hand-edited DB —
  /// means what it says.
  final int? articleLimit;
  final int? lastFetchedAt;
  final String? lastFetchError;
  final int consecutiveFailures;
  final bool isDead;
  final int position;
  final int createdAt;

  const Feed({
    this.id,
    required this.folderId,
    required this.title,
    required this.url,
    this.siteUrl,
    this.faviconPath,
    this.description,
    this.articleLimit,
    this.lastFetchedAt,
    this.lastFetchError,
    this.consecutiveFailures = 0,
    this.isDead = false,
    this.position = 0,
    required this.createdAt,
  });

  factory Feed.fromMap(Map<String, dynamic> map) {
    return Feed(
      id: map['id'] as int?,
      folderId: map['folder_id'] as int,
      title: map['title'] as String,
      url: map['url'] as String,
      siteUrl: map['site_url'] as String?,
      faviconPath: map['favicon_path'] as String?,
      description: map['description'] as String?,
      articleLimit: map['article_limit'] as int?,
      lastFetchedAt: map['last_fetched_at'] as int?,
      lastFetchError: map['last_fetch_error'] as String?,
      consecutiveFailures: map['consecutive_failures'] as int? ?? 0,
      isDead: (map['is_dead'] as int? ?? 0) == 1,
      position: map['position'] as int? ?? 0,
      createdAt: map['created_at'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'folder_id': folderId,
      'title': title,
      'url': url,
      'site_url': siteUrl,
      'favicon_path': faviconPath,
      'description': description,
      'article_limit': articleLimit,
      'last_fetched_at': lastFetchedAt,
      'last_fetch_error': lastFetchError,
      'consecutive_failures': consecutiveFailures,
      'is_dead': isDead ? 1 : 0,
      'position': position,
      'created_at': createdAt,
    };
  }

  Feed copyWith({
    int? id,
    int? folderId,
    String? title,
    String? url,
    String? siteUrl,
    String? faviconPath,
    String? description,
    int? articleLimit,
    int? lastFetchedAt,
    String? lastFetchError,
    int? consecutiveFailures,
    bool? isDead,
    int? position,
    int? createdAt,
  }) {
    return Feed(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      title: title ?? this.title,
      url: url ?? this.url,
      siteUrl: siteUrl ?? this.siteUrl,
      faviconPath: faviconPath ?? this.faviconPath,
      description: description ?? this.description,
      articleLimit: articleLimit ?? this.articleLimit,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      lastFetchError: lastFetchError ?? this.lastFetchError,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      isDead: isDead ?? this.isDead,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  bool get isHealthy => lastFetchError == null && !isDead;

  String get domain {
    try {
      final uri = Uri.parse(siteUrl ?? url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return '';
    }
  }
}
