class AppSettings {
  final String theme; // 'system' | 'light' | 'dark'
  final int refreshIntervalMinutes;
  final int articleLimit;
  final bool markReadOnScroll;
  final bool opinionFilterHeuristic;
  final bool opinionFilterAi;
  final bool driveBackupEnabled;
  final int? driveLastBackupAt;
  final bool anthropicApiKeySet;
  final String? googleAccountEmail;
  final bool onboardingComplete;

  const AppSettings({
    this.theme = 'system',
    this.refreshIntervalMinutes = 30,
    this.articleLimit = 100,
    this.markReadOnScroll = true,
    this.opinionFilterHeuristic = true,
    this.opinionFilterAi = false,
    this.driveBackupEnabled = false,
    this.driveLastBackupAt,
    this.anthropicApiKeySet = false,
    this.googleAccountEmail,
    this.onboardingComplete = false,
  });

  factory AppSettings.fromMap(Map<String, String> map) {
    return AppSettings(
      theme: map['theme'] ?? 'system',
      refreshIntervalMinutes: int.tryParse(map['refresh_interval_minutes'] ?? '30') ?? 30,
      articleLimit: int.tryParse(map['article_limit'] ?? '100') ?? 100,
      markReadOnScroll: (map['mark_read_on_scroll'] ?? 'true') == 'true',
      opinionFilterHeuristic: (map['opinion_filter_heuristic'] ?? 'true') == 'true',
      opinionFilterAi: (map['opinion_filter_ai'] ?? 'false') == 'true',
      driveBackupEnabled: (map['drive_backup_enabled'] ?? 'false') == 'true',
      driveLastBackupAt: map['drive_last_backup_at'] != null && map['drive_last_backup_at'] != 'null'
          ? int.tryParse(map['drive_last_backup_at']!)
          : null,
      anthropicApiKeySet: (map['anthropic_api_key_set'] ?? 'false') == 'true',
      googleAccountEmail: map['google_account_email'] == 'null' ? null : map['google_account_email'],
      onboardingComplete: (map['onboarding_complete'] ?? 'false') == 'true',
    );
  }

  AppSettings copyWith({
    String? theme,
    int? refreshIntervalMinutes,
    int? articleLimit,
    bool? markReadOnScroll,
    bool? opinionFilterHeuristic,
    bool? opinionFilterAi,
    bool? driveBackupEnabled,
    int? driveLastBackupAt,
    bool? anthropicApiKeySet,
    String? googleAccountEmail,
    bool? onboardingComplete,
  }) {
    return AppSettings(
      theme: theme ?? this.theme,
      refreshIntervalMinutes: refreshIntervalMinutes ?? this.refreshIntervalMinutes,
      articleLimit: articleLimit ?? this.articleLimit,
      markReadOnScroll: markReadOnScroll ?? this.markReadOnScroll,
      opinionFilterHeuristic: opinionFilterHeuristic ?? this.opinionFilterHeuristic,
      opinionFilterAi: opinionFilterAi ?? this.opinionFilterAi,
      driveBackupEnabled: driveBackupEnabled ?? this.driveBackupEnabled,
      driveLastBackupAt: driveLastBackupAt ?? this.driveLastBackupAt,
      anthropicApiKeySet: anthropicApiKeySet ?? this.anthropicApiKeySet,
      googleAccountEmail: googleAccountEmail ?? this.googleAccountEmail,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }
}
