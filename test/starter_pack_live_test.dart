// The live gate on the starter pack.
//
// The app was pulled from Google Play under the News and Magazines policy
// because a fresh install showed no news. The starter pack is the fix, which
// makes "does every feed in it actually produce articles?" a release
// question rather than a nicety — and it cannot be answered offline. A feed
// can be reachable, well-formed and still seed a visibly empty category:
// `applyFetchThresholds` drops every item with no pubDate and everything
// published more than `kFetchDayLimit` days ago, so a publisher that has gone
// quiet for a week looks exactly like the screen the reviewer saw.
//
// So this runs the real pipeline, deliberately:
//   - the same `http.get` with the same 20s timeout as `fetchAndStore`, with
//     the default Dart User-Agent, because a feed that 403s our real client
//     is a feed that will 403 on the user's phone;
//   - the real parser, through `RssService.parseForTesting`;
//   - the real `applyFetchThresholds` at the default article limit.
//
// Skipped by default — a normal `flutter test` must not depend on fifteen
// third-party servers. Run it on purpose:
//
//   flutter test test/starter_pack_live_test.dart --dart-define=LIVE_NETWORK=true
//
// Pass marks. Feed: HTTP 200, parses, >= 1 article after thresholds.
// Category: every feed in it passing, and >= 5 articles in total.
//
// That is "every feed" rather than the original ">= 2 passing feeds" because
// two categories now legitimately hold one feed each
// (kSingleFeedStarterCategories) — a fixed floor of 2 would fail them
// permanently and stop meaning anything. Requiring all of a category's feeds
// to pass is the stricter reading and keeps a single-feed category honest:
// there is no spare to hide behind.
//
// A failing feed whose category still clears the bar without it gets removed
// from the pack; a failing category stops the pass and goes back to David —
// replacement publishers are his call, not this test's.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flash/data/starter_pack.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/repositories/article_repository.dart';
import 'package:flash/repositories/feed_repository.dart';
import 'package:flash/services/rss_service.dart';
import 'package:flash/utils/constants.dart';

const bool _live = bool.fromEnvironment('LIVE_NETWORK');

class _Row {
  final String category;
  final String feed;
  final String status;
  final int parsed;
  final int accepted;
  final String newest;

  const _Row(this.category, this.feed, this.status, this.parsed, this.accepted,
      this.newest);

  bool get passed => status == '200' && accepted >= 1;
}

String _pad(String s, int width) =>
    s.length >= width ? s.substring(0, width) : s.padRight(width);

void main() {
  // flutter_test installs an HttpOverrides that fails every real request with
  // "400: Test failed. No HttpClient..." — the guard that stops an ordinary
  // unit test hitting the network by accident. This file wants the network on
  // purpose, so it puts the plain Dart client back for the duration.
  setUpAll(() => HttpOverrides.global = null);

  test('every starter feed produces articles through the real pipeline',
      () async {
    // fetchAndStore's own path, minus the DB: the service is built with real
    // repositories (never touched — nothing here inserts) so the parser under
    // test is the production one.
    final rss = RssService(ArticleRepository(), FeedRepository());
    final rows = <_Row>[];

    for (final category in kStarterPack) {
      for (final starter in category.feeds) {
        // id is required by _fromRssItems; 1 is a placeholder, nothing is
        // written anywhere.
        final feed = Feed(
          id: 1,
          folderId: 1,
          title: starter.title,
          url: starter.url,
          siteUrl: starter.siteUrl,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        String status;
        var parsed = 0;
        var accepted = 0;
        var newest = '-';
        try {
          final response = await http
              .get(Uri.parse(starter.url))
              .timeout(const Duration(seconds: 20));
          status = '${response.statusCode}';
          if (response.statusCode == 200) {
            final body = utf8.decode(response.bodyBytes, allowMalformed: true);
            final articles = rss.parseForTesting(body, feed);
            parsed = articles.length;
            final kept = rss.applyFetchThresholds(
              articles,
              articleLimit: kFetchArticleLimit,
            );
            accepted = kept.length;
            if (kept.isNotEmpty && kept.first.publishedAt != null) {
              newest = DateTime.fromMillisecondsSinceEpoch(
                      kept.first.publishedAt!)
                  .toUtc()
                  .toIso8601String()
                  .substring(0, 16);
            }
          }
        } catch (e) {
          status = e.runtimeType.toString();
        }

        rows.add(_Row(category.id, starter.title, status, parsed, accepted,
            newest));
      }
    }

    // ignore: avoid_print
    print('\n${_pad('CATEGORY', 16)} ${_pad('FEED', 28)} ${_pad('HTTP', 18)} '
        '${_pad('PARSED', 7)} ${_pad('KEPT', 5)} NEWEST (UTC)');
    // ignore: avoid_print
    print('-' * 100);
    for (final r in rows) {
      // ignore: avoid_print
      print('${_pad(r.category, 16)} ${_pad(r.feed, 28)} '
          '${_pad(r.status, 18)} ${_pad('${r.parsed}', 7)} '
          '${_pad('${r.accepted}', 5)} ${r.newest}');
    }
    // ignore: avoid_print
    print('');

    final failedFeeds = rows.where((r) => !r.passed).toList();
    final failedCategories = <String>[];
    for (final category in kStarterPack) {
      final mine = rows.where((r) => r.category == category.id);
      final passing = mine.where((r) => r.passed).length;
      final articles =
          mine.where((r) => r.passed).fold<int>(0, (sum, r) => sum + r.accepted);
      if (passing < category.feeds.length || articles < 5) {
        failedCategories.add(category.id);
      }
    }

    expect(failedCategories, isEmpty,
        reason: 'a starter category cannot carry itself: '
            '${failedCategories.join(', ')}. Stop and ask David for '
            'replacement publishers — do not pick them here.');
    expect(failedFeeds.map((r) => '${r.category}/${r.feed} (${r.status}, '
        '${r.accepted} kept)'), isEmpty,
        reason: 'these feeds seed nothing. Remove each from starter_pack.dart '
            'if its category still passes without it.');
  }, timeout: const Timeout(Duration(minutes: 5)), skip: !_live);
}
