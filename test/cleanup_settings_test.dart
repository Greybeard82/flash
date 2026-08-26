import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/article.dart';
import 'package:flash/models/settings.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/utils/constants.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

late ArticleRepository _repo;

final _now = DateTime.now();

Article _art(int i, {required DateTime published}) => Article(
      feedId: 1,
      guid: 'guid-$i',
      title: 'Article $i',
      url: 'https://example.com/$i',
      publishedAt: published.millisecondsSinceEpoch,
      fetchedAt: 0,
    );

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  _repo = ArticleRepository();

  final db = await AppDatabase.instance.database;
  final ts = DateTime.now().millisecondsSinceEpoch;
  final folderId = await db.insert(
      TableNames.folders, {'name': 'Test', 'position': 0, 'created_at': ts});
  await db.insert(TableNames.feeds, {
    'folder_id': folderId,
    'title': 'Feed',
    'url': 'https://example.com/feed',
    'consecutive_failures': 0,
    'is_dead': 0,
    'position': 0,
    'created_at': ts,
  });
}

Future<void> _tearDown() async => AppDatabase.instance.close();

Future<int> _count() async {
  final db = await AppDatabase.instance.database;
  final r = await db.rawQuery('SELECT COUNT(*) AS c FROM ${TableNames.articles}');
  return r.first['c'] as int;
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('runCleanup with configurable days', () {
    setUp(_setUp);
    tearDown(_tearDown);

    test('deletes read+unsaved articles older than the configured window', () async {
      const window = 10;
      final old = _now.subtract(const Duration(days: window + 1));
      await _repo.insertArticles(1, [_art(1, published: old)]);
      await _repo.markAllAsRead();
      final deleted = await _repo.runCleanup(days: window);
      expect(deleted, 1);
      expect(await _count(), 0);
    });

    test('keeps read articles within the configured window', () async {
      const window = 10;
      final recent = _now.subtract(const Duration(days: window - 1));
      await _repo.insertArticles(1, [_art(1, published: recent)]);
      await _repo.markAllAsRead();
      final deleted = await _repo.runCleanup(days: window);
      expect(deleted, 0);
      expect(await _count(), 1);
    });

    test('never deletes unread articles regardless of window', () async {
      const window = 5;
      final old = _now.subtract(const Duration(days: window + 5));
      await _repo.insertArticles(1, [_art(1, published: old)]);
      // NOT marked as read.
      final deleted = await _repo.runCleanup(days: window);
      expect(deleted, 0);
      expect(await _count(), 1);
    });

    test('never deletes saved (bookmarked) articles regardless of window', () async {
      const window = 5;
      final old = _now.subtract(const Duration(days: window + 5));
      await _repo.insertArticles(1, [_art(1, published: old)]);
      final db = await AppDatabase.instance.database;
      final id = (await db.query(TableNames.articles, limit: 1)).first['id'] as int;
      await _repo.setSaved(id, saved: true);
      await _repo.markAllAsRead();
      final deleted = await _repo.runCleanup(days: window);
      expect(deleted, 0);
      expect(await _count(), 1);
    });

    test('boundary: article exactly at N days is kept (strictly less than)', () async {
      const window = 10;
      // 5s inside the safe zone to avoid sub-ms race with DateTime.now() in runCleanup.
      final boundary = _now
          .subtract(const Duration(days: window))
          .add(const Duration(seconds: 5));
      await _repo.insertArticles(1, [_art(1, published: boundary)]);
      await _repo.markAllAsRead();
      final deleted = await _repo.runCleanup(days: window);
      expect(deleted, 0);
    });

    test('days clamped to minimum 5: value of 2 behaves as 5', () async {
      // Article 4 days old — older than 2 but within 5 — must NOT be deleted.
      final fourDaysOld = _now.subtract(const Duration(days: 4));
      await _repo.insertArticles(1, [_art(1, published: fourDaysOld)]);
      await _repo.markAllAsRead();
      final deleted = await _repo.runCleanup(days: 2); // clamped to 5
      expect(deleted, 0);
    });

    test('days clamped to maximum 20: value of 99 behaves as 20', () async {
      // Article 21 days old — older than 20 — must be deleted even with days=99.
      final twentyOneDaysOld = _now.subtract(const Duration(days: 21));
      await _repo.insertArticles(1, [_art(1, published: twentyOneDaysOld)]);
      await _repo.markAllAsRead();
      final deleted = await _repo.runCleanup(days: 99); // clamped to 20
      expect(deleted, 1);
    });

    test('window=5 deletes articles older than 5 days', () async {
      final sixDaysOld = _now.subtract(const Duration(days: 6));
      final fourDaysOld = _now.subtract(const Duration(days: 4));
      await _repo.insertArticles(1, [
        _art(1, published: sixDaysOld),
        _art(2, published: fourDaysOld),
      ]);
      await _repo.markAllAsRead();
      final deleted = await _repo.runCleanup(days: 5);
      expect(deleted, 1);
      expect(await _count(), 1);
    });

    test('window=20 keeps articles that window=7 would delete', () async {
      final tenDaysOld = _now.subtract(const Duration(days: 10));
      await _repo.insertArticles(1, [_art(1, published: tenDaysOld)]);
      await _repo.markAllAsRead();

      // Default window (7) would delete it.
      final deletedDefault = await _repo.runCleanup(days: kFetchDayLimit);
      expect(deletedDefault, 1);

      // Re-insert and try with window=20.
      await _repo.insertArticles(1, [_art(1, published: tenDaysOld)]);
      await _repo.markAllAsRead();
      final deletedWide = await _repo.runCleanup(days: 20);
      expect(deletedWide, 0);
    });
  });

  // ── AppSettings.cleanupAgeDays parsing & clamping ─────────────────────────

  group('AppSettings.cleanupAgeDays', () {
    test('default is 7 when key is absent', () {
      final s = AppSettings.fromMap({});
      expect(s.cleanupAgeDays, 7);
    });

    test('default seed value is 7', () {
      final seed = defaultSettings.firstWhere((e) => e['key'] == 'cleanup_age_days');
      expect(seed['value'], '7');
    });

    test('reads configured value correctly', () {
      final s = AppSettings.fromMap({'cleanup_age_days': '14'});
      expect(s.cleanupAgeDays, 14);
    });

    // The parse clamp's lower bound was widened from 5 to 2 so the Filter
    // bubble's 2–15 day slider can't set a value the model silently raises
    // back. The *meaning* of the setting is unchanged, and
    // ArticleRepository.runCleanup keeps its own independent clamp(5, 20) —
    // asserted separately below — so a stored 2 is preserved here but cleanup
    // still behaves as if it were 5.
    test('clamps below minimum to 2', () {
      final s = AppSettings.fromMap({'cleanup_age_days': '1'});
      expect(s.cleanupAgeDays, 2);
    });

    test('a value of 3 is now preserved rather than raised to 5', () {
      final s = AppSettings.fromMap({'cleanup_age_days': '3'});
      expect(s.cleanupAgeDays, 3);
    });

    test('clamps above maximum to 20', () {
      final s = AppSettings.fromMap({'cleanup_age_days': '30'});
      expect(s.cleanupAgeDays, 20);
    });

    test('value exactly at minimum (5) is kept', () {
      final s = AppSettings.fromMap({'cleanup_age_days': '5'});
      expect(s.cleanupAgeDays, 5);
    });

    test('value exactly at maximum (20) is kept', () {
      final s = AppSettings.fromMap({'cleanup_age_days': '20'});
      expect(s.cleanupAgeDays, 20);
    });

    test('non-numeric value falls back to 7', () {
      final s = AppSettings.fromMap({'cleanup_age_days': 'bogus'});
      expect(s.cleanupAgeDays, 7);
    });
  });
}
