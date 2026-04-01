import 'package:workmanager/workmanager.dart';
import '../models/feed.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/keyword_repository.dart';
import '../repositories/settings_repository.dart';
import 'rss_service.dart';

const String kRefreshTaskName = 'flash_feed_refresh';
const String kRefreshTaskUniqueName = 'flash_feed_refresh_periodic';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == kRefreshTaskName) {
      await _runRefresh();
    }
    return true;
  });
}

Future<void> _runRefresh() async {
  try {
    final feedRepo = FeedRepository();
    final articleRepo = ArticleRepository();
    final settingsRepo = SettingsRepository();
    final keywordRepo = KeywordRepository();
    final keywords = await keywordRepo.getAll();
    final rssService = RssService(articleRepo, feedRepo, settingsRepo);

    final feeds = await feedRepo.getAll();
    for (final feed in feeds) {
      await rssService.fetchAndStore(feed, keywords: keywords);
    }
  } catch (_) {
    // Background refresh errors are silent
  }
}

class RefreshService {
  final SettingsRepository _settingsRepo;

  RefreshService(this._settingsRepo);

  Future<void> init() async {
    await Workmanager().initialize(callbackDispatcher);
    await schedulePeriodicRefresh();
  }

  Future<void> schedulePeriodicRefresh() async {
    final intervalStr = await _settingsRepo.get('refresh_interval_minutes') ?? '30';
    final intervalMinutes = int.tryParse(intervalStr) ?? 30;

    // 0 means manual only — cancel any existing task
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
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  Future<void> refreshAll() async {
    final feedRepo = FeedRepository();
    final articleRepo = ArticleRepository();
    final settingsRepo = SettingsRepository();
    final keywordRepo = KeywordRepository();
    final keywords = await keywordRepo.getAll();
    final rssService = RssService(articleRepo, feedRepo, settingsRepo);

    final feeds = await feedRepo.getAll();
    for (final feed in feeds) {
      await rssService.fetchAndStore(feed, keywords: keywords);
    }
  }

  Future<void> refreshFeed(Feed feed) async {
    final feedRepo = FeedRepository();
    final articleRepo = ArticleRepository();
    final settingsRepo = SettingsRepository();
    final keywordRepo = KeywordRepository();
    final keywords = await keywordRepo.getAll();
    final rssService = RssService(articleRepo, feedRepo, settingsRepo);
    await rssService.fetchAndStore(feed, keywords: keywords);
  }
}
