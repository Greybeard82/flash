import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/diag_log.dart';
import 'package:workmanager/workmanager.dart';
import '../models/feed.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/keyword_alert_repository.dart';
import '../repositories/keyword_repository.dart';
import '../repositories/settings_repository.dart';
import 'rss_service.dart';

const String kRefreshTaskName = 'flash_feed_refresh';
const String kRefreshTaskUniqueName = 'flash_feed_refresh_periodic';
const String _kKeywordChannelId = 'flash_keyword_alerts';
const String _kKeywordChannelName = 'Keyword alerts';
const int _kKeywordNotificationId = 2;

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
  await plugin.initialize(const InitializationSettings(android: androidInit));
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
  // Keywords matched by articles insertArticles actually wrote as new this
  // pass -- not recomputed against the full re-parsed batch, which is what
  // used to fire a notification for the same article on every refresh: RSS
  // feeds re-serve their last N items, and only fetchAndStore's own dedup
  // check knows which of those are genuinely new here.
  final newlyMatchedKeywords = <String>{};

  await Future.wait(feedList.map((feed) async {
    final result = await rssService.fetchAndStore(
      feed,
      keywords: keywords,
      alerts: alerts,
      articleLimit: settings.articleLimit,
    );
    totalNew += result.newCount;
    newlyMatchedKeywords.addAll(result.newlyMatchedAlertKeywords);
  }));

  if (newlyMatchedKeywords.isEmpty) {
    DiagLog.alert(
      source: source,
      alertCount: alerts.length,
      newCount: totalNew,
      hitCount: 0,
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
      final keywordsList = newlyMatchedKeywords.toList();
      final label = keywordsList.length == 1
          ? '"${keywordsList.first}"'
          : keywordsList.map((k) => '"$k"').join(', ');
      await plugin.show(
        _kKeywordNotificationId,
        'Flash — keyword alert',
        'New articles matching $label',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _kKeywordChannelId,
            _kKeywordChannelName,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            showWhen: true,
          ),
        ),
      );
      shown = 'plugin.show() completed, areNotificationsEnabled=$enabled';
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
      hitCount: newlyMatchedKeywords.length,
      shown: shown,
      error: error,
    );
  }

  return totalNew;
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
