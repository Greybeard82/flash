import '../utils/constants.dart';

/// Feed ordering values stored under the `article_sort_order` settings key.
const String kSortNewestFirst = 'newest';
const String kSortOldestFirst = 'oldest';

class AppSettings {
  /// Delay options offered for [autoMarkReadAtBottomSeconds], in seconds.
  /// 0 means "immediately on reaching the bottom"; the rest step by 5.
  static const List<int> autoMarkReadDelayOptions = [0, 5, 10, 15, 20, 25, 30];

  final String theme; // 'system' | 'light' | 'dark'
  final int refreshIntervalMinutes;

  /// "Max articles per feed" — the cap applied to each feed independently at
  /// fetch time. Not a cap on the All tab, which is the uncapped union of
  /// every feed's retained articles.
  final int articleLimit;

  /// Feed ordering: `'newest'` (newest article at the top) or `'oldest'`.
  ///
  /// Defaults to `'newest'`, which is what the app has always done. Applied
  /// when the list is loaded rather than in SQL, so the repository queries are
  /// untouched.
  final String articleSortOrder;

  final bool markReadOnScroll;

  /// Whether reaching the end of a feed marks everything in it as read.
  final bool autoMarkReadAtBottom;

  /// How long to stay at the bottom before that happens. 0 = immediately.
  /// Always one of [autoMarkReadDelayOptions].
  final int autoMarkReadAtBottomSeconds;
  final bool driveBackupEnabled;
  final int? driveLastBackupAt;
  final String? googleAccountEmail;
  final bool onboardingComplete;
  /// Age window for cleanup, in days. Meaning is unchanged — read articles
  /// older than this are purged — only the accepted range widened, from
  /// [5, 20] down to [2, 20], so the Filter bubble's 2–15 slider can't set a
  /// value the model would silently clamp back up. The Settings screen's
  /// stepper still moves within its own 5–20 bounds.
  ///
  /// NB: `ArticleRepository.runCleanup` applies its own independent
  /// `clamp(5, 20)`, so a stored 2–4 is preserved here but cleanup still
  /// behaves as if it were 5. Left alone deliberately — that clamp is in the
  /// retention path.
  final int cleanupAgeDays; // [2, 20]
  final bool newspaperMode;

  /// Whether read articles stay in the list until the next refresh.
  ///
  /// This no longer decides *whether* a read article survives — every read
  /// article is eventually retired, which deletes the row and tombstones its
  /// guid. It decides *when*: off retires as the article scrolls two cards
  /// above the viewport, on keeps it visible and dimmed and retires it at the
  /// next refresh or cold start. Saved articles are exempt either way.
  final bool showRead;

  /// Whether *Mark all as read* asks for confirmation first.
  ///
  /// Turned off by the dialog's own "Don't show again" checkbox, and back on
  /// from the Quick Settings bubble — a setting that can only ever be
  /// disabled is a trap.
  final bool markAllReadConfirm;

  const AppSettings({
    this.theme = 'system',
    this.refreshIntervalMinutes = 30,
    this.articleLimit = kFetchArticleLimit,
    this.articleSortOrder = kSortNewestFirst,
    this.markReadOnScroll = true,
    this.autoMarkReadAtBottom = true,
    this.autoMarkReadAtBottomSeconds = 5,
    this.driveBackupEnabled = false,
    this.driveLastBackupAt,
    this.googleAccountEmail,
    this.onboardingComplete = false,
    this.cleanupAgeDays = 7,
    this.newspaperMode = false,
    this.showRead = true,
    this.markAllReadConfirm = true,
  });

  /// Snaps a stored delay onto the offered options, so a value written by an
  /// older build (or hand-edited) can never leave the dropdown showing a
  /// selection it has no item for — which would throw at build time.
  static int _nearestDelayOption(int seconds) {
    if (autoMarkReadDelayOptions.contains(seconds)) return seconds;
    final clamped = seconds.clamp(
      autoMarkReadDelayOptions.first,
      autoMarkReadDelayOptions.last,
    );
    return autoMarkReadDelayOptions.reduce(
      (a, b) => (a - clamped).abs() <= (b - clamped).abs() ? a : b,
    );
  }

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      theme: map['theme'] ?? 'system',
      refreshIntervalMinutes: int.tryParse(map['refresh_interval_minutes'] ?? '30') ?? 30,
      articleLimit:
          int.tryParse(map['article_limit'] ?? '') ?? kFetchArticleLimit,
      articleSortOrder: map['article_sort_order'] == kSortOldestFirst
          ? kSortOldestFirst
          : kSortNewestFirst,
      markReadOnScroll: (map['mark_read_on_scroll'] ?? 'true') == 'true',
      autoMarkReadAtBottom:
          (map['auto_mark_read_at_bottom'] ?? 'true') == 'true',
      autoMarkReadAtBottomSeconds: _nearestDelayOption(
        int.tryParse(map['auto_mark_read_at_bottom_seconds'] ?? '5') ?? 5,
      ),
      driveBackupEnabled: (map['drive_backup_enabled'] ?? 'false') == 'true',
      driveLastBackupAt: map['drive_last_backup_at'] != null && map['drive_last_backup_at'] != 'null'
          ? int.tryParse(map['drive_last_backup_at']!)
          : null,
      googleAccountEmail: map['google_account_email'] == 'null' ? null : map['google_account_email'],
      onboardingComplete: (map['onboarding_complete'] ?? 'false') == 'true',
      cleanupAgeDays:
          (int.tryParse(map['cleanup_age_days'] ?? '7') ?? 7).clamp(2, 20),
      newspaperMode: (map['newspaper_mode'] ?? 'false') == 'true',
      showRead: (map['show_read'] ?? 'true') == 'true',
      markAllReadConfirm:
          (map['mark_all_read_confirm'] ?? 'true') == 'true',
    );
  }

  AppSettings copyWith({
    String? theme,
    int? refreshIntervalMinutes,
    int? articleLimit,
    String? articleSortOrder,
    bool? markReadOnScroll,
    bool? autoMarkReadAtBottom,
    int? autoMarkReadAtBottomSeconds,
    bool? driveBackupEnabled,
    int? driveLastBackupAt,
    String? googleAccountEmail,
    bool? onboardingComplete,
    int? cleanupAgeDays,
    bool? newspaperMode,
    bool? showRead,
    bool? markAllReadConfirm,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      refreshIntervalMinutes: refreshIntervalMinutes ?? this.refreshIntervalMinutes,
      articleLimit: articleLimit ?? this.articleLimit,
      articleSortOrder: articleSortOrder ?? this.articleSortOrder,
      markReadOnScroll: markReadOnScroll ?? this.markReadOnScroll,
      autoMarkReadAtBottom: autoMarkReadAtBottom ?? this.autoMarkReadAtBottom,
      autoMarkReadAtBottomSeconds:
          autoMarkReadAtBottomSeconds ?? this.autoMarkReadAtBottomSeconds,
      driveBackupEnabled: driveBackupEnabled ?? this.driveBackupEnabled,
      driveLastBackupAt: driveLastBackupAt ?? this.driveLastBackupAt,
      googleAccountEmail: googleAccountEmail ?? this.googleAccountEmail,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      cleanupAgeDays: cleanupAgeDays ?? this.cleanupAgeDays,
      newspaperMode: newspaperMode ?? this.newspaperMode,
      showRead: showRead ?? this.showRead,
      markAllReadConfirm: markAllReadConfirm ?? this.markAllReadConfirm,
    );
  }
}
