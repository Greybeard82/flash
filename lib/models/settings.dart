class AppSettings {
  final String theme; // 'system' | 'light' | 'dark'
  final int refreshIntervalMinutes;
  final int articleLimit;
  final bool markReadOnScroll;
  final bool driveBackupEnabled;
  final int? driveLastBackupAt;
  final bool anthropicApiKeySet;
  final String? googleAccountEmail;
  final bool onboardingComplete;
  final String articleFontSize; // 'small' | 'medium' | 'large'
  final bool readerMode;
  final int cleanupAgeDays; // [5, 20]
  final bool newspaperMode;

  const AppSettings({
    this.theme = 'system',
    this.refreshIntervalMinutes = 30,
    this.articleLimit = 100,
    this.markReadOnScroll = true,
    this.driveBackupEnabled = false,
    this.driveLastBackupAt,
    this.anthropicApiKeySet = false,
    this.googleAccountEmail,
    this.onboardingComplete = false,
    this.articleFontSize = 'medium',
    this.readerMode = false,
    this.cleanupAgeDays = 7,
    this.newspaperMode = false,
  });

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      theme: map['theme'] ?? 'system',
      refreshIntervalMinutes: int.tryParse(map['refresh_interval_minutes'] ?? '30') ?? 30,
      articleLimit: int.tryParse(map['article_limit'] ?? '100') ?? 100,
      markReadOnScroll: (map['mark_read_on_scroll'] ?? 'true') == 'true',
      driveBackupEnabled: (map['drive_backup_enabled'] ?? 'false') == 'true',
      driveLastBackupAt: map['drive_last_backup_at'] != null && map['drive_last_backup_at'] != 'null'
          ? int.tryParse(map['drive_last_backup_at']!)
          : null,
      anthropicApiKeySet: (map['anthropic_api_key_set'] ?? 'false') == 'true',
      googleAccountEmail: map['google_account_email'] == 'null' ? null : map['google_account_email'],
      onboardingComplete: (map['onboarding_complete'] ?? 'false') == 'true',
      articleFontSize: map['article_font_size'] ?? 'medium',
      readerMode: (map['reader_mode'] ?? 'false') == 'true',
      cleanupAgeDays: (int.tryParse(map['cleanup_age_days'] ?? '7') ?? 7).clamp(5, 20),
      newspaperMode: (map['newspaper_mode'] ?? 'false') == 'true',
    );
  }

  AppSettings copyWith({
    String? theme,
    int? refreshIntervalMinutes,
    int? articleLimit,
    bool? markReadOnScroll,
    bool? driveBackupEnabled,
    int? driveLastBackupAt,
    bool? anthropicApiKeySet,
    String? googleAccountEmail,
    bool? onboardingComplete,
    String? articleFontSize,
    bool? readerMode,
    int? cleanupAgeDays,
    bool? newspaperMode,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      refreshIntervalMinutes: refreshIntervalMinutes ?? this.refreshIntervalMinutes,
      articleLimit: articleLimit ?? this.articleLimit,
      markReadOnScroll: markReadOnScroll ?? this.markReadOnScroll,
      driveBackupEnabled: driveBackupEnabled ?? this.driveBackupEnabled,
      driveLastBackupAt: driveLastBackupAt ?? this.driveLastBackupAt,
      anthropicApiKeySet: anthropicApiKeySet ?? this.anthropicApiKeySet,
      googleAccountEmail: googleAccountEmail ?? this.googleAccountEmail,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      articleFontSize: articleFontSize ?? this.articleFontSize,
      readerMode: readerMode ?? this.readerMode,
      cleanupAgeDays: cleanupAgeDays ?? this.cleanupAgeDays,
      newspaperMode: newspaperMode ?? this.newspaperMode,
    );
  }
}
