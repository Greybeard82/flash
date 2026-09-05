// What one alert notification is allowed to say, and which one it replaces.
//
// Two separate defects lived in the old keyword-alert notification path in
// RefreshService, and both were invisible in the code that produced them:
//
// (a) every alert was posted under one hardcoded id
//     (`const int _kKeywordNotificationId = 2`). Android treats (id, tag) as
//     the identity of a notification, so posting a second alert did not add a
//     second line to the shade — it OVERWROTE the first one. A user away from
//     the phone while three unrelated keywords hit saw exactly one
//     notification: the last. The other two were destroyed by the system, not
//     missed by the user.
//
// (b) the body was assembled by joining every keyword matched anywhere in the
//     pass into a single sentence — `New articles matching "zelda", "crypto"`
//     — so two completely unrelated alerts arrived as one indivisible blob.
//     Tapping it could only lead somewhere generic, and there was no way to
//     tell whether "crypto" had hit once or forty times.
//
// The replacement is a pure decision function: `planAlertNotifications` takes
// the alert_matches rows ACTUALLY written this pass plus a callback for the
// running total, and returns one plan per distinct keyword SET. The set is
// what earns a notification id (see `notificationIdFor` below), so two
// keywords can no longer evict each other, and one article that hits two
// keywords is still exactly one notification.
//
// This file deliberately touches neither the database nor
// flutter_local_notifications: the planner is where the rules live, and the
// rules are testable without either. Running totals are staged in a plain Map
// so each scenario states its own history out loud.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart). The
// notificationIdFor group at the bottom is the one part that needs a real
// database, and it carries its own setUp.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/models/alert_match.dart';
import 'package:flash/repositories/alert_match_repository.dart';
import 'package:flash/services/alert_notification_planner.dart';

const int _now = 1750000000000;

// ── Helpers ────────────────────────────────────────────────────────────────

/// One row as it would come back from `AlertMatchRepository.insertMatches` —
/// i.e. a match genuinely written this pass, not merely re-parsed out of the
/// feed XML again.
AlertMatch _match(
  String guid,
  String keyword, {
  int feedId = 1,
  int matchedAt = _now,
}) =>
    AlertMatch(
      feedId: feedId,
      guid: guid,
      keyword: keyword,
      title: 'Article $guid',
      url: 'https://example.com/$guid',
      matchedAt: matchedAt,
    );

/// The staged running totals, standing in for
/// `AlertMatchRepository.countForKeywordSet`.
///
/// Keys are the sorted keywords joined with '|'. Every lookup is recorded, so
/// a test can assert the planner hands the callback a SORTED list rather than
/// whatever order the matches happened to arrive in. An unstaged key fails
/// rather than returning zero: it means the planner grouped the matches into a
/// set the scenario never described, which would otherwise surface as a
/// baffling `count == 0`.
class _Totals {
  _Totals(this._byKey);

  final Map<String, int> _byKey;
  final List<List<String>> calls = <List<String>>[];

  int call(List<String> sortedKeywords) {
    calls.add(List<String>.of(sortedKeywords));
    final key = sortedKeywords.join('|');
    final total = _byKey[key];
    if (total == null) {
      fail('planAlertNotifications asked for the running total of {$key}, '
          'which this scenario never staged — the matches were grouped into a '
          'keyword set the test did not describe');
    }
    return total;
  }
}

/// AlertNotificationPlan carries no value equality in the contract, so plans
/// are compared through a signature rather than with `==`.
String _sig(AlertNotificationPlan p) =>
    '${p.keywords.join('|')}/${p.kind}/${p.count}';

/// The single plan for [keywords], failing loudly if the planner emitted none
/// or more than one.
AlertNotificationPlan _planFor(
    List<AlertNotificationPlan> plans, List<String> keywords) {
  final key = keywords.join('|');
  final hits = plans.where((p) => p.keywords.join('|') == key).toList();
  expect(hits, hasLength(1),
      reason: 'expected exactly one notification for {${keywords.join(', ')}}, '
          'got ${plans.map(_sig).toList()}');
  return hits.first;
}

bool _isSorted(List<String> keywords) {
  for (var i = 1; i < keywords.length; i++) {
    if (keywords[i - 1].compareTo(keywords[i]) > 0) return false;
  }
  return true;
}

void main() {
  group('planAlertNotifications', () {
    // ── One keyword, one article ─────────────────────────────────────────

    test('the very first article for a keyword announces the article itself',
        () {
      final totals = _Totals({'zelda': 1});

      final plans = planAlertNotifications(
        newMatches: [_match('a1', 'zelda')],
        runningTotalFor: totals.call,
      );

      expect(plans, hasLength(1));
      expect(plans.single.keywords, ['zelda']);
      expect(plans.single.kind, AlertBodyKind.first,
          reason: 'with a single entry there is nothing to tally, so the '
              'notification names the article rather than reporting a count');
      expect(plans.single.count, 1);
    });

    test('a second article for the same keyword reports the running total',
        () {
      final totals = _Totals({'zelda': 2});

      final plans = planAlertNotifications(
        newMatches: [_match('a2', 'zelda')],
        runningTotalFor: totals.call,
      );

      expect(plans, hasLength(1));
      expect(plans.single.kind, AlertBodyKind.count,
          reason: 'the Alerts tab now holds two entries for this keyword, so '
              'naming only the newest one would hide the other');
      expect(plans.single.count, 2);
    });

    test('an arrival after a backfill of eight counts nine, never "first"', () {
      // Adding a keyword backfills every article already on the device. The
      // next genuinely new arrival is the first notification the user has ever
      // seen for this keyword, but it is not the first ENTRY.
      final totals = _Totals({'zelda': 9});

      final plans = planAlertNotifications(
        newMatches: [_match('a9', 'zelda')],
        runningTotalFor: totals.call,
      );

      expect(plans.single.kind, AlertBodyKind.count,
          reason: 'the running total IS the state — there is no separate '
              '"have I notified for this keyword before" flag to consult, so a '
              'keyword sitting on eight backfilled entries must never be '
              'described as a first hit');
      expect(plans.single.count, 9,
          reason: 'the body counts everything waiting in the Alerts tab, not '
              'the one row written this pass');
    });

    test('binning every entry for a keyword makes the next arrival first again',
        () {
      // The user swipes away all their "zelda" alerts and the group empties.
      // The next match starts the count over.
      final totals = _Totals({'zelda': 1});

      final plans = planAlertNotifications(
        newMatches: [_match('a10', 'zelda')],
        runningTotalFor: totals.call,
      );

      expect(plans.single.kind, AlertBodyKind.first,
          reason: 'reading the total back after insertion is exactly why no '
              '"already notified" flag exists — a flag would have stayed set '
              'through the deletion and reported a stale tally forever');
      expect(plans.single.count, 1);
    });

    // ── Several keywords on one article ──────────────────────────────────

    test('an article matching two keywords is one notification, not two', () {
      final totals = _Totals({'mario|zelda': 3});

      final plans = planAlertNotifications(
        newMatches: [
          _match('a20', 'zelda'),
          _match('a20', 'mario'),
        ],
        runningTotalFor: totals.call,
      );

      expect(plans, hasLength(1),
          reason: 'one article is one thing to read; two notifications for it '
              'would put the same headline in the shade twice');
      expect(plans.single.keywords, ['mario', 'zelda'],
          reason: 'the keyword list is sorted so the same pair always resolves '
              'to the same notification id, whichever keyword matched first');
      expect(plans.single.kind, AlertBodyKind.combined);
      expect(plans.single.count, 3,
          reason: 'the count is the intersection total — entries carrying BOTH '
              'keywords, not the sum of the two groups');
      expect(plans.any((p) => p.keywords.length == 1), isFalse,
          reason: 'a combined group must not also emit per-keyword plans; that '
              'turns the old blob-body bug into duplicate notifications');
    });

    test('three keywords on one article list all three, sorted', () {
      final totals = _Totals({'crypto|mario|zelda': 1});

      final plans = planAlertNotifications(
        // Deliberately not alphabetical: match order follows the feed, not the
        // keyword table.
        newMatches: [
          _match('a21', 'zelda'),
          _match('a21', 'crypto'),
          _match('a21', 'mario'),
        ],
        runningTotalFor: totals.call,
      );

      expect(plans, hasLength(1));
      expect(plans.single.keywords, ['crypto', 'mario', 'zelda']);
      expect(plans.single.kind, AlertBodyKind.combined,
          reason: 'a combined set stays combined at any size — it never '
              'collapses to "first" just because its intersection total is 1');
      expect(plans.single.count, 1);
    });

    // ── Several articles in one pass ─────────────────────────────────────

    test('two articles on the same keyword are one notification, not one each',
        () {
      final totals = _Totals({'zelda': 2});

      final plans = planAlertNotifications(
        newMatches: [
          _match('a30', 'zelda'),
          _match('a31', 'zelda'),
        ],
        runningTotalFor: totals.call,
      );

      expect(plans, hasLength(1),
          reason: 'a refresh pulling five matching articles must not stack '
              'five notifications; the keyword set is the unit, not the row');
      expect(plans.single.kind, AlertBodyKind.count);
      expect(plans.single.count, 2);
    });

    test('two articles matching the same pair are one combined notification',
        () {
      final totals = _Totals({'mario|zelda': 2});

      final plans = planAlertNotifications(
        newMatches: [
          _match('a40', 'zelda'),
          _match('a40', 'mario'),
          _match('a41', 'mario'),
          _match('a41', 'zelda'),
        ],
        runningTotalFor: totals.call,
      );

      expect(plans, hasLength(1),
          reason: 'both articles share one keyword-set signature, so they '
              'share one notification id and one line in the shade');
      expect(plans.single.keywords, ['mario', 'zelda']);
      expect(plans.single.kind, AlertBodyKind.combined);
      expect(plans.single.count, 2);
    });

    test('a single-keyword article and a two-keyword article get one plan each',
        () {
      final totals = _Totals({'zelda': 4, 'mario|zelda': 1});

      final plans = planAlertNotifications(
        newMatches: [
          _match('a50', 'zelda'),
          _match('a51', 'zelda'),
          _match('a51', 'mario'),
        ],
        runningTotalFor: totals.call,
      );

      expect(plans, hasLength(2),
          reason: 'distinct keyword sets are distinct alerts — this is the '
              'case the single hardcoded id used to destroy, keeping only '
              'whichever was posted last');

      final zelda = _planFor(plans, ['zelda']);
      expect(zelda.kind, AlertBodyKind.count);
      expect(zelda.count, 4);

      final pair = _planFor(plans, ['mario', 'zelda']);
      expect(pair.kind, AlertBodyKind.combined);
      expect(pair.count, 1,
          reason: 'the pair is counted on its own intersection, uninfluenced '
              'by how many entries the "zelda" group holds');
    });

    // ── Nothing new, and determinism ─────────────────────────────────────

    test('a fetch that found nothing genuinely new produces no notification',
        () {
      final totals = _Totals({});

      final plans = planAlertNotifications(
        newMatches: const [],
        runningTotalFor: totals.call,
      );

      expect(plans, isEmpty,
          reason: 'RSS feeds re-serve their last N items on every poll; if the '
              'planner spoke up for re-seen articles the user would be '
              'notified about the same headline every thirty minutes');
      expect(totals.calls, isEmpty,
          reason: 'with nothing written there is nothing to count — the '
              'planner should not even reach for a running total');
    });

    test('feeding the same matches in reverse order yields the same plans', () {
      final matches = [
        _match('a60', 'zelda'),
        _match('a61', 'zelda', matchedAt: _now + 1),
        _match('a61', 'mario', matchedAt: _now + 1),
        _match('a62', 'crypto', matchedAt: _now + 2),
      ];
      final staged = {'zelda': 5, 'mario|zelda': 2, 'crypto': 1};

      final forward = planAlertNotifications(
        newMatches: matches,
        runningTotalFor: _Totals(staged).call,
      );
      final backward = planAlertNotifications(
        newMatches: matches.reversed.toList(),
        runningTotalFor: _Totals(staged).call,
      );

      expect(forward, hasLength(3));
      expect(backward.map(_sig).toList(), forward.map(_sig).toList(),
          reason: 'plan order must not depend on the order feeds happened to '
              'be fetched in, or the same alert would be described differently '
              'from one refresh to the next');
    });

    test('the running total is looked up with the keyword list already sorted',
        () {
      final totals = _Totals({'mario|zelda': 2});

      planAlertNotifications(
        // Reverse alphabetical on purpose.
        newMatches: [
          _match('a70', 'zelda'),
          _match('a70', 'mario'),
        ],
        runningTotalFor: totals.call,
      );

      expect(totals.calls, isNotEmpty);
      for (final call in totals.calls) {
        expect(_isSorted(call), isTrue,
            reason: 'countForKeywordSet and notificationIdFor both key off the '
                'sorted list; handing either an unsorted one mints a second id '
                'for a set that already has one, and the two notifications '
                'then sit in the shade as duplicates of each other');
      }
      expect(totals.calls, contains(['mario', 'zelda']));
    });
  });

  // ── The id the plan is posted under ──────────────────────────────────────

  group('AlertMatchRepository.notificationIdFor', () {
    // The one part of this file that needs real I/O: the id is a rowid in
    // alert_notification_ids, so that a keyword set keeps the same id across a
    // process restart. No folder or feed seeding — that table deliberately
    // carries no foreign keys.
    late AlertMatchRepository repo;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppDatabase.useForTesting();
      await AppDatabase.instance.database;
      repo = AlertMatchRepository();
    });

    tearDown(() => AppDatabase.instance.close());

    test('the same keyword set always gets the same id', () async {
      final first = await repo.notificationIdFor(['zelda']);
      final second = await repo.notificationIdFor(['zelda']);

      expect(second, first,
          reason: 'a keyword that alerts twice must reuse its id so the second '
              'notification updates the first rather than piling up a fresh '
              'one in the shade on every refresh');
    });

    test('the two orderings of a pair collapse to one id', () async {
      final ab = await repo.notificationIdFor(['mario', 'zelda']);
      final ba = await repo.notificationIdFor(['zelda', 'mario']);

      expect(ba, ab,
          reason: 'the key is canonical, so an unsorted call cannot mint a '
              'second id for a set that already owns one — that would put the '
              'same article in the shade twice');
    });

    test('a keyword and a pair containing it get different ids', () async {
      final single = await repo.notificationIdFor(['zelda']);
      final pair = await repo.notificationIdFor(['mario', 'zelda']);

      expect(pair, isNot(single),
          reason: 'this is the bug being fixed: a shared id made the combined '
              'alert silently replace the standing "zelda" one');
    });

    test('ids stay clear of the ids the rest of the app posts under', () async {
      final ids = [
        await repo.notificationIdFor(['zelda']),
        await repo.notificationIdFor(['mario', 'zelda']),
      ];

      for (final id in ids) {
        expect(id, greaterThanOrEqualTo(2000),
            reason: 'alert ids are offset into their own range so a rowid of 2 '
                'cannot collide with the fixed id the old keyword notification '
                'used, nor with any other notification the app posts');
      }
    });

    test('a third distinct keyword set gets a third distinct id', () async {
      final ids = <int>{
        await repo.notificationIdFor(['zelda']),
        await repo.notificationIdFor(['mario', 'zelda']),
        await repo.notificationIdFor(['crypto']),
      };

      expect(ids, hasLength(3),
          reason: 'three unrelated alerts must be able to sit in the shade at '
              'the same time; one shared id is what reduced them to one');
    });
  });
}
