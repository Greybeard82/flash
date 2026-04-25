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
        await _doRefreshAll();
      } catch (_) {
        // Background refresh errors are intentionally silent — the app
        // will pick up new articles on the next successful run.
      }
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

/// Shared refresh logic used by both the background WorkManager task
/// and foreground manual refresh.
/// Returns the total number of new articles fetched.
Future<int> _doRefreshAll({List<Feed>? feeds}) async {
  final feedRepo = FeedRepository();
  final articleRepo = ArticleRepository();
  final settingsRepo = SettingsRepository();
  final keywordRepo = KeywordRepository();
  final alertRepo = KeywordAlertRepository();
  final keywords = await keywordRepo.getAll();
  final alerts = await alertRepo.getAll();
  final rssService = RssService(articleRepo, feedRepo, settingsRepo);
  final feedList = feeds ?? await feedRepo.getAll();
  int totalNew = 0;
  final allUnblocked = <({String title, String? description})>[];
  for (final feed in feedList) {
    final result = await rssService.fetchAndStore(feed, keywords: keywords);
    totalNew += result.newCount;
    allUnblocked.addAll(result.unblocked);
  }
  if (alerts.isNotEmpty && allUnblocked.isNotEmpty) {
    final hits = KeywordAlertRepository.findHits(allUnblocked, alerts);
    if (hits.isNotEmpty) {
      await _showKeywordNotification(hits);
    }
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

  /// Schedules (or updates) the periodic background refresh.
  ///
  /// [forceReschedule] should be `true` only when the user explicitly changes
  /// the interval in Settings — it cancels any existing task and registers a
  /// fresh one so the new interval takes effect immediately.
  /// On normal app startup pass `false` (default) so an already-running
  /// schedule is not reset.
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

  Future<int> refreshAll() => _doRefreshAll();

  Future<int> refreshFeed(Feed feed) => _doRefreshAll(feeds: [feed]);
}
