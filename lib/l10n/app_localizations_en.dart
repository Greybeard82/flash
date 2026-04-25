// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Flash';

  @override
  String get markAllRead => 'Mark all as read';

  @override
  String get refresh => 'Refresh';

  @override
  String get noArticlesYet => 'No articles yet.\nPull down to refresh.';

  @override
  String get feeds => 'Feeds';

  @override
  String get categories => 'Categories';

  @override
  String get newCategory => 'New category';

  @override
  String get addFeed => 'Add feed';

  @override
  String get noFeedsYet => 'No feeds yet.';

  @override
  String get renameCategory => 'Rename category';

  @override
  String get deleteCategory => 'Delete category';

  @override
  String get removeFeed => 'Remove feed';

  @override
  String get uncategorised => 'Uncategorised';

  @override
  String get addAFeed => 'Add a feed';

  @override
  String get searchHint => 'Search by name or paste a URL';

  @override
  String get noFeedsFound => 'No feeds found. Try a URL instead.';

  @override
  String get followers => 'followers';

  @override
  String get feedAlreadyAdded => 'This feed is already added.';

  @override
  String get couldNotParseFeed => 'Could not parse feed at this URL.';

  @override
  String failedToAddFeed(String error) {
    return 'Failed to add feed: $error';
  }

  @override
  String get defaultFolderName => 'My News';

  @override
  String get categoryName => 'Category name';

  @override
  String get save => 'Save';

  @override
  String get addToCategory => 'Add to category';

  @override
  String get editFeed => 'Edit feed';

  @override
  String get feedName => 'Feed name';

  @override
  String get category => 'Category';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get remove => 'Remove';

  @override
  String renameFolder(String name) {
    return 'Rename \"$name\"';
  }

  @override
  String deleteFolder(String name) {
    return 'Delete \"$name\"';
  }

  @override
  String get edit => 'Edit';

  @override
  String feedRemoved(String title) {
    return '\"$title\" removed';
  }

  @override
  String deleteFolderMessage(String name) {
    return 'Delete \"$name\"? All feeds and articles in this category will be deleted.';
  }

  @override
  String removeFeedMessage(String title) {
    return 'Remove \"$title\"? All cached articles will be deleted.';
  }

  @override
  String get settings => 'Settings';

  @override
  String get reading => 'Reading';

  @override
  String get markReadOnScroll => 'Mark as read on scroll';

  @override
  String get markReadOnScrollSubtitle =>
      'Automatically mark articles as read as you scroll past them';

  @override
  String get backgroundRefreshInterval => 'Background refresh interval';

  @override
  String get every15Minutes => 'Every 15 minutes';

  @override
  String get every30Minutes => 'Every 30 minutes';

  @override
  String get everyHour => 'Every hour';

  @override
  String get every3Hours => 'Every 3 hours';

  @override
  String get every6Hours => 'Every 6 hours';

  @override
  String get manualOnly => 'Manual only';

  @override
  String get storage => 'Storage';

  @override
  String get maxArticlesPerFeed => 'Max articles per feed';

  @override
  String get articles50 => '50 articles';

  @override
  String get articles100 => '100 articles';

  @override
  String get articles200 => '200 articles';

  @override
  String get articles500 => '500 articles';

  @override
  String get unlimited => 'Unlimited';

  @override
  String get filters => 'Filters';

  @override
  String get keywordBlocklist => 'Keyword Blocklist';

  @override
  String get keywordBlocklistSubtitle =>
      'Hide articles matching specific words or phrases';

  @override
  String get backup => 'Backup';

  @override
  String get googleDriveBackup => 'Google Drive Backup';

  @override
  String get connectGoogle => 'Connect Google account';

  @override
  String get backupNow => 'Back up now';

  @override
  String get restoreFromDrive => 'Restore from Drive';

  @override
  String get signOut => 'Sign out';

  @override
  String lastBackup(String date) {
    return 'Last backup: $date';
  }

  @override
  String get backupSuccess => 'Backup saved to Google Drive';

  @override
  String restoreSuccess(int count) {
    return '$count feeds restored. Pull to refresh.';
  }

  @override
  String get restoreConfirmTitle => 'Restore from Drive?';

  @override
  String get restoreConfirmMessage =>
      'This will replace all your current feeds, categories and keywords with the saved backup. Articles will be re-fetched on next refresh.';

  @override
  String get restore => 'Restore';

  @override
  String get noBackupFound => 'No backup found in Drive';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get addKeyword => 'Add keyword';

  @override
  String get noBlockedKeywords => 'No blocked keywords.';

  @override
  String get keywordBlocklistEmpty =>
      'Articles matching a blocked keyword\nwill be hidden from your feed.';

  @override
  String get blockKeyword => 'Block keyword';

  @override
  String get keywordOrPhrase => 'Keyword or phrase';

  @override
  String get keywordHint => 'e.g. sponsored, celebrity name…';

  @override
  String get wholeWordOnly => 'Whole word only';

  @override
  String get wholeWordSubtitle => '\"crypto\" won\'t match \"cryptocurrency\"';

  @override
  String get add => 'Add';

  @override
  String get matchingWholeWord => 'Matching whole word only';

  @override
  String get matchingAnywhere => 'Matching anywhere in text';

  @override
  String get allTab => 'All';

  @override
  String get allMarkedRead => 'All marked as read';

  @override
  String keywordRemoved(String keyword) {
    return '\"$keyword\" removed';
  }

  @override
  String get share => 'Share';

  @override
  String get markRead => 'Mark as read';

  @override
  String get nothingHereYet => 'Nothing here yet.';

  @override
  String get addFirstFeed => 'Add your first feed to get started.';

  @override
  String get addAFeedButton => 'Add a feed';

  @override
  String get onboardingTagline =>
      'Fast, local-first RSS with AI-powered filtering.';

  @override
  String get onboardingBullet1 =>
      'Follow any RSS feed — news, blogs, podcasts.';

  @override
  String get onboardingBullet2 => 'AI summaries, on-device.';

  @override
  String get onboardingBullet3 => 'No accounts. Your data stays on your phone.';

  @override
  String get blockedArticles => 'Blocked Articles';

  @override
  String get noBlockedArticles => 'No blocked articles yet.';

  @override
  String blockedByKeyword(String keyword) {
    return 'Blocked by: $keyword';
  }

  @override
  String get localBackup => 'Local backup file';

  @override
  String get exportBackup => 'Export backup';

  @override
  String get importBackup => 'Import backup';

  @override
  String get localBackupSubtitle =>
      'Save a backup file you can restore from any time';

  @override
  String get invalidBackupFile => 'Not a valid Flash backup file';

  @override
  String get pickACategory => 'Pick a category';

  @override
  String get markAllReadWarningTitle => 'Mark everything as read?';

  @override
  String get markAllReadWarningBody =>
      'This will mark all articles in the current view as read. You won\'t be able to undo this.';

  @override
  String get markAllReadConfirm => 'Mark all read';

  @override
  String get aiSummary => 'AI Summary';

  @override
  String get aiSummaryUnavailable =>
      'On-device AI is not available on this device. Gemini Nano requires a Pixel 8 or newer running Android 14+.';

  @override
  String get aiSummaryDisclaimer =>
      'Generated on-device by Gemini Nano. May not be fully accurate.';

  @override
  String get copySummary => 'Copy summary';

  @override
  String get summaryCopied => 'Summary copied';

  @override
  String get unreadOnly => 'Unread';

  @override
  String get searchArticles => 'Search articles…';

  @override
  String noSearchResults(String query) {
    return 'No articles match \"$query\"';
  }

  @override
  String get readFullArticle => 'Read full article';

  @override
  String get fontSizeSmall => 'S';

  @override
  String get fontSizeMedium => 'M';

  @override
  String get fontSizeLarge => 'L';

  @override
  String get fontSize => 'Font size';

  @override
  String get summary => 'Summary';

  @override
  String get saved => 'Saved';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get noBookmarks =>
      'No bookmarks yet.\nLong-press any article to save it.';

  @override
  String get bookmark => 'Bookmark';

  @override
  String get unbookmark => 'Remove bookmark';

  @override
  String get readerMode => 'Reader mode';

  @override
  String get loadingArticle => 'Loading article…';

  @override
  String get extractionFailed => 'Could not load the full article.';

  @override
  String get readOnWebsite => 'Read on website';

  @override
  String get readerModeSubtitle =>
      'Open articles directly in the app, ad-free. Not all websites are supported — falls back to the browser automatically.';

  @override
  String get keywordAlerts => 'Keyword alerts';

  @override
  String get keywordAlertsSubtitle =>
      'Get notified when tracked keywords appear in new articles';

  @override
  String get noKeywordAlerts => 'No keyword alerts yet.';

  @override
  String get keywordAlertsEmpty =>
      'Add keywords you want to be notified about\nwhen they appear in your feeds.';

  @override
  String get addAlertKeyword => 'Add alert keyword';

  @override
  String get addAlertKeywordSubtitle =>
      'You\'ll get a notification when this word appears in a new article. Case-sensitive.';

  @override
  String get alertKeywordHint => 'e.g. Flutter, climate change…';

  @override
  String get markUnread => 'Mark as unread';

  @override
  String get opml => 'OPML';

  @override
  String get opmlSubtitle =>
      'Import or export your feeds in the universal OPML format, compatible with all RSS readers';

  @override
  String get opmlExport => 'Export OPML';

  @override
  String get opmlImport => 'Import OPML';

  @override
  String get opmlExportSuccess => 'Feeds exported to OPML file';

  @override
  String opmlImportSuccess(int count) {
    return '$count feeds imported';
  }

  @override
  String get changelog => 'Changelog';

  @override
  String get timeJustNow => 'just now';

  @override
  String timeMinAgo(int n) {
    return '${n}m ago';
  }

  @override
  String timeHourAgo(int n) {
    return '${n}h ago';
  }

  @override
  String get timeYesterday => 'yesterday';

  @override
  String timeDaysAgo(int n) {
    return '${n}d ago';
  }

  @override
  String timeWeeksAgo(int n) {
    return '${n}w ago';
  }

  @override
  String timeMonthsAgo(int n) {
    return '${n}mo ago';
  }

  @override
  String timeYearsAgo(int n) {
    return '${n}y ago';
  }
}
