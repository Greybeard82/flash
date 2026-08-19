import '../utils/constants.dart';

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

  final bool markReadOnScroll;

  /// Whether reaching the end of a feed marks everything in it as read.
  final bool autoMarkReadAtBottom;

  /// How long to stay at the bottom before that happens. 0 = immediately.
  /// Always one of [autoMarkReadDelayOptions].
  final int autoMarkReadAtBottomSeconds;
  final bool driveBackupEnabled;
  final int? driveLastBackupAt;
  final bool anthropicApiKeySet;
  final String? googleAccountEmail;
  final bool onboardingComplete;
  final int cleanupAgeDays; // [5, 20]
  final bool newspaperMode;

  const AppSettings({
    this.theme = 'system',
    this.refreshIntervalMinutes = 30,
    this.articleLimit = kFetchArticleLimit,
    this.markReadOnScroll = true,
    this.autoMarkReadAtBottom = true,
    this.autoMarkReadAtBottomSeconds = 5,
    this.driveBackupEnabled = false,
    this.driveLastBackupAt,
    this.anthropicApiKeySet = false,
    this.googleAccountEmail,
    this.onboardingComplete = false,
    this.cleanupAgeDays = 7,
    this.newspaperMode = false,
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
      anthropicApiKeySet: (map['anthropic_api_key_set'] ?? 'false') == 'true',
      googleAccountEmail: map['google_account_email'] == 'null' ? null : map['google_account_email'],
      onboardingComplete: (map['onboarding_complete'] ?? 'false') == 'true',
      cleanupAgeDays: (int.tryParse(map['cleanup_age_days'] ?? '7') ?? 7).clamp(5, 20),
      newspaperMode: (map['newspaper_mode'] ?? 'false') == 'true',
    );
  }

  AppSettings copyWith({
    String? theme,
    int? refreshIntervalMinutes,
    int? articleLimit,
    bool? markReadOnScroll,
    bool? autoMarkReadAtBottom,
    int? autoMarkReadAtBottomSeconds,
    bool? driveBackupEnabled,
    int? driveLastBackupAt,
    bool? anthropicApiKeySet,
    String? googleAccountEmail,
    bool? onboardingComplete,
    int? cleanupAgeDays,
    bool? newspaperMode,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      refreshIntervalMinutes: refreshIntervalMinutes ?? this.refreshIntervalMinutes,
      articleLimit: articleLimit ?? this.articleLimit,
      markReadOnScroll: markReadOnScroll ?? this.markReadOnScroll,
      autoMarkReadAtBottom: autoMarkReadAtBottom ?? this.autoMarkReadAtBottom,
      autoMarkReadAtBottomSeconds:
          autoMarkReadAtBottomSeconds ?? this.autoMarkReadAtBottomSeconds,
      driveBackupEnabled: driveBackupEnabled ?? this.driveBackupEnabled,
      driveLastBackupAt: driveLastBackupAt ?? this.driveLastBackupAt,
      anthropicApiKeySet: anthropicApiKeySet ?? this.anthropicApiKeySet,
      googleAccountEmail: googleAccountEmail ?? this.googleAccountEmail,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      cleanupAgeDays: cleanupAgeDays ?? this.cleanupAgeDays,
      newspaperMode: newspaperMode ?? this.newspaperMode,
    );
  }
}
