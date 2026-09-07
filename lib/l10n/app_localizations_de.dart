// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Flash';

  @override
  String get markAllRead => 'Alle als gelesen markieren';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get noArticlesYet =>
      'Noch keine Artikel.\nZum Aktualisieren nach unten ziehen.';

  @override
  String get noNewArticles =>
      'Keine neuen Artikel.\nAlles auf dem neuesten Stand.';

  @override
  String get feeds => 'Feeds';

  @override
  String get categories => 'Kategorien';

  @override
  String get newCategory => 'Neue Kategorie';

  @override
  String get addFeed => 'Feed hinzufügen';

  @override
  String get noFeedsYet => 'Noch keine Feeds.';

  @override
  String get renameCategory => 'Kategorie umbenennen';

  @override
  String get deleteCategory => 'Kategorie löschen';

  @override
  String get removeFeed => 'Feed entfernen';

  @override
  String get addAFeed => 'Feed hinzufügen';

  @override
  String get searchHint => 'Nach Name suchen oder URL einfügen';

  @override
  String get noFeedsFound => 'Keine Feeds gefunden. Versuche eine URL.';

  @override
  String get followers => 'Abonnenten';

  @override
  String get feedAlreadyAdded => 'Dieser Feed wurde bereits hinzugefügt.';

  @override
  String get couldNotParseFeed =>
      'Feed unter dieser URL konnte nicht gelesen werden.';

  @override
  String failedToAddFeed(String error) {
    return 'Feed konnte nicht hinzugefügt werden: $error';
  }

  @override
  String get defaultFolderName => 'Meine Nachrichten';

  @override
  String get categoryName => 'Kategoriename';

  @override
  String get save => 'Speichern';

  @override
  String get addToCategory => 'Zur Kategorie hinzufügen';

  @override
  String get editFeed => 'Feed bearbeiten';

  @override
  String get feedName => 'Feed-Name';

  @override
  String get category => 'Kategorie';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get delete => 'Löschen';

  @override
  String get remove => 'Entfernen';

  @override
  String renameFolder(String name) {
    return '\"$name\" umbenennen';
  }

  @override
  String deleteFolder(String name) {
    return '\"$name\" löschen';
  }

  @override
  String get edit => 'Bearbeiten';

  @override
  String feedRemoved(String title) {
    return '\"$title\" entfernt';
  }

  @override
  String deleteFolderMessage(String name) {
    return '\"$name\" löschen? Alle Feeds und Artikel in dieser Kategorie werden gelöscht.';
  }

  @override
  String removeFeedMessage(String title) {
    return '\"$title\" entfernen? Alle zwischengespeicherten Artikel werden gelöscht.';
  }

  @override
  String get settings => 'Einstellungen';

  @override
  String get reading => 'Lesen';

  @override
  String get markReadOnScroll => 'Beim Scrollen als gelesen markieren';

  @override
  String get markReadOnScrollSubtitle =>
      'Artikel werden beim Scrollen automatisch als gelesen markiert';

  @override
  String get backgroundRefreshInterval => 'Aktualisierungsintervall';

  @override
  String get every15Minutes => 'Alle 15 Minuten';

  @override
  String get every30Minutes => 'Alle 30 Minuten';

  @override
  String get everyHour => 'Jede Stunde';

  @override
  String get every3Hours => 'Alle 3 Stunden';

  @override
  String get every6Hours => 'Alle 6 Stunden';

  @override
  String get manualOnly => 'Nur manuell';

  @override
  String get maxArticlesPerFeed => 'Max. Artikel pro Feed';

  @override
  String get filters => 'Filter';

  @override
  String get keywordBlocklist => 'Stichwort-Sperrliste';

  @override
  String get keywordBlocklistSubtitle =>
      'Artikel mit bestimmten Wörtern oder Phrasen ausblenden';

  @override
  String get backup => 'Sicherung';

  @override
  String get googleDriveBackup => 'Google Drive Sicherung';

  @override
  String get connectGoogle => 'Google-Konto verbinden';

  @override
  String get backupNow => 'Jetzt sichern';

  @override
  String get restoreFromDrive => 'Von Drive wiederherstellen';

  @override
  String get signOut => 'Abmelden';

  @override
  String lastBackup(String date) {
    return 'Letzte Sicherung: $date';
  }

  @override
  String get backupSuccess => 'Sicherung auf Google Drive gespeichert';

  @override
  String restoreSuccess(int count) {
    return '$count Feeds wiederhergestellt. Zum Aktualisieren ziehen.';
  }

  @override
  String get restoreConfirmTitle => 'Von Drive wiederherstellen?';

  @override
  String get restoreConfirmMessage =>
      'Dadurch werden alle aktuellen Feeds, Kategorien und gesperrten Stichwörter durch die gespeicherte Sicherung ersetzt. Artikel werden beim nächsten Aktualisieren abgerufen.';

  @override
  String get restore => 'Wiederherstellen';

  @override
  String get noBackupFound => 'Keine Sicherung in Drive gefunden';

  @override
  String get theme => 'Design';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get colorPalette => 'Farbpalette';

  @override
  String get paletteGreen => 'Grün & Gold';

  @override
  String get paletteBlue => 'Blau & Terrakotta';

  @override
  String get paletteOrange => 'Orange & Waldgrün';

  @override
  String get paletteRed => 'Rot & Indigo';

  @override
  String get paletteTealOrange => 'Petrol & Orange';

  @override
  String get addKeyword => 'Stichwort hinzufügen';

  @override
  String get noBlockedKeywords => 'Keine gesperrten Stichwörter.';

  @override
  String get keywordBlocklistEmpty =>
      'Artikel, die ein gesperrtes Stichwort enthalten,\nwerden aus deinem Feed ausgeblendet.';

  @override
  String get blockKeyword => 'Stichwort sperren';

  @override
  String get keywordOrPhrase => 'Stichwort oder Phrase';

  @override
  String get keywordHint => 'z.B. Werbung, Prominame…';

  @override
  String get wholeWordOnly => 'Nur ganzes Wort';

  @override
  String get wholeWordSubtitle => '\"Krypto\" trifft nicht \"Kryptografie\"';

  @override
  String get add => 'Hinzufügen';

  @override
  String get matchingWholeWord => 'Nur vollständige Wortübereinstimmung';

  @override
  String get matchingAnywhere => 'Übereinstimmung irgendwo im Text';

  @override
  String get allTab => 'Alle';

  @override
  String get allMarkedRead => 'Alles als gelesen markiert';

  @override
  String alertKeywordExists(String keyword) {
    return '\"$keyword\" ist bereits ein Alarm-Stichwort';
  }

  @override
  String keywordRemoved(String keyword) {
    return '\"$keyword\" entfernt';
  }

  @override
  String get share => 'Teilen';

  @override
  String get markRead => 'Als gelesen markieren';

  @override
  String get nothingHereYet => 'Noch nichts hier.';

  @override
  String get addFirstFeed => 'Füge deinen ersten Feed hinzu, um loszulegen.';

  @override
  String get addAFeedButton => 'Feed hinzufügen';

  @override
  String get onboardingTagline =>
      'Schneller, lokaler RSS-Reader mit KI-Filterung.';

  @override
  String get onboardingBullet1 =>
      'Folge jedem RSS-Feed — Nachrichten, Blogs, Podcasts.';

  @override
  String get onboardingBullet2 => 'KI-Zusammenfassungen, auf dem Gerät.';

  @override
  String get onboardingBullet3 =>
      'Kein Konto. Deine Daten bleiben auf deinem Handy.';

  @override
  String get localBackup => 'Lokale Sicherungsdatei';

  @override
  String get exportBackup => 'Sicherung exportieren';

  @override
  String get importBackup => 'Sicherung importieren';

  @override
  String get localBackupSubtitle =>
      'Speichere eine Sicherungsdatei, die du jederzeit wiederherstellen kannst';

  @override
  String get invalidBackupFile => 'Keine gültige Flash-Sicherungsdatei';

  @override
  String get pickACategory => 'Kategorie auswählen';

  @override
  String get markAllReadWarningTitle => 'Alles als gelesen markieren?';

  @override
  String get markAllReadWarningBody =>
      'Alle Artikel in der aktuellen Ansicht werden als gelesen markiert und aus dem Feed entfernt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get markAllReadConfirm => 'Alle als gelesen markieren';

  @override
  String get aiSummary => 'KI-Zusammenfassung';

  @override
  String get aiSummaryUnavailable =>
      'Die KI auf dem Gerät ist nicht verfügbar. Gemini Nano erfordert ein Pixel 8 oder neuer mit Android 14+.';

  @override
  String get aiSummaryDisclaimer =>
      'Auf dem Gerät von Gemini Nano generiert. Möglicherweise nicht vollständig korrekt.';

  @override
  String get aiSummaryReading => 'Artikel wird gelesen…';

  @override
  String get aiSummaryWriting => 'Zusammenfassung wird geschrieben…';

  @override
  String get aiSummaryTeaserOnly => 'Basiert nur auf der Artikelvorschau.';

  @override
  String get copySummary => 'Zusammenfassung kopieren';

  @override
  String get summaryCopied => 'Zusammenfassung kopiert';

  @override
  String get unreadOnly => 'Ungelesen';

  @override
  String get searchArticles => 'Artikel suchen…';

  @override
  String noSearchResults(String query) {
    return 'Keine Artikel zu \"$query\" gefunden';
  }

  @override
  String get summary => 'Zusammenfassung';

  @override
  String get saved => 'Gespeichert';

  @override
  String get bookmarks => 'Gespeichert';

  @override
  String get noBookmarks =>
      'Noch nichts gespeichert.\nArtikel lang drücken, um ihn zu speichern.';

  @override
  String get bookmark => 'Speichern';

  @override
  String get unbookmark => 'Aus Gespeichert entfernen';

  @override
  String get keywordAlerts => 'Stichwort-Benachrichtigungen';

  @override
  String get keywordAlertsSubtitle =>
      'Benachrichtigungen wenn überwachte Stichwörter in neuen Artikeln erscheinen';

  @override
  String get noKeywordAlerts => 'Noch keine Stichwort-Benachrichtigungen.';

  @override
  String get keywordAlertsEmpty =>
      'Füge Stichwörter hinzu, über die du benachrichtigt werden möchtest\nwenn sie in deinen Feeds erscheinen.';

  @override
  String get addAlertKeyword => 'Benachrichtigung hinzufügen';

  @override
  String get addAlertKeywordSubtitle =>
      'Du wirst benachrichtigt, wenn dieses Wort in einem neuen Artikel erscheint. Groß-/Kleinschreibung beachten.';

  @override
  String get alertKeywordHint => 'z.B. Flutter, Klimawandel…';

  @override
  String get markUnread => 'Als ungelesen markieren';

  @override
  String get timeJustNow => 'gerade eben';

  @override
  String timeMinAgo(int n) {
    return 'vor ${n}Min';
  }

  @override
  String timeHourAgo(int n) {
    return 'vor ${n}Std';
  }

  @override
  String get timeYesterday => 'gestern';

  @override
  String timeDaysAgo(int n) {
    return 'vor ${n}T';
  }

  @override
  String timeWeeksAgo(int n) {
    return 'vor ${n}Wo';
  }

  @override
  String timeMonthsAgo(int n) {
    return 'vor ${n}Mo';
  }

  @override
  String timeYearsAgo(int n) {
    return 'vor ${n}J';
  }

  @override
  String get newspaperMode => 'Zeitungsmodus';

  @override
  String get newspaperModeSubtitle => 'Feed als gedruckte Zeitung lesen';

  @override
  String get newspaperModeOverridesTheme =>
      'Erscheinungsbild wird vom Zeitungsmodus bestimmt';

  @override
  String get moveFeedFailed => 'Änderung konnte nicht gespeichert werden';

  @override
  String get refreshFailed =>
      'Aktualisierung fehlgeschlagen — bitte Verbindung prüfen';

  @override
  String get filterBubbleTitle => 'Filter';

  @override
  String get quickSettingsTitle => 'Schnelleinstellungen';

  @override
  String get articleAgeFilter => 'Artikelalter';

  @override
  String articlesCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Artikel',
      one: '1 Artikel',
    );
    return '$_temp0';
  }

  @override
  String daysCount(int n) {
    return '$n Tage';
  }

  @override
  String get filterBubbleFootnote => 'Gilt für alle Feeds.';

  @override
  String get filterTooltip => 'Artikel filtern';

  @override
  String get quickSettingsTooltip => 'Schnelleinstellungen';

  @override
  String get articleOrder => 'Reihenfolge';

  @override
  String get newestFirst => 'Neueste';

  @override
  String get oldestFirst => 'Älteste';

  @override
  String get apply => 'Übernehmen';

  @override
  String unreadCountNotification(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ungelesene Artikel',
      one: '1 ungelesener Artikel',
    );
    return '$_temp0';
  }

  @override
  String get iconBadge => 'Symbol-Zähler';

  @override
  String get moreSettings => 'Weitere Einstellungen';

  @override
  String get showRead => 'Gelesene anzeigen';

  @override
  String get showReadSubtitle =>
      'Gelesene Artikel bis zur nächsten Aktualisierung behalten';

  @override
  String get dayToday => 'Heute';

  @override
  String get dayYesterday => 'Gestern';

  @override
  String get dontShowAgain => 'Nicht mehr anzeigen';

  @override
  String get confirmMarkAllRead => 'Alle als gelesen bestätigen';

  @override
  String get selectCategoryFirst => 'Wähle eine Kategorie, um fortzufahren.';

  @override
  String get alertsTab => 'Benachrichtigungen';

  @override
  String get alertsTabEmpty =>
      'Noch keine Treffer.\nArtikel, die deine Stichwörter enthalten, erscheinen hier.';

  @override
  String get alertsFilterAll => 'Alle';

  @override
  String get alertsManageKeywords => 'Stichwörter verwalten';

  @override
  String get alertsRemove => 'Entfernen';

  @override
  String get alertsRemovedBanner => 'Aus Benachrichtigungen entfernt';

  @override
  String get alertsMarkAllReadBanner =>
      'Alle Benachrichtigungen als gelesen markiert';

  @override
  String get alertsArticleGone =>
      'Dieser Artikel ist nicht mehr in deinem Feed';

  @override
  String alertsMoreKeywords(int count) {
    return '+$count';
  }

  @override
  String deleteAlertKeywordTitle(String keyword) {
    return '\"$keyword\" löschen?';
  }

  @override
  String deleteAlertKeywordBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel verschwinden aus dem Tab Benachrichtigungen.',
      one: '1 Artikel verschwindet aus dem Tab Benachrichtigungen.',
    );
    return '$_temp0';
  }

  @override
  String get alertNotificationTitle => 'Flash — Stichwort-Treffer';

  @override
  String alertNotificationFirst(String keyword) {
    return '\"$keyword\" ist in einem Artikel aufgetaucht';
  }

  @override
  String alertNotificationCount(int count, String keyword) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel enthalten \"$keyword\"',
      one: '1 Artikel enthält \"$keyword\"',
    );
    return '$_temp0';
  }

  @override
  String alertNotificationCombined(int count, String keywords) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Artikel enthalten die Wörter $keywords',
      one: '1 Artikel enthält die Wörter $keywords',
    );
    return '$_temp0';
  }

  @override
  String get keywordListSeparator => ', ';

  @override
  String get keywordListAnd => ' und ';

  @override
  String get openInBrowser => 'Im Browser öffnen';

  @override
  String get selectAnArticle => 'Wähle einen Artikel, um ihn hier zu lesen';

  @override
  String get builtInViewer => 'Artikel im integrierten Viewer öffnen';
}
