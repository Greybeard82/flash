// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'Flash';

  @override
  String get markAllRead => 'Segna tutto come letto';

  @override
  String get refresh => 'Aggiorna';

  @override
  String get noArticlesYet =>
      'Nessun articolo ancora.\nTira giù per aggiornare.';

  @override
  String get noNewArticles => 'Nessun nuovo articolo.\nSei in pari.';

  @override
  String get feeds => 'Feed';

  @override
  String get categories => 'Categorie';

  @override
  String get newCategory => 'Nuova categoria';

  @override
  String get addFeed => 'Aggiungi feed';

  @override
  String get noFeedsYet => 'Nessun feed ancora.';

  @override
  String get renameCategory => 'Rinomina categoria';

  @override
  String get deleteCategory => 'Elimina categoria';

  @override
  String get removeFeed => 'Rimuovi feed';

  @override
  String get addAFeed => 'Aggiungi un feed';

  @override
  String get searchHint => 'Cerca per nome o incolla un URL';

  @override
  String get noFeedsFound => 'Nessun feed trovato. Prova con un URL.';

  @override
  String get followers => 'follower';

  @override
  String get feedAlreadyAdded => 'Questo feed è già stato aggiunto.';

  @override
  String get couldNotParseFeed => 'Impossibile leggere il feed a questo URL.';

  @override
  String failedToAddFeed(String error) {
    return 'Impossibile aggiungere il feed: $error';
  }

  @override
  String get defaultFolderName => 'Le Mie Notizie';

  @override
  String get categoryName => 'Nome categoria';

  @override
  String get save => 'Salva';

  @override
  String get addToCategory => 'Aggiungi alla categoria';

  @override
  String get editFeed => 'Modifica feed';

  @override
  String get feedName => 'Nome del feed';

  @override
  String get category => 'Categoria';

  @override
  String get cancel => 'Annulla';

  @override
  String get delete => 'Elimina';

  @override
  String get remove => 'Rimuovi';

  @override
  String renameFolder(String name) {
    return 'Rinomina \"$name\"';
  }

  @override
  String deleteFolder(String name) {
    return 'Elimina \"$name\"';
  }

  @override
  String get edit => 'Modifica';

  @override
  String feedRemoved(String title) {
    return '\"$title\" rimosso';
  }

  @override
  String deleteFolderMessage(String name) {
    return 'Eliminare \"$name\"? Tutti i feed e gli articoli in questa categoria verranno eliminati.';
  }

  @override
  String removeFeedMessage(String title) {
    return 'Rimuovere \"$title\"? Tutti gli articoli in cache verranno eliminati.';
  }

  @override
  String get settings => 'Impostazioni';

  @override
  String get reading => 'Lettura';

  @override
  String get markReadOnScroll => 'Segna come letto scorrendo';

  @override
  String get markReadOnScrollSubtitle =>
      'Segna automaticamente gli articoli come letti mentre scorri';

  @override
  String get backgroundRefreshInterval => 'Intervallo di aggiornamento';

  @override
  String get every15Minutes => 'Ogni 15 minuti';

  @override
  String get every30Minutes => 'Ogni 30 minuti';

  @override
  String get everyHour => 'Ogni ora';

  @override
  String get every3Hours => 'Ogni 3 ore';

  @override
  String get every6Hours => 'Ogni 6 ore';

  @override
  String get manualOnly => 'Solo manuale';

  @override
  String get maxArticlesPerFeed => 'Max articoli per feed';

  @override
  String get filters => 'Filtri';

  @override
  String get keywordBlocklist => 'Lista parole bloccate';

  @override
  String get keywordBlocklistSubtitle =>
      'Nascondi articoli che contengono parole o frasi specifiche';

  @override
  String get backup => 'Backup';

  @override
  String get googleDriveBackup => 'Backup su Google Drive';

  @override
  String get connectGoogle => 'Collega account Google';

  @override
  String get backupNow => 'Esegui backup ora';

  @override
  String get restoreFromDrive => 'Ripristina da Drive';

  @override
  String get signOut => 'Disconnetti';

  @override
  String lastBackup(String date) {
    return 'Ultimo backup: $date';
  }

  @override
  String get backupSuccess => 'Backup salvato su Google Drive';

  @override
  String restoreSuccess(int count) {
    return '$count feed ripristinati. Trascina per aggiornare.';
  }

  @override
  String get restoreConfirmTitle => 'Ripristinare da Drive?';

  @override
  String get restoreConfirmMessage =>
      'Questo sostituirà tutti i tuoi feed, categorie e parole bloccate attuali con il backup salvato. Gli articoli verranno recuperati al prossimo aggiornamento.';

  @override
  String get restore => 'Ripristina';

  @override
  String get noBackupFound => 'Nessun backup trovato in Drive';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get colorPalette => 'Tavolozza colori';

  @override
  String get paletteGreen => 'Verde';

  @override
  String get paletteBlue => 'Blu';

  @override
  String get paletteOrange => 'Arancione';

  @override
  String get paletteRed => 'Rosso';

  @override
  String get paletteTealOrange => 'Verde acqua e arancione';

  @override
  String get addKeyword => 'Aggiungi parola';

  @override
  String get noBlockedKeywords => 'Nessuna parola bloccata.';

  @override
  String get keywordBlocklistEmpty =>
      'Gli articoli che contengono una parola bloccata\nverranno nascosti dal tuo feed.';

  @override
  String get blockKeyword => 'Blocca parola';

  @override
  String get keywordOrPhrase => 'Parola o frase';

  @override
  String get keywordHint => 'Es. sponsorizzato, nome di celebrità…';

  @override
  String get wholeWordOnly => 'Solo parola intera';

  @override
  String get wholeWordSubtitle =>
      '\"cripto\" non corrisponderà a \"crittografia\"';

  @override
  String get add => 'Aggiungi';

  @override
  String get matchingWholeWord => 'Corrispondenza solo parola intera';

  @override
  String get matchingAnywhere => 'Corrispondenza ovunque nel testo';

  @override
  String get allTab => 'Tutti';

  @override
  String get allMarkedRead => 'Tutto segnato come letto';

  @override
  String keywordRemoved(String keyword) {
    return '\"$keyword\" rimossa';
  }

  @override
  String get share => 'Condividi';

  @override
  String get markRead => 'Segna come letto';

  @override
  String get nothingHereYet => 'Niente ancora qui.';

  @override
  String get addFirstFeed => 'Aggiungi il tuo primo feed per iniziare.';

  @override
  String get addAFeedButton => 'Aggiungi un feed';

  @override
  String get onboardingTagline =>
      'RSS veloce, locale, con filtri AI integrati.';

  @override
  String get onboardingBullet1 =>
      'Segui qualsiasi feed RSS — notizie, blog, podcast.';

  @override
  String get onboardingBullet2 => 'Riassunti AI, sul dispositivo.';

  @override
  String get onboardingBullet3 =>
      'Nessun account. I tuoi dati restano sul telefono.';

  @override
  String get blockedArticles => 'Articoli bloccati';

  @override
  String get noBlockedArticles => 'Nessun articolo bloccato ancora.';

  @override
  String blockedByKeyword(String keyword) {
    return 'Bloccato da: $keyword';
  }

  @override
  String get matchedArticles => 'Articoli corrispondenti';

  @override
  String matchedByKeyword(String keyword) {
    return 'Corrisponde a: $keyword';
  }

  @override
  String get localBackup => 'File di backup locale';

  @override
  String get exportBackup => 'Esporta backup';

  @override
  String get importBackup => 'Importa backup';

  @override
  String get localBackupSubtitle =>
      'Salva un file di backup ripristinabile in qualsiasi momento';

  @override
  String get invalidBackupFile => 'Il file non è un backup Flash valido';

  @override
  String get pickACategory => 'Scegli una categoria';

  @override
  String get markAllReadWarningTitle => 'Segna tutto come letto?';

  @override
  String get markAllReadWarningBody =>
      'Tutti gli articoli nella vista corrente verranno segnati come letti e rimossi dal feed. Non potrai annullare questa azione.';

  @override
  String get markAllReadConfirm => 'Segna tutto come letto';

  @override
  String get aiSummary => 'Riepilogo IA';

  @override
  String get aiSummaryUnavailable =>
      'L\'IA sul dispositivo non è disponibile. Gemini Nano richiede un Pixel 8 o superiore con Android 14+.';

  @override
  String get aiSummaryDisclaimer =>
      'Generato sul dispositivo da Gemini Nano. Potrebbe non essere completamente accurato.';

  @override
  String get aiSummaryReading => 'Lettura dell\'articolo…';

  @override
  String get aiSummaryWriting => 'Scrittura del riepilogo…';

  @override
  String get aiSummaryTeaserOnly =>
      'Basato solo sull\'anteprima dell\'articolo.';

  @override
  String get copySummary => 'Copia riepilogo';

  @override
  String get summaryCopied => 'Riepilogo copiato';

  @override
  String get unreadOnly => 'Non letti';

  @override
  String get searchArticles => 'Cerca articoli…';

  @override
  String noSearchResults(String query) {
    return 'Nessun articolo corrisponde a \"$query\"';
  }

  @override
  String get summary => 'Riassunto';

  @override
  String get saved => 'Salvato';

  @override
  String get bookmarks => 'Salvati';

  @override
  String get noBookmarks =>
      'Niente di salvato ancora.\nTieni premuto un articolo per salvarlo.';

  @override
  String get bookmark => 'Salva';

  @override
  String get unbookmark => 'Rimuovi dai salvati';

  @override
  String get keywordAlerts => 'Avvisi per parole chiave';

  @override
  String get keywordAlertsSubtitle =>
      'Ricevi notifiche quando le parole tracciate compaiono in nuovi articoli';

  @override
  String get noKeywordAlerts => 'Nessun avviso ancora.';

  @override
  String get keywordAlertsEmpty =>
      'Aggiungi parole chiave per ricevere notifiche\nquando compaiono nei tuoi feed.';

  @override
  String get addAlertKeyword => 'Aggiungi avviso';

  @override
  String get addAlertKeywordSubtitle =>
      'Riceverai una notifica quando questa parola appare in un nuovo articolo. Distingue maiuscole.';

  @override
  String get alertKeywordHint => 'es. Flutter, cambiamento climatico…';

  @override
  String get markUnread => 'Segna come non letto';

  @override
  String get timeJustNow => 'adesso';

  @override
  String timeMinAgo(int n) {
    return '${n}min fa';
  }

  @override
  String timeHourAgo(int n) {
    return '${n}h fa';
  }

  @override
  String get timeYesterday => 'ieri';

  @override
  String timeDaysAgo(int n) {
    return '${n}g fa';
  }

  @override
  String timeWeeksAgo(int n) {
    return '${n}sett fa';
  }

  @override
  String timeMonthsAgo(int n) {
    return '${n}mesi fa';
  }

  @override
  String timeYearsAgo(int n) {
    return '${n}anni fa';
  }

  @override
  String get newspaperMode => 'Modalità giornale';

  @override
  String get newspaperModeSubtitle => 'Leggi il feed come un giornale stampato';

  @override
  String get newspaperModeOverridesTheme =>
      'L\'aspetto è impostato dalla modalità giornale';

  @override
  String get moveFeedFailed => 'Impossibile salvare la modifica';

  @override
  String get refreshFailed =>
      'Aggiornamento non riuscito — controlla la connessione';

  @override
  String get filterBubbleTitle => 'Filtro';

  @override
  String get quickSettingsTitle => 'Impostazioni rapide';

  @override
  String get articleAgeFilter => 'Età degli articoli';

  @override
  String articlesCount(int n) {
    return '$n articoli';
  }

  @override
  String daysCount(int n) {
    return '$n giorni';
  }

  @override
  String get filterBubbleFootnote => 'Vale per tutti i feed.';

  @override
  String get filterTooltip => 'Filtra articoli';

  @override
  String get quickSettingsTooltip => 'Impostazioni rapide';

  @override
  String get articleOrder => 'Ordine articoli';

  @override
  String get newestFirst => 'Recenti';

  @override
  String get oldestFirst => 'Meno recenti';

  @override
  String get apply => 'Applica';

  @override
  String get showRead => 'Mostra letti';

  @override
  String get showReadSubtitle =>
      'Mantieni gli articoli letti fino al prossimo aggiornamento';

  @override
  String get dayToday => 'Oggi';

  @override
  String get dayYesterday => 'Ieri';

  @override
  String get dontShowAgain => 'Non mostrare più';

  @override
  String get confirmMarkAllRead => 'Conferma segna tutto come letto';

  @override
  String get selectCategoryFirst => 'Scegli una categoria per continuare.';
}
