import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'alert_navigation_intent.dart';
import '../utils/diag_log.dart';
import '../utils/device_localizations.dart';
import 'package:workmanager/workmanager.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_match.dart';
import '../models/feed.dart';
import '../repositories/alert_match_repository.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/keyword_alert_repository.dart';
import '../repositories/keyword_repository.dart';
import '../repositories/settings_repository.dart';
import 'alert_notification_planner.dart';
import 'rss_service.dart';

const String kRefreshTaskName = 'flash_feed_refresh';
const String kRefreshTaskUniqueName = 'flash_feed_refresh_periodic';
const String _kKeywordChannelId = 'flash_keyword_alerts';
const String _kKeywordChannelName = 'Keyword alerts';

/// Bundles every keyword alert under one heading in the shade. Now that each
/// keyword set posts under its own id they no longer overwrite each other,
/// which trades one destroyed notification for a wall of them; grouping is
/// what keeps five alerts looking like five alerts rather than five apps.
const String _kKeywordGroupKey = 'flash_keyword_alerts_group';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == kRefreshTaskName) {
      try {
        // Background job: run cleanup first, then fetch. This runs in its
        // own isolate/engine, separate from the foreground app -- Pass 20
        // investigation into "never received a keyword-alert notification"
        // needs to know whether this path specifically is where it fails.
        await _doRefresh(runCleanup: true, source: 'background');
      } catch (_) {}
    }
    return true;
  });
}

Future<FlutterLocalNotificationsPlugin> _initPlugin() async {
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  // The handler must be passed here too. initialize() overwrites the stored
  // response callback every time, and this runs on the UI isolate as well as
  // the background one -- so omitting it de-registered main()'s handler the
  // first time an alert was posted, and tapping a notification thereafter did
  // nothing.
  await plugin.initialize(
    const InitializationSettings(android: androidInit),
    onDidReceiveNotificationResponse: onAlertNotificationResponse,
  );
  return plugin;
}

/// Reports the Android-side notification permission state directly, rather
/// than inferring it from whether .show() throws -- NotificationManager
/// silently drops a notification when the app lacks posting permission
/// instead of raising, which is exactly the "nothing broken, nothing shown"
/// symptom this investigation exists to pin down.
Future<bool?> _notificationsEnabled(FlutterLocalNotificationsPlugin plugin) {
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  return androidPlugin?.areNotificationsEnabled() ?? Future.value(null);
}

/// Core refresh logic shared across cold start, background, and pull-to-refresh.
///
/// [runCleanup] — true for cold start and background; false for pull-to-refresh.
/// [feeds] — if provided, only these feeds are fetched; otherwise all feeds.
Future<int> _doRefresh({
  bool runCleanup = false,
  List<Feed>? feeds,
  String source = 'unknown',
}) async {
  final articleRepo = ArticleRepository();
  final feedRepo = FeedRepository();
  final keywordRepo = KeywordRepository();
  final alertRepo = KeywordAlertRepository();
  final settingsRepo = SettingsRepository();

  // Read once for the whole pass: every feed shares the same global cap, and
  // cleanup (when it runs) needs the age window from the same snapshot.
  final settings = await settingsRepo.getAll();

  // Cleanup must complete before any inserts (cold start and background only).
  if (runCleanup) {
    await articleRepo.runCleanup(days: settings.cleanupAgeDays);
  }

  final keywords = await keywordRepo.getAll();
  final alerts = await alertRepo.getAll();
  final rssService = RssService(articleRepo, feedRepo);
  final feedList = feeds ?? await feedRepo.getAll();

  int totalNew = 0;
  final alertMatchRepo = AlertMatchRepository();
  // The rows insertMatches actually wrote this pass -- not everything the
  // fetch re-parsed, which is what used to fire a notification for the same
  // article on every refresh: RSS feeds re-serve their last N items, and only
  // fetchAndStore's own dedup check knows which of those are genuinely new.
  final newMatches = <AlertMatch>[];

  await Future.wait(feedList.map((feed) async {
    final result = await rssService.fetchAndStore(
      feed,
      keywords: keywords,
      alerts: alerts,
      articleLimit: settings.articleLimit,
    );
    totalNew += result.newCount;
    newMatches.addAll(result.newAlertMatches);
  }));

  // One plan per distinct keyword set, each quoting the total currently
  // waiting in the Alerts tab. The total is read back from the table *after*
  // every feed has been inserted, deliberately: the body describes what the
  // user will find when they open the tab, not how many rows this particular
  // pass happened to write, so a keyword that already had eight entries says
  // nine rather than one.
  //
  // planAlertNotifications is synchronous on purpose -- it is a pure decision
  // function with no database behind it, which is the only reason its rules
  // are testable at all -- so the totals are read here first and handed over
  // as a lookup rather than being queried from inside it.
  final totals = <String, int>{};
  for (final keywordSet in _distinctKeywordSets(newMatches)) {
    totals[keywordSet.join(_kSetSeparator)] =
        await alertMatchRepo.countForKeywordSet(keywordSet);
  }

  final plans = planAlertNotifications(
    newMatches: newMatches,
    runningTotalFor: (sortedKeywords) =>
        totals[sortedKeywords.join(_kSetSeparator)] ?? 0,
  );

  if (plans.isEmpty) {
    DiagLog.alert(
      source: source,
      alertCount: alerts.length,
      newCount: totalNew,
      hitCount: 0,
      groupCount: 0,
    );
  } else {
    String? shown;
    String? error;
    try {
      // Checked, not just called: NotificationManager on Android drops a
      // notification with no error when the app lacks posting permission,
      // so a call that completes without throwing tells you nothing about
      // whether anything actually reached the shade.
      final plugin = await _initPlugin();
      final enabled = await _notificationsEnabled(plugin);
      final l10n = _alertLocalizations();
      for (final plan in plans) {
        // A stable id per keyword set. Every alert used to post under the
        // hardcoded id 2, and Android treats the id as the notification's
        // identity -- so the second alert of a pass did not join the first in
        // the shade, it replaced it outright.
        final id = await alertMatchRepo.notificationIdFor(plan.keywords);
        await plugin.show(
          id,
          _alertTitle(l10n),
          _alertBody(l10n, plan),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _kKeywordChannelId,
              _kKeywordChannelName,
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
              showWhen: true,
              groupKey: _kKeywordGroupKey,
            ),
          ),
          payload: kAlertNotificationPayload,
        );
      }
      shown = '${plans.length} shown, areNotificationsEnabled=$enabled';
    } catch (e) {
      // Deliberately caught here rather than left to bubble: callbackDispatcher
      // wraps the whole background task in a silent try/catch, so an
      // exception thrown from here on the background-isolate path would
      // otherwise vanish with zero trace -- indistinguishable from working.
      error = e.toString();
    }
    DiagLog.alert(
      source: source,
      alertCount: alerts.length,
      newCount: totalNew,
      hitCount: newMatches.length,
      groupCount: plans.length,
      keywordSets: [for (final plan in plans) plan.keywords],
      shown: shown,
      error: error,
    );
  }

  return totalNew;
}

/// NUL-joined, matching the key both [planAlertNotifications] and
/// `AlertMatchRepository.notificationIdFor` mint from a keyword set, so the
/// total looked up here cannot end up attached to a different set than the one
/// it was counted for.
const String _kSetSeparator = '\u0000';

/// The distinct sorted keyword sets in [matches] -- one per article, then
/// deduplicated, which is exactly the grouping [planAlertNotifications]
/// performs. Recomputed here only because the totals have to be awaited before
/// the planner runs.
List<List<String>> _distinctKeywordSets(List<AlertMatch> matches) {
  final byArticle = <String, Set<String>>{};
  for (final match in matches) {
    byArticle
        .putIfAbsent('${match.feedId}$_kSetSeparator${match.guid}',
            () => <String>{})
        .add(match.keyword);
  }
  final sets = <String, List<String>>{};
  for (final keywords in byArticle.values) {
    final sorted = keywords.toList()..sort();
    sets[sorted.join(_kSetSeparator)] = sorted;
  }
  return sets.values.toList();
}

/// The localisations the notification bodies are written in.
///
/// Shared with the unread-count badge — see [deviceLocalizations] for why this
/// cannot go through a BuildContext.
AppLocalizations? _alertLocalizations() => deviceLocalizations();

String _alertTitle(AppLocalizations? l10n) =>
    l10n?.alertNotificationTitle ?? 'Flash — keyword alert';

String _alertBody(AppLocalizations? l10n, AlertNotificationPlan plan) {
  switch (plan.kind) {
    case AlertBodyKind.first:
      final keyword = plan.keywords.first;
      return l10n?.alertNotificationFirst(keyword) ??
          '"$keyword" appeared in an article';
    case AlertBodyKind.count:
      final keyword = plan.keywords.first;
      return l10n?.alertNotificationCount(plan.count, keyword) ??
          (plan.count == 1
              ? '1 article matched "$keyword"'
              : '${plan.count} articles matched "$keyword"');
    case AlertBodyKind.combined:
      final keywords = _joinQuotedKeywords(
        plan.keywords,
        l10n?.keywordListSeparator ?? ', ',
        l10n?.keywordListAnd ?? ' and ',
      );
      return l10n?.alertNotificationCombined(plan.count, keywords) ??
          (plan.count == 1
              ? '1 article triggered with the words $keywords'
              : '${plan.count} articles triggered with the words $keywords');
  }
}

/// `"a" and "b"` for two, `"a", "b" and "c"` for three or more.
///
/// The separator and the conjunction are both localised, because a list
/// joined with an English " and " reads as a bug in every other language the
/// app ships. Each keyword is quoted so a multi-word keyword cannot be
/// mistaken for two.
String _joinQuotedKeywords(
  List<String> keywords,
  String separator,
  String and,
) {
  final quoted = [for (final keyword in keywords) '"$keyword"'];
  return quoted.join(separator);
}

class RefreshService {
  final SettingsRepository _settingsRepo;

  RefreshService(this._settingsRepo);

  Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
    await schedulePeriodicRefresh();
  }

  Future<void> schedulePeriodicRefresh({bool forceReschedule = false}) async {
    final intervalStr =
        await _settingsRepo.get('refresh_interval_minutes') ?? '30';
    final intervalMinutes = int.tryParse(intervalStr) ?? 30;

    if (intervalMinutes == 0) {
      await Workmanager().cancelByUniqueName(kRefreshTaskUniqueName);
      return;
    }

    await Workmanager().registerPeriodicTask(
      kRefreshTaskUniqueName,
      kRefreshTaskName,
      frequency: Duration(minutes: intervalMinutes),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
      ),
      existingWorkPolicy: forceReschedule
          ? ExistingPeriodicWorkPolicy.replace
          : ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Fetch all feeds.
  /// [coldStart] — true on app cold open; runs cleanup before fetching.
  Future<int> refreshAll({bool coldStart = false}) => _doRefresh(
        runCleanup: coldStart,
        source: coldStart ? 'coldStart' : 'foregroundRefresh',
      );

  /// Refresh several feeds in one pass, rather than looping a per-feed
  /// refresh: each call re-reads keyword blocks and alerts from the DB, so a
  /// loop repeats those queries per feed and serialises the network fetches,
  /// while one call queries once and fans out via Future.wait.
  Future<int> refreshFeeds(List<Feed> feeds) =>
      _doRefresh(runCleanup: false, feeds: feeds, source: 'foregroundRefreshFeeds');
}
