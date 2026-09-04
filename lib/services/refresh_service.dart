import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
        // Background job: run cleanup first, then fetch.
        await _doRefresh(runCleanup: true);
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

Future<void> _showKeywordNotification(List<String> keywords) async {
  final plugin = await _initPlugin();
  final label = keywords.length == 1
      ? '"${keywords.first}"'
      : keywords.map((k) => '"$k"').join(', ');
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
}

/// Core refresh logic shared across cold start, background, and pull-to-refresh.
///
/// [runCleanup] — true for cold start and background; false for pull-to-refresh.
/// [feeds] — if provided, only these feeds are fetched; otherwise all feeds.
Future<int> _doRefresh({bool runCleanup = false, List<Feed>? feeds}) async {
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
  final allUnblocked = <({String title, String? description})>[];

  await Future.wait(feedList.map((feed) async {
    final result = await rssService.fetchAndStore(
      feed,
      keywords: keywords,
      articleLimit: settings.articleLimit,
    );
    totalNew += result.newCount;
    allUnblocked.addAll(result.unblocked);
  }));

  if (alerts.isNotEmpty && allUnblocked.isNotEmpty) {
    final hits = KeywordAlertRepository.findHits(allUnblocked, alerts);
    if (hits.isNotEmpty) await _showKeywordNotification(hits);
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
  Future<int> refreshAll({bool coldStart = false}) =>
      _doRefresh(runCleanup: coldStart);

  /// Refresh several feeds in one pass, rather than looping a per-feed
  /// refresh: each call re-reads keyword blocks and alerts from the DB, so a
  /// loop repeats those queries per feed and serialises the network fetches,
  /// while one call queries once and fans out via Future.wait.
  Future<int> refreshFeeds(List<Feed> feeds) =>
      _doRefresh(runCleanup: false, feeds: feeds);
}
