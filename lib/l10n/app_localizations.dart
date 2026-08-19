import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Flash'**
  String get appTitle;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get markAllRead;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @noArticlesYet.
  ///
  /// In en, this message translates to:
  /// **'No articles yet.\nPull down to refresh.'**
  String get noArticlesYet;

  /// No description provided for @noNewArticles.
  ///
  /// In en, this message translates to:
  /// **'No new articles.\nYou\'re all caught up.'**
  String get noNewArticles;

  /// No description provided for @feeds.
  ///
  /// In en, this message translates to:
  /// **'Feeds'**
  String get feeds;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @newCategory.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get newCategory;

  /// No description provided for @addFeed.
  ///
  /// In en, this message translates to:
  /// **'Add feed'**
  String get addFeed;

  /// No description provided for @noFeedsYet.
  ///
  /// In en, this message translates to:
  /// **'No feeds yet.'**
  String get noFeedsYet;

  /// No description provided for @renameCategory.
  ///
  /// In en, this message translates to:
  /// **'Rename category'**
  String get renameCategory;

  /// No description provided for @deleteCategory.
  ///
  /// In en, this message translates to:
  /// **'Delete category'**
  String get deleteCategory;

  /// No description provided for @removeFeed.
  ///
  /// In en, this message translates to:
  /// **'Remove feed'**
  String get removeFeed;

  /// No description provided for @addAFeed.
  ///
  /// In en, this message translates to:
  /// **'Add a feed'**
  String get addAFeed;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or paste a URL'**
  String get searchHint;

  /// No description provided for @noFeedsFound.
  ///
  /// In en, this message translates to:
  /// **'No feeds found. Try a URL instead.'**
  String get noFeedsFound;

  /// No description provided for @followers.
  ///
  /// In en, this message translates to:
  /// **'followers'**
  String get followers;

  /// No description provided for @feedAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'This feed is already added.'**
  String get feedAlreadyAdded;

  /// No description provided for @couldNotParseFeed.
  ///
  /// In en, this message translates to:
  /// **'Could not parse feed at this URL.'**
  String get couldNotParseFeed;

  /// No description provided for @failedToAddFeed.
  ///
  /// In en, this message translates to:
  /// **'Failed to add feed: {error}'**
  String failedToAddFeed(String error);

  /// No description provided for @defaultFolderName.
  ///
  /// In en, this message translates to:
  /// **'My News'**
  String get defaultFolderName;

  /// No description provided for @categoryName.
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get categoryName;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @addToCategory.
  ///
  /// In en, this message translates to:
  /// **'Add to category'**
  String get addToCategory;

  /// No description provided for @editFeed.
  ///
  /// In en, this message translates to:
  /// **'Edit feed'**
  String get editFeed;

  /// No description provided for @feedName.
  ///
  /// In en, this message translates to:
  /// **'Feed name'**
  String get feedName;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @renameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename \"{name}\"'**
  String renameFolder(String name);

  /// No description provided for @deleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"'**
  String deleteFolder(String name);

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @feedRemoved.
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" removed'**
  String feedRemoved(String title);

  /// No description provided for @deleteFolderMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? All feeds and articles in this category will be deleted.'**
  String deleteFolderMessage(String name);

  /// No description provided for @removeFeedMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{title}\"? All cached articles will be deleted.'**
  String removeFeedMessage(String title);

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @reading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get reading;

  /// No description provided for @markReadOnScroll.
  ///
  /// In en, this message translates to:
  /// **'Mark as read on scroll'**
  String get markReadOnScroll;

  /// No description provided for @markReadOnScrollSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically mark articles as read as you scroll past them'**
  String get markReadOnScrollSubtitle;

  /// No description provided for @backgroundRefreshInterval.
  ///
  /// In en, this message translates to:
  /// **'Background refresh interval'**
  String get backgroundRefreshInterval;

  /// No description provided for @every15Minutes.
  ///
  /// In en, this message translates to:
  /// **'Every 15 minutes'**
  String get every15Minutes;

  /// No description provided for @every30Minutes.
  ///
  /// In en, this message translates to:
  /// **'Every 30 minutes'**
  String get every30Minutes;

  /// No description provided for @everyHour.
  ///
  /// In en, this message translates to:
  /// **'Every hour'**
  String get everyHour;

  /// No description provided for @every3Hours.
  ///
  /// In en, this message translates to:
  /// **'Every 3 hours'**
  String get every3Hours;

  /// No description provided for @every6Hours.
  ///
  /// In en, this message translates to:
  /// **'Every 6 hours'**
  String get every6Hours;

  /// No description provided for @manualOnly.
  ///
  /// In en, this message translates to:
  /// **'Manual only'**
  String get manualOnly;

  /// No description provided for @storage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// No description provided for @maxArticlesPerFeed.
  ///
  /// In en, this message translates to:
  /// **'Max articles per feed'**
  String get maxArticlesPerFeed;

  /// No description provided for @articles50.
  ///
  /// In en, this message translates to:
  /// **'50 articles'**
  String get articles50;

  /// No description provided for @articles100.
  ///
  /// In en, this message translates to:
  /// **'100 articles'**
  String get articles100;

  /// No description provided for @articles200.
  ///
  /// In en, this message translates to:
  /// **'200 articles'**
  String get articles200;

  /// No description provided for @articles500.
  ///
  /// In en, this message translates to:
  /// **'500 articles'**
  String get articles500;

  /// No description provided for @unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get unlimited;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @keywordBlocklist.
  ///
  /// In en, this message translates to:
  /// **'Keyword Blocklist'**
  String get keywordBlocklist;

  /// No description provided for @keywordBlocklistSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide articles matching specific words or phrases'**
  String get keywordBlocklistSubtitle;

  /// No description provided for @backup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backup;

  /// No description provided for @googleDriveBackup.
  ///
  /// In en, this message translates to:
  /// **'Google Drive Backup'**
  String get googleDriveBackup;

  /// No description provided for @connectGoogle.
  ///
  /// In en, this message translates to:
  /// **'Connect Google account'**
  String get connectGoogle;

  /// No description provided for @backupNow.
  ///
  /// In en, this message translates to:
  /// **'Back up now'**
  String get backupNow;

  /// No description provided for @restoreFromDrive.
  ///
  /// In en, this message translates to:
  /// **'Restore from Drive'**
  String get restoreFromDrive;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @lastBackup.
  ///
  /// In en, this message translates to:
  /// **'Last backup: {date}'**
  String lastBackup(String date);

  /// No description provided for @backupSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup saved to Google Drive'**
  String get backupSuccess;

  /// No description provided for @restoreSuccess.
  ///
  /// In en, this message translates to:
  /// **'{count} feeds restored. Pull to refresh.'**
  String restoreSuccess(int count);

  /// No description provided for @restoreConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore from Drive?'**
  String get restoreConfirmTitle;

  /// No description provided for @restoreConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This will replace all your current feeds, categories and keywords with the saved backup. Articles will be re-fetched on next refresh.'**
  String get restoreConfirmMessage;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @noBackupFound.
  ///
  /// In en, this message translates to:
  /// **'No backup found in Drive'**
  String get noBackupFound;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @addKeyword.
  ///
  /// In en, this message translates to:
  /// **'Add keyword'**
  String get addKeyword;

  /// No description provided for @noBlockedKeywords.
  ///
  /// In en, this message translates to:
  /// **'No blocked keywords.'**
  String get noBlockedKeywords;

  /// No description provided for @keywordBlocklistEmpty.
  ///
  /// In en, this message translates to:
  /// **'Articles matching a blocked keyword\nwill be hidden from your feed.'**
  String get keywordBlocklistEmpty;

  /// No description provided for @blockKeyword.
  ///
  /// In en, this message translates to:
  /// **'Block keyword'**
  String get blockKeyword;

  /// No description provided for @keywordOrPhrase.
  ///
  /// In en, this message translates to:
  /// **'Keyword or phrase'**
  String get keywordOrPhrase;

  /// No description provided for @keywordHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. sponsored, celebrity name…'**
  String get keywordHint;

  /// No description provided for @wholeWordOnly.
  ///
  /// In en, this message translates to:
  /// **'Whole word only'**
  String get wholeWordOnly;

  /// No description provided for @wholeWordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'\"crypto\" won\'t match \"cryptocurrency\"'**
  String get wholeWordSubtitle;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @matchingWholeWord.
  ///
  /// In en, this message translates to:
  /// **'Matching whole word only'**
  String get matchingWholeWord;

  /// No description provided for @matchingAnywhere.
  ///
  /// In en, this message translates to:
  /// **'Matching anywhere in text'**
  String get matchingAnywhere;

  /// No description provided for @allTab.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get allTab;

  /// No description provided for @allMarkedRead.
  ///
  /// In en, this message translates to:
  /// **'All marked as read'**
  String get allMarkedRead;

  /// No description provided for @keywordRemoved.
  ///
  /// In en, this message translates to:
  /// **'\"{keyword}\" removed'**
  String keywordRemoved(String keyword);

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @markRead.
  ///
  /// In en, this message translates to:
  /// **'Mark as read'**
  String get markRead;

  /// No description provided for @nothingHereYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get nothingHereYet;

  /// No description provided for @addFirstFeed.
  ///
  /// In en, this message translates to:
  /// **'Add your first feed to get started.'**
  String get addFirstFeed;

  /// No description provided for @addAFeedButton.
  ///
  /// In en, this message translates to:
  /// **'Add a feed'**
  String get addAFeedButton;

  /// No description provided for @onboardingTagline.
  ///
  /// In en, this message translates to:
  /// **'Fast, local-first RSS with AI-powered filtering.'**
  String get onboardingTagline;

  /// No description provided for @onboardingBullet1.
  ///
  /// In en, this message translates to:
  /// **'Follow any RSS feed — news, blogs, podcasts.'**
  String get onboardingBullet1;

  /// No description provided for @onboardingBullet2.
  ///
  /// In en, this message translates to:
  /// **'AI summaries, on-device.'**
  String get onboardingBullet2;

  /// No description provided for @onboardingBullet3.
  ///
  /// In en, this message translates to:
  /// **'No accounts. Your data stays on your phone.'**
  String get onboardingBullet3;

  /// No description provided for @blockedArticles.
  ///
  /// In en, this message translates to:
  /// **'Blocked Articles'**
  String get blockedArticles;

  /// No description provided for @noBlockedArticles.
  ///
  /// In en, this message translates to:
  /// **'No blocked articles yet.'**
  String get noBlockedArticles;

  /// No description provided for @blockedByKeyword.
  ///
  /// In en, this message translates to:
  /// **'Blocked by: {keyword}'**
  String blockedByKeyword(String keyword);

  /// No description provided for @localBackup.
  ///
  /// In en, this message translates to:
  /// **'Local backup file'**
  String get localBackup;

  /// No description provided for @exportBackup.
  ///
  /// In en, this message translates to:
  /// **'Export backup'**
  String get exportBackup;

  /// No description provided for @importBackup.
  ///
  /// In en, this message translates to:
  /// **'Import backup'**
  String get importBackup;

  /// No description provided for @localBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save a backup file you can restore from any time'**
  String get localBackupSubtitle;

  /// No description provided for @invalidBackupFile.
  ///
  /// In en, this message translates to:
  /// **'Not a valid Flash backup file'**
  String get invalidBackupFile;

  /// No description provided for @pickACategory.
  ///
  /// In en, this message translates to:
  /// **'Pick a category'**
  String get pickACategory;

  /// No description provided for @markAllReadWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Mark everything as read?'**
  String get markAllReadWarningTitle;

  /// No description provided for @markAllReadWarningBody.
  ///
  /// In en, this message translates to:
  /// **'This will mark all articles in the current view as read. You won\'t be able to undo this.'**
  String get markAllReadWarningBody;

  /// No description provided for @markAllReadConfirm.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllReadConfirm;

  /// No description provided for @aiSummary.
  ///
  /// In en, this message translates to:
  /// **'AI Summary'**
  String get aiSummary;

  /// No description provided for @aiSummaryUnavailable.
  ///
  /// In en, this message translates to:
  /// **'On-device AI is not available on this device. Gemini Nano requires a Pixel 8 or newer running Android 14+.'**
  String get aiSummaryUnavailable;

  /// No description provided for @aiSummaryDisclaimer.
  ///
  /// In en, this message translates to:
  /// **'Generated on-device by Gemini Nano. May not be fully accurate.'**
  String get aiSummaryDisclaimer;

  /// No description provided for @aiSummaryReading.
  ///
  /// In en, this message translates to:
  /// **'Reading the article…'**
  String get aiSummaryReading;

  /// No description provided for @aiSummaryWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing the summary…'**
  String get aiSummaryWriting;

  /// No description provided for @aiSummaryTeaserOnly.
  ///
  /// In en, this message translates to:
  /// **'Based on the article preview only.'**
  String get aiSummaryTeaserOnly;

  /// No description provided for @copySummary.
  ///
  /// In en, this message translates to:
  /// **'Copy summary'**
  String get copySummary;

  /// No description provided for @summaryCopied.
  ///
  /// In en, this message translates to:
  /// **'Summary copied'**
  String get summaryCopied;

  /// No description provided for @unreadOnly.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get unreadOnly;

  /// No description provided for @searchArticles.
  ///
  /// In en, this message translates to:
  /// **'Search articles…'**
  String get searchArticles;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No articles match \"{query}\"'**
  String noSearchResults(String query);

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @noBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks yet.\nLong-press any article to save it.'**
  String get noBookmarks;

  /// No description provided for @bookmark.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get bookmark;

  /// No description provided for @unbookmark.
  ///
  /// In en, this message translates to:
  /// **'Remove bookmark'**
  String get unbookmark;

  /// No description provided for @keywordAlerts.
  ///
  /// In en, this message translates to:
  /// **'Keyword alerts'**
  String get keywordAlerts;

  /// No description provided for @keywordAlertsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get notified when tracked keywords appear in new articles'**
  String get keywordAlertsSubtitle;

  /// No description provided for @noKeywordAlerts.
  ///
  /// In en, this message translates to:
  /// **'No keyword alerts yet.'**
  String get noKeywordAlerts;

  /// No description provided for @keywordAlertsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add keywords you want to be notified about\nwhen they appear in your feeds.'**
  String get keywordAlertsEmpty;

  /// No description provided for @addAlertKeyword.
  ///
  /// In en, this message translates to:
  /// **'Add alert keyword'**
  String get addAlertKeyword;

  /// No description provided for @addAlertKeywordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You\'ll get a notification when this word appears in a new article. Case-sensitive.'**
  String get addAlertKeywordSubtitle;

  /// No description provided for @alertKeywordHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Flutter, climate change…'**
  String get alertKeywordHint;

  /// No description provided for @markUnread.
  ///
  /// In en, this message translates to:
  /// **'Mark as unread'**
  String get markUnread;

  /// No description provided for @opml.
  ///
  /// In en, this message translates to:
  /// **'OPML'**
  String get opml;

  /// No description provided for @opmlSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import or export your feeds in the universal OPML format, compatible with all RSS readers'**
  String get opmlSubtitle;

  /// No description provided for @opmlExport.
  ///
  /// In en, this message translates to:
  /// **'Export OPML'**
  String get opmlExport;

  /// No description provided for @opmlImport.
  ///
  /// In en, this message translates to:
  /// **'Import OPML'**
  String get opmlImport;

  /// No description provided for @opmlExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Feeds exported to OPML file'**
  String get opmlExportSuccess;

  /// No description provided for @opmlImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'{count} feeds imported'**
  String opmlImportSuccess(int count);

  /// No description provided for @changelog.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get changelog;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeJustNow;

  /// No description provided for @timeMinAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}m ago'**
  String timeMinAgo(int n);

  /// No description provided for @timeHourAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}h ago'**
  String timeHourAgo(int n);

  /// No description provided for @timeYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get timeYesterday;

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}d ago'**
  String timeDaysAgo(int n);

  /// No description provided for @timeWeeksAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}w ago'**
  String timeWeeksAgo(int n);

  /// No description provided for @timeMonthsAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}mo ago'**
  String timeMonthsAgo(int n);

  /// No description provided for @timeYearsAgo.
  ///
  /// In en, this message translates to:
  /// **'{n}y ago'**
  String timeYearsAgo(int n);

  /// No description provided for @newspaperMode.
  ///
  /// In en, this message translates to:
  /// **'Newspaper mode'**
  String get newspaperMode;

  /// No description provided for @newspaperModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read your feed as a printed paper'**
  String get newspaperModeSubtitle;

  /// No description provided for @newspaperModeOverridesTheme.
  ///
  /// In en, this message translates to:
  /// **'Appearance is set by Newspaper mode'**
  String get newspaperModeOverridesTheme;

  /// No description provided for @moveFeedFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save that change'**
  String get moveFeedFailed;

  /// No description provided for @refreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t refresh — check your connection'**
  String get refreshFailed;

  /// No description provided for @autoMarkReadAtBottom.
  ///
  /// In en, this message translates to:
  /// **'Mark all read at end of feed'**
  String get autoMarkReadAtBottom;

  /// No description provided for @autoMarkReadAtBottomSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reaching the bottom marks every article in this feed as read'**
  String get autoMarkReadAtBottomSubtitle;

  /// No description provided for @autoMarkReadDelay.
  ///
  /// In en, this message translates to:
  /// **'Wait before marking'**
  String get autoMarkReadDelay;

  /// No description provided for @autoMarkReadImmediately.
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get autoMarkReadImmediately;

  /// No description provided for @autoMarkReadAfterSeconds.
  ///
  /// In en, this message translates to:
  /// **'After {n}s'**
  String autoMarkReadAfterSeconds(int n);

  /// No description provided for @filterBubbleTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterBubbleTitle;

  /// No description provided for @quickSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick settings'**
  String get quickSettingsTitle;

  /// No description provided for @articleAgeFilter.
  ///
  /// In en, this message translates to:
  /// **'Article age'**
  String get articleAgeFilter;

  /// No description provided for @articlesCount.
  ///
  /// In en, this message translates to:
  /// **'{n} articles'**
  String articlesCount(int n);

  /// No description provided for @daysCount.
  ///
  /// In en, this message translates to:
  /// **'{n} days'**
  String daysCount(int n);

  /// No description provided for @filterBubbleFootnote.
  ///
  /// In en, this message translates to:
  /// **'Also editable in Settings. Applies to every feed.'**
  String get filterBubbleFootnote;

  /// No description provided for @filterTooltip.
  ///
  /// In en, this message translates to:
  /// **'Filter articles'**
  String get filterTooltip;

  /// No description provided for @quickSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Quick settings'**
  String get quickSettingsTooltip;

  /// No description provided for @articleOrder.
  ///
  /// In en, this message translates to:
  /// **'Article order'**
  String get articleOrder;

  /// No description provided for @newestFirst.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get newestFirst;

  /// No description provided for @oldestFirst.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get oldestFirst;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'es', 'fr', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
