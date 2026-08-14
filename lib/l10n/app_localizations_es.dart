// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Flash';

  @override
  String get markAllRead => 'Marcar todo como leído';

  @override
  String get refresh => 'Actualizar';

  @override
  String get noArticlesYet =>
      'Sin artículos aún.\nDesliza hacia abajo para actualizar.';

  @override
  String get noNewArticles => 'Sin artículos nuevos.\nEstás al día.';

  @override
  String get feeds => 'Fuentes';

  @override
  String get categories => 'Categorías';

  @override
  String get newCategory => 'Nueva categoría';

  @override
  String get addFeed => 'Añadir fuente';

  @override
  String get noFeedsYet => 'Sin fuentes aún.';

  @override
  String get renameCategory => 'Renombrar categoría';

  @override
  String get deleteCategory => 'Eliminar categoría';

  @override
  String get removeFeed => 'Eliminar fuente';

  @override
  String get uncategorised => 'Sin categoría';

  @override
  String get addAFeed => 'Añadir una fuente';

  @override
  String get searchHint => 'Busca por nombre o pega una URL';

  @override
  String get noFeedsFound => 'No se encontraron fuentes. Prueba con una URL.';

  @override
  String get followers => 'seguidores';

  @override
  String get feedAlreadyAdded => 'Esta fuente ya está añadida.';

  @override
  String get couldNotParseFeed => 'No se pudo leer la fuente en esta URL.';

  @override
  String failedToAddFeed(String error) {
    return 'Error al añadir la fuente: $error';
  }

  @override
  String get defaultFolderName => 'Mis Noticias';

  @override
  String get categoryName => 'Nombre de categoría';

  @override
  String get save => 'Guardar';

  @override
  String get addToCategory => 'Añadir a categoría';

  @override
  String get editFeed => 'Editar fuente';

  @override
  String get feedName => 'Nombre de la fuente';

  @override
  String get category => 'Categoría';

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get remove => 'Quitar';

  @override
  String renameFolder(String name) {
    return 'Renombrar \"$name\"';
  }

  @override
  String deleteFolder(String name) {
    return 'Eliminar \"$name\"';
  }

  @override
  String get edit => 'Editar';

  @override
  String feedRemoved(String title) {
    return '\"$title\" eliminada';
  }

  @override
  String deleteFolderMessage(String name) {
    return '¿Eliminar \"$name\"? Se eliminarán todas las fuentes y artículos de esta categoría.';
  }

  @override
  String removeFeedMessage(String title) {
    return '¿Quitar \"$title\"? Se eliminarán todos los artículos en caché.';
  }

  @override
  String get settings => 'Ajustes';

  @override
  String get reading => 'Lectura';

  @override
  String get markReadOnScroll => 'Marcar como leído al desplazar';

  @override
  String get markReadOnScrollSubtitle =>
      'Marca automáticamente los artículos como leídos al desplazarte';

  @override
  String get backgroundRefreshInterval => 'Intervalo de actualización';

  @override
  String get every15Minutes => 'Cada 15 minutos';

  @override
  String get every30Minutes => 'Cada 30 minutos';

  @override
  String get everyHour => 'Cada hora';

  @override
  String get every3Hours => 'Cada 3 horas';

  @override
  String get every6Hours => 'Cada 6 horas';

  @override
  String get manualOnly => 'Solo manual';

  @override
  String get storage => 'Almacenamiento';

  @override
  String get maxArticlesPerFeed => 'Máx. artículos por fuente';

  @override
  String get articles50 => '50 artículos';

  @override
  String get articles100 => '100 artículos';

  @override
  String get articles200 => '200 artículos';

  @override
  String get articles500 => '500 artículos';

  @override
  String get unlimited => 'Sin límite';

  @override
  String get filters => 'Filtros';

  @override
  String get keywordBlocklist => 'Lista de palabras bloqueadas';

  @override
  String get keywordBlocklistSubtitle =>
      'Ocultar artículos que coincidan con palabras o frases';

  @override
  String get backup => 'Copia de seguridad';

  @override
  String get googleDriveBackup => 'Copia en Google Drive';

  @override
  String get connectGoogle => 'Conectar cuenta de Google';

  @override
  String get backupNow => 'Hacer copia ahora';

  @override
  String get restoreFromDrive => 'Restaurar desde Drive';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String lastBackup(String date) {
    return 'Última copia: $date';
  }

  @override
  String get backupSuccess => 'Copia guardada en Google Drive';

  @override
  String restoreSuccess(int count) {
    return '$count fuentes restauradas. Desliza para actualizar.';
  }

  @override
  String get restoreConfirmTitle => '¿Restaurar desde Drive?';

  @override
  String get restoreConfirmMessage =>
      'Esto reemplazará todas tus fuentes, categorías y palabras bloqueadas actuales con la copia guardada. Los artículos se actualizarán en el próximo refresco.';

  @override
  String get restore => 'Restaurar';

  @override
  String get noBackupFound => 'No se encontró copia en Drive';

  @override
  String get theme => 'Tema';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get themeLight => 'Claro';

  @override
  String get themeDark => 'Oscuro';

  @override
  String get addKeyword => 'Añadir palabra';

  @override
  String get noBlockedKeywords => 'Sin palabras bloqueadas.';

  @override
  String get keywordBlocklistEmpty =>
      'Los artículos que coincidan con una palabra bloqueada\nse ocultarán de tu fuente.';

  @override
  String get blockKeyword => 'Bloquear palabra';

  @override
  String get keywordOrPhrase => 'Palabra o frase';

  @override
  String get keywordHint => 'Ej. patrocinado, nombre de famoso…';

  @override
  String get wholeWordOnly => 'Solo palabra completa';

  @override
  String get wholeWordSubtitle =>
      '\"cripto\" no coincidirá con \"criptografía\"';

  @override
  String get add => 'Añadir';

  @override
  String get matchingWholeWord => 'Solo coincidencia de palabra completa';

  @override
  String get matchingAnywhere => 'Coincidencia en cualquier parte del texto';

  @override
  String get allTab => 'Todo';

  @override
  String get allMarkedRead => 'Todo marcado como leído';

  @override
  String keywordRemoved(String keyword) {
    return '\"$keyword\" eliminada';
  }

  @override
  String get share => 'Compartir';

  @override
  String get markRead => 'Marcar como leído';

  @override
  String get nothingHereYet => 'Nada aquí todavía.';

  @override
  String get addFirstFeed => 'Añade tu primera fuente para empezar.';

  @override
  String get addAFeedButton => 'Añadir una fuente';

  @override
  String get onboardingTagline =>
      'RSS rápido y local con filtrado mediante IA.';

  @override
  String get onboardingBullet1 =>
      'Sigue cualquier fuente RSS — noticias, blogs, podcasts.';

  @override
  String get onboardingBullet2 => 'Resúmenes IA, en el dispositivo.';

  @override
  String get onboardingBullet3 =>
      'Sin cuenta. Tus datos permanecen en tu teléfono.';

  @override
  String get blockedArticles => 'Artículos bloqueados';

  @override
  String get noBlockedArticles => 'Sin artículos bloqueados aún.';

  @override
  String blockedByKeyword(String keyword) {
    return 'Bloqueado por: $keyword';
  }

  @override
  String get localBackup => 'Copia de seguridad local';

  @override
  String get exportBackup => 'Exportar copia';

  @override
  String get importBackup => 'Importar copia';

  @override
  String get localBackupSubtitle =>
      'Guarda un archivo de copia que puedes restaurar en cualquier momento';

  @override
  String get invalidBackupFile => 'El archivo no es una copia válida de Flash';

  @override
  String get pickACategory => 'Elige una categoría';

  @override
  String get markAllReadWarningTitle => '¿Marcar todo como leído?';

  @override
  String get markAllReadWarningBody =>
      'Esto marcará todos los artículos de la vista actual como leídos. No podrás deshacer esta acción.';

  @override
  String get markAllReadConfirm => 'Marcar todo como leído';

  @override
  String get aiSummary => 'Resumen IA';

  @override
  String get aiSummaryUnavailable =>
      'La IA en dispositivo no está disponible. Gemini Nano requiere un Pixel 8 o superior con Android 14+.';

  @override
  String get aiSummaryDisclaimer =>
      'Generado en el dispositivo por Gemini Nano. Puede no ser completamente preciso.';

  @override
  String get aiSummaryReading => 'Leyendo el artículo…';

  @override
  String get aiSummaryWriting => 'Escribiendo el resumen…';

  @override
  String get aiSummaryTeaserOnly =>
      'Basado solo en la vista previa del artículo.';

  @override
  String get copySummary => 'Copiar resumen';

  @override
  String get summaryCopied => 'Resumen copiado';

  @override
  String get unreadOnly => 'No leídos';

  @override
  String get searchArticles => 'Buscar artículos…';

  @override
  String noSearchResults(String query) {
    return 'Ningún artículo coincide con \"$query\"';
  }

  @override
  String get summary => 'Resumen';

  @override
  String get saved => 'Guardado';

  @override
  String get bookmarks => 'Guardados';

  @override
  String get noBookmarks =>
      'Nada guardado aún.\nMantén pulsado un artículo para guardarlo.';

  @override
  String get bookmark => 'Guardar';

  @override
  String get unbookmark => 'Quitar de guardados';

  @override
  String get keywordAlerts => 'Alertas de palabras clave';

  @override
  String get keywordAlertsSubtitle =>
      'Recibe notificaciones cuando las palabras rastreadas aparezcan en nuevos artículos';

  @override
  String get noKeywordAlerts => 'Aún no hay alertas de palabras clave.';

  @override
  String get keywordAlertsEmpty =>
      'Añade palabras sobre las que quieras recibir alertas\ncuando aparezcan en tus feeds.';

  @override
  String get addAlertKeyword => 'Añadir alerta';

  @override
  String get addAlertKeywordSubtitle =>
      'Recibirás una notificación cuando esta palabra aparezca en un artículo nuevo. Distingue mayúsculas.';

  @override
  String get alertKeywordHint => 'p. ej. Flutter, cambio climático…';

  @override
  String get markUnread => 'Marcar como no leído';

  @override
  String get opml => 'OPML';

  @override
  String get opmlSubtitle =>
      'Importa o exporta tus feeds en formato OPML, compatible con todos los lectores RSS';

  @override
  String get opmlExport => 'Exportar OPML';

  @override
  String get opmlImport => 'Importar OPML';

  @override
  String get opmlExportSuccess => 'Feeds exportados a OPML';

  @override
  String opmlImportSuccess(int count) {
    return '$count feeds importados';
  }

  @override
  String get changelog => 'Registro de cambios';

  @override
  String get timeJustNow => 'ahora';

  @override
  String timeMinAgo(int n) {
    return 'hace ${n}min';
  }

  @override
  String timeHourAgo(int n) {
    return 'hace ${n}h';
  }

  @override
  String get timeYesterday => 'ayer';

  @override
  String timeDaysAgo(int n) {
    return 'hace ${n}d';
  }

  @override
  String timeWeeksAgo(int n) {
    return 'hace ${n}sem';
  }

  @override
  String timeMonthsAgo(int n) {
    return 'hace ${n}mes';
  }

  @override
  String timeYearsAgo(int n) {
    return 'hace ${n}a';
  }

  @override
  String get newspaperMode => 'Modo periódico';

  @override
  String get newspaperModeSubtitle => 'Lee tu feed como un periódico impreso';

  @override
  String get newspaperModeOverridesTheme =>
      'La apariencia está definida por el modo periódico';
}
