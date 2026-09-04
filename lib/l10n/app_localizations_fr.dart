// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Flash';

  @override
  String get markAllRead => 'Tout marquer comme lu';

  @override
  String get refresh => 'Actualiser';

  @override
  String get noArticlesYet =>
      'Aucun article pour l\'instant.\nTirez vers le bas pour actualiser.';

  @override
  String get noNewArticles => 'Aucun nouvel article.\nVous êtes à jour.';

  @override
  String get feeds => 'Flux';

  @override
  String get categories => 'Catégories';

  @override
  String get newCategory => 'Nouvelle catégorie';

  @override
  String get addFeed => 'Ajouter un flux';

  @override
  String get noFeedsYet => 'Aucun flux pour l\'instant.';

  @override
  String get renameCategory => 'Renommer la catégorie';

  @override
  String get deleteCategory => 'Supprimer la catégorie';

  @override
  String get removeFeed => 'Supprimer le flux';

  @override
  String get addAFeed => 'Ajouter un flux';

  @override
  String get searchHint => 'Rechercher par nom ou coller une URL';

  @override
  String get noFeedsFound => 'Aucun flux trouvé. Essayez une URL.';

  @override
  String get followers => 'abonnés';

  @override
  String get feedAlreadyAdded => 'Ce flux est déjà ajouté.';

  @override
  String get couldNotParseFeed => 'Impossible de lire le flux à cette URL.';

  @override
  String failedToAddFeed(String error) {
    return 'Échec de l\'ajout du flux : $error';
  }

  @override
  String get defaultFolderName => 'Mes Actualités';

  @override
  String get categoryName => 'Nom de la catégorie';

  @override
  String get save => 'Enregistrer';

  @override
  String get addToCategory => 'Ajouter à la catégorie';

  @override
  String get editFeed => 'Modifier le flux';

  @override
  String get feedName => 'Nom du flux';

  @override
  String get category => 'Catégorie';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get remove => 'Retirer';

  @override
  String renameFolder(String name) {
    return 'Renommer \"$name\"';
  }

  @override
  String deleteFolder(String name) {
    return 'Supprimer \"$name\"';
  }

  @override
  String get edit => 'Modifier';

  @override
  String feedRemoved(String title) {
    return '\"$title\" supprimé';
  }

  @override
  String deleteFolderMessage(String name) {
    return 'Supprimer \"$name\" ? Tous les flux et articles de cette catégorie seront supprimés.';
  }

  @override
  String removeFeedMessage(String title) {
    return 'Retirer \"$title\" ? Tous les articles en cache seront supprimés.';
  }

  @override
  String get settings => 'Paramètres';

  @override
  String get reading => 'Lecture';

  @override
  String get markReadOnScroll => 'Marquer comme lu au défilement';

  @override
  String get markReadOnScrollSubtitle =>
      'Marque automatiquement les articles comme lus lors du défilement';

  @override
  String get backgroundRefreshInterval => 'Intervalle d\'actualisation';

  @override
  String get every15Minutes => 'Toutes les 15 minutes';

  @override
  String get every30Minutes => 'Toutes les 30 minutes';

  @override
  String get everyHour => 'Toutes les heures';

  @override
  String get every3Hours => 'Toutes les 3 heures';

  @override
  String get every6Hours => 'Toutes les 6 heures';

  @override
  String get manualOnly => 'Manuel uniquement';

  @override
  String get maxArticlesPerFeed => 'Max articles par flux';

  @override
  String get filters => 'Filtres';

  @override
  String get keywordBlocklist => 'Liste de mots bloqués';

  @override
  String get keywordBlocklistSubtitle =>
      'Masquer les articles contenant des mots ou phrases spécifiques';

  @override
  String get backup => 'Sauvegarde';

  @override
  String get googleDriveBackup => 'Sauvegarde Google Drive';

  @override
  String get connectGoogle => 'Connecter un compte Google';

  @override
  String get backupNow => 'Sauvegarder maintenant';

  @override
  String get restoreFromDrive => 'Restaurer depuis Drive';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String lastBackup(String date) {
    return 'Dernière sauvegarde : $date';
  }

  @override
  String get backupSuccess => 'Sauvegarde enregistrée sur Google Drive';

  @override
  String restoreSuccess(int count) {
    return '$count flux restaurés. Tirez pour actualiser.';
  }

  @override
  String get restoreConfirmTitle => 'Restaurer depuis Drive ?';

  @override
  String get restoreConfirmMessage =>
      'Cela remplacera tous vos flux, catégories et mots bloqués actuels par la sauvegarde enregistrée. Les articles seront récupérés lors du prochain rafraîchissement.';

  @override
  String get restore => 'Restaurer';

  @override
  String get noBackupFound => 'Aucune sauvegarde trouvée dans Drive';

  @override
  String get theme => 'Thème';

  @override
  String get themeSystem => 'Système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get colorPalette => 'Palette de couleurs';

  @override
  String get paletteGreen => 'Vert';

  @override
  String get paletteBlue => 'Bleu';

  @override
  String get paletteOrange => 'Orange';

  @override
  String get paletteRed => 'Rouge';

  @override
  String get paletteTealOrange => 'Sarcelle et orange';

  @override
  String get addKeyword => 'Ajouter un mot';

  @override
  String get noBlockedKeywords => 'Aucun mot bloqué.';

  @override
  String get keywordBlocklistEmpty =>
      'Les articles contenant un mot bloqué\nseront masqués de votre flux.';

  @override
  String get blockKeyword => 'Bloquer un mot';

  @override
  String get keywordOrPhrase => 'Mot ou phrase';

  @override
  String get keywordHint => 'Ex. sponsorisé, nom de célébrité…';

  @override
  String get wholeWordOnly => 'Mot entier uniquement';

  @override
  String get wholeWordSubtitle =>
      '\"crypto\" ne correspondra pas à \"cryptographie\"';

  @override
  String get add => 'Ajouter';

  @override
  String get matchingWholeWord => 'Correspondance mot entier uniquement';

  @override
  String get matchingAnywhere => 'Correspondance n\'importe où dans le texte';

  @override
  String get allTab => 'Tout';

  @override
  String get allMarkedRead => 'Tout marqué comme lu';

  @override
  String keywordRemoved(String keyword) {
    return '\"$keyword\" supprimé';
  }

  @override
  String get share => 'Partager';

  @override
  String get markRead => 'Marquer comme lu';

  @override
  String get nothingHereYet => 'Rien ici pour l\'instant.';

  @override
  String get addFirstFeed => 'Ajoutez votre premier flux pour commencer.';

  @override
  String get addAFeedButton => 'Ajouter un flux';

  @override
  String get onboardingTagline => 'RSS rapide et local avec filtrage par IA.';

  @override
  String get onboardingBullet1 =>
      'Suivez n\'importe quel flux RSS — actualités, blogs, podcasts.';

  @override
  String get onboardingBullet2 => 'Résumés IA, sur l\'appareil.';

  @override
  String get onboardingBullet3 =>
      'Sans compte. Vos données restent sur votre téléphone.';

  @override
  String get localBackup => 'Fichier de sauvegarde local';

  @override
  String get exportBackup => 'Exporter la sauvegarde';

  @override
  String get importBackup => 'Importer la sauvegarde';

  @override
  String get localBackupSubtitle =>
      'Enregistrez un fichier de sauvegarde restaurable à tout moment';

  @override
  String get invalidBackupFile =>
      'Ce fichier n\'est pas une sauvegarde Flash valide';

  @override
  String get pickACategory => 'Choisir une catégorie';

  @override
  String get markAllReadWarningTitle => 'Tout marquer comme lu ?';

  @override
  String get markAllReadWarningBody =>
      'Ceci marquera tous les articles de la vue actuelle comme lus et les retirera du flux. Cette action est irréversible.';

  @override
  String get markAllReadConfirm => 'Tout marquer comme lu';

  @override
  String get aiSummary => 'Résumé IA';

  @override
  String get aiSummaryUnavailable =>
      'L\'IA embarquée n\'est pas disponible sur cet appareil. Gemini Nano nécessite un Pixel 8 ou supérieur sous Android 14+.';

  @override
  String get aiSummaryDisclaimer =>
      'Généré sur l\'appareil par Gemini Nano. Peut ne pas être entièrement précis.';

  @override
  String get aiSummaryReading => 'Lecture de l\'article…';

  @override
  String get aiSummaryWriting => 'Rédaction du résumé…';

  @override
  String get aiSummaryTeaserOnly =>
      'Basé uniquement sur l\'aperçu de l\'article.';

  @override
  String get copySummary => 'Copier le résumé';

  @override
  String get summaryCopied => 'Résumé copié';

  @override
  String get unreadOnly => 'Non lus';

  @override
  String get searchArticles => 'Rechercher des articles…';

  @override
  String noSearchResults(String query) {
    return 'Aucun article ne correspond à \"$query\"';
  }

  @override
  String get summary => 'Résumé';

  @override
  String get saved => 'Enregistré';

  @override
  String get bookmarks => 'Enregistrés';

  @override
  String get noBookmarks =>
      'Rien d\'enregistré pour l\'instant.\nAppuyez longuement sur un article pour le sauvegarder.';

  @override
  String get bookmark => 'Enregistrer';

  @override
  String get unbookmark => 'Retirer des enregistrés';

  @override
  String get keywordAlerts => 'Alertes par mot-clé';

  @override
  String get keywordAlertsSubtitle =>
      'Recevez des notifications quand des mots suivis apparaissent dans de nouveaux articles';

  @override
  String get noKeywordAlerts => 'Aucune alerte pour l\'instant.';

  @override
  String get keywordAlertsEmpty =>
      'Ajoutez des mots pour être notifié\nlorsqu\'ils apparaissent dans vos flux.';

  @override
  String get addAlertKeyword => 'Ajouter une alerte';

  @override
  String get addAlertKeywordSubtitle =>
      'Vous serez notifié quand ce mot apparaît dans un nouvel article. Sensible à la casse.';

  @override
  String get alertKeywordHint => 'ex. Flutter, réchauffement climatique…';

  @override
  String get markUnread => 'Marquer comme non lu';

  @override
  String get timeJustNow => 'à l\'instant';

  @override
  String timeMinAgo(int n) {
    return 'il y a ${n}min';
  }

  @override
  String timeHourAgo(int n) {
    return 'il y a ${n}h';
  }

  @override
  String get timeYesterday => 'hier';

  @override
  String timeDaysAgo(int n) {
    return 'il y a ${n}j';
  }

  @override
  String timeWeeksAgo(int n) {
    return 'il y a ${n}sem';
  }

  @override
  String timeMonthsAgo(int n) {
    return 'il y a ${n}mois';
  }

  @override
  String timeYearsAgo(int n) {
    return 'il y a ${n}an';
  }

  @override
  String get newspaperMode => 'Mode journal';

  @override
  String get newspaperModeSubtitle =>
      'Lisez votre fil comme un journal imprimé';

  @override
  String get newspaperModeOverridesTheme =>
      'L\'apparence est définie par le mode journal';

  @override
  String get moveFeedFailed => 'Impossible d\'enregistrer cette modification';

  @override
  String get refreshFailed =>
      'Échec de l\'actualisation — vérifiez votre connexion';

  @override
  String get filterBubbleTitle => 'Filtre';

  @override
  String get quickSettingsTitle => 'Réglages rapides';

  @override
  String get articleAgeFilter => 'Âge des articles';

  @override
  String articlesCount(int n) {
    return '$n articles';
  }

  @override
  String daysCount(int n) {
    return '$n jours';
  }

  @override
  String get filterBubbleFootnote => 'S\'applique à tous les flux.';

  @override
  String get filterTooltip => 'Filtrer les articles';

  @override
  String get quickSettingsTooltip => 'Réglages rapides';

  @override
  String get articleOrder => 'Ordre des articles';

  @override
  String get newestFirst => 'Récents';

  @override
  String get oldestFirst => 'Anciens';

  @override
  String get apply => 'Appliquer';

  @override
  String get showRead => 'Afficher les lus';

  @override
  String get showReadSubtitle =>
      'Garder les articles lus jusqu\'à la prochaine actualisation';

  @override
  String get dayToday => 'Aujourd\'hui';

  @override
  String get dayYesterday => 'Hier';

  @override
  String get dontShowAgain => 'Ne plus afficher';

  @override
  String get confirmMarkAllRead => 'Confirmer tout marquer comme lu';

  @override
  String get selectCategoryFirst => 'Choisissez une catégorie pour continuer.';
}
