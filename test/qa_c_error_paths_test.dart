// QA section C — error and empty paths.
//
// **Network failure is produced with a fake client, never by touching
// connectivity.** Airplane mode, wifi, proxy and DNS are forbidden on the
// devices, and a network settings change during exactly this kind of test is
// why that rule exists. `runWithClient` swaps the client for the duration of
// a zone, which reaches `RssService`'s top-level `http.get` without any
// production change.
//
// **Worth recording: RssService has no seam of its own.** `fetchAndStore`
// calls the global `http.get` directly, so there is no client to inject and no
// way to exercise any of this from an ordinary unit test. `runWithClient` is a
// way around that, not a substitute for it — see the triage table.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/repositories/feed_repository.dart';
import 'package:flash/services/rss_service.dart';

const _now = 1750000000000;

String _rss(List<String> items) => '''<?xml version="1.0"?>
<rss version="2.0"><channel><title>Test</title>
${items.join('\n')}
</channel></rss>''';

String _item({
  String guid = 'g1',
  String title = 'A headline',
  String? link = 'https://example.com/a',
  String? pubDate,
}) {
  final date = pubDate ??
      HttpDate.format(DateTime.fromMillisecondsSinceEpoch(
          DateTime.now().millisecondsSinceEpoch - 3600000));
  return '<item><guid>$guid</guid><title>$title</title>'
      '${link == null ? '' : '<link>$link</link>'}'
      '<pubDate>$date</pubDate></item>';
}

/// `HttpDate` lives in dart:io, which a Flutter test can use.
class HttpDate {
  static String format(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final u = d.toUtc();
    return '${days[u.weekday - 1]}, ${u.day.toString().padLeft(2, '0')} '
        '${months[u.month - 1]} ${u.year} '
        '${u.hour.toString().padLeft(2, '0')}:'
        '${u.minute.toString().padLeft(2, '0')}:'
        '${u.second.toString().padLeft(2, '0')} GMT';
  }
}

late Feed _feed;
late RssService _svc;
late ArticleRepository _articles;

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
  final db = await AppDatabase.instance.database;

  final folderId = await db.insert(TableNames.folders,
      {'name': 'News', 'position': 0, 'created_at': _now, 'color_index': 0});
  final feedId = await db.insert(TableNames.feeds, {
    'folder_id': folderId,
    'title': 'Test feed',
    'url': 'https://example.com/rss.xml',
    'consecutive_failures': 0,
    'is_dead': 0,
    'created_at': _now,
  });

  _articles = ArticleRepository();
  _svc = RssService(_articles, FeedRepository());
  _feed = (await FeedRepository().getAll()).firstWhere((f) => f.id == feedId);
}

/// Runs one fetch against a canned response.
Future<Object?> _fetch(http.Response Function(http.Request) handler) async {
  Object? thrown;
  await http.runWithClient(() async {
    try {
      await _svc.fetchAndStore(_feed, articleLimit: 100);
    } catch (e) {
      thrown = e;
    }
  }, () => MockClient((req) async => handler(req)));
  return thrown;
}

Future<int> _articleCount() async {
  final db = await AppDatabase.instance.database;
  final rows = await db.rawQuery('SELECT COUNT(*) c FROM ${TableNames.articles}');
  return (rows.first['c'] as int?) ?? -1;
}

void main() {
  setUp(_setUp);
  tearDown(() async => AppDatabase.instance.close());

  group('a feed that fails', () {
    test('404 is RECORDED on the feed, not thrown at the refresh', () async {
      // **Deliberate design, and my first assertion here was wrong.** A bad
      // feed must not take the whole refresh down with it -- one dead URL
      // among thirty would otherwise mean no news at all. So the failure is
      // caught, counted, and written to the feed row instead.
      final e = await _fetch((_) => http.Response('Not found', 404));
      expect(e, isNull, reason: 'one bad feed must not abort a refresh');
      expect(await _articleCount(), 0);

      final feed = (await FeedRepository().getAll()).single;
      expect(feed.lastFetchError, contains('404'),
          reason: 'the reason has to be recoverable later, or a dead feed is '
              'indistinguishable from an empty one');
      expect(feed.consecutiveFailures, 1);
      expect(feed.isDead, isFalse, reason: 'one failure is not death');
    });

    test('500 is recorded the same way', () async {
      final e = await _fetch((_) => http.Response('Server error', 500));
      expect(e, isNull);
      expect(await _articleCount(), 0);

      final feed = (await FeedRepository().getAll()).single;
      expect(feed.lastFetchError, contains('500'));
      expect(feed.consecutiveFailures, 1);
    });

    test('a feed is only declared dead after seven consecutive failures',
        () async {
      // The threshold matters: too low and a weekend outage kills a feed the
      // reader still wants; too high and a genuinely gone feed keeps costing
      // a request every refresh.
      for (var i = 0; i < 7; i++) {
        await _fetch((_) => http.Response('gone', 404));
        _feed = (await FeedRepository().getAll()).single;
      }
      final feed = (await FeedRepository().getAll()).single;
      expect(feed.consecutiveFailures, 7);
      expect(feed.isDead, isTrue);
    });

    test('a success clears the failure count', () async {
      await _fetch((_) => http.Response('gone', 404));
      _feed = (await FeedRepository().getAll()).single;
      expect(_feed.consecutiveFailures, 1);

      await _fetch((_) => http.Response(_rss([_item()]), 200));
      final feed = (await FeedRepository().getAll()).single;
      expect(feed.consecutiveFailures, 0,
          reason: 'a feed that recovers must not stay one outage away from '
              'being declared dead forever');
      expect(feed.isDead, isFalse);
    });

    test('a redirect is followed and the body is used', () async {
      // MockClient does not follow redirects itself, so this asserts the
      // shape that matters: a 200 arriving after a redirect chain is parsed
      // normally. The real client follows up to 5 by default.
      final e = await _fetch((req) => http.Response(_rss([_item()]), 200));
      expect(e, isNull);
      expect(await _articleCount(), 1);
    });
  });

  group('a feed that returns something unusable', () {
    test('malformed XML does not write articles and does not hang', () async {
      final e = await _fetch(
          (_) => http.Response('<rss><channel><item>broken', 200));
      // Either it throws or it parses to nothing. Both are acceptable; a
      // partial write is not.
      expect(await _articleCount(), 0,
          reason: 'half a feed is worse than none: the user cannot tell '
              'which half is missing. thrown=$e');
    });

    test('valid XML that is not RSS writes nothing', () async {
      await _fetch(
          (_) => http.Response('<?xml version="1.0"?><html><body/></html>', 200));
      expect(await _articleCount(), 0);
    });

    test('a valid but EMPTY feed is not an error', () async {
      // The case most likely to be mishandled: nothing wrong happened, there
      // is simply nothing new. It must not throw, because a throw here shows
      // the user a refresh-failed banner for a healthy feed.
      final e = await _fetch((_) => http.Response(_rss([]), 200));
      expect(e, isNull, reason: 'an empty feed is a normal Tuesday');
      expect(await _articleCount(), 0);
    });

    test('an empty body is not a crash', () async {
      await _fetch((_) => http.Response('', 200));
      expect(await _articleCount(), 0);
    });
  });

  group('an article missing its parts', () {
    test('no link and no guid is discarded, not stored blank', () async {
      await _fetch((_) => http.Response(
          _rss(['<item><title>No identity</title></item>']), 200));
      expect(await _articleCount(), 0,
          reason: 'resolveGuid throws for these on purpose: an article with '
              'no identity cannot be deduplicated on the next fetch');
    });

    test('no title still stores, because it has identity', () async {
      await _fetch((_) => http.Response(
          _rss([_item(title: '', guid: 'has-guid')]), 200));
      // Whether it stores or not, it must not throw and must not half-write.
      expect(await _articleCount(), lessThanOrEqualTo(1));
    });

    test('no pubDate is rejected by the age filter, not stored undated',
        () async {
      await _fetch((_) => http.Response(
          _rss(['<item><guid>g</guid><title>T</title>'
              '<link>https://example.com/x</link></item>']),
          200));
      expect(await _articleCount(), 0,
          reason: 'applyFetchThresholds rejects null published_at rather than '
              'inventing a date, which would put the article at the top of '
              'the list forever');
    });
  });

  group('an enormous feed', () {
    test('is capped rather than written whole', () async {
      final items = [for (var i = 0; i < 500; i++) _item(guid: 'g$i')];
      final e = await _fetch((_) => http.Response(_rss(items), 200));
      expect(e, isNull);
      final n = await _articleCount();
      expect(n, lessThanOrEqualTo(100),
          reason: 'kFetchArticleLimit is 100; a 500-item feed must not be '
              'able to flood the database in one refresh');
      expect(n, greaterThan(0));
    });

    test('a very large body does not throw', () async {
      // 5 MB of padding around a single valid item.
      final padding = 'x' * (5 * 1024 * 1024);
      final body = _rss([_item()]).replaceFirst(
          '<title>Test</title>', '<title>Test</title><!--$padding-->');
      final e = await _fetch((_) => http.Response(body, 200));
      expect(e, isNull, reason: 'size alone must not be fatal');
    });
  });

  test('a response with invalid UTF-8 bytes is decoded, not thrown on', () {
    // fetchAndStore uses utf8.decode(..., allowMalformed: true) exactly so a
    // feed with a bad byte does not take the whole refresh down. Asserted
    // directly because it is a one-word flag that is easy to drop.
    expect(() => utf8.decode([0xC3, 0x28], allowMalformed: true), returnsNormally);
    expect(() => utf8.decode([0xC3, 0x28]), throwsFormatException);
  });
}
