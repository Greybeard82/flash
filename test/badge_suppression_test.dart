// Reaching the bottom of a feed zeroes that tab's badge.
//
// Written independently of the implementation. Reaching the end means the user
// has seen it, so the badge drops to zero immediately even though articles at
// the bottom are still unread. This is display-only: nothing is written, and
// the true count returns the moment the scope is cleared — which happens when
// new articles arrive for it, or on cold start.
//
// The interesting case is the All badge. Zeroing one category must not zero
// All, or clearing Gaming would silently claim the whole app is caught up.

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/unread_counts.dart';

UnreadCounts _counts({int gaming = 0, int news = 0, int tech = 0}) =>
    UnreadCounts.fromRepository(
      total: gaming + news + tech,
      byFolder: {1: gaming, 2: news, 3: tech},
    );

void main() {
  test('an empty scope set changes nothing', () {
    final before = _counts(gaming: 3, news: 5, tech: 2);
    final after = before.withZeroedScopes({});

    expect(identical(after, before), isTrue,
        reason: 'the common case must not allocate or alter anything');
  });

  test('a zeroed folder reports 0', () {
    final after = _counts(gaming: 3, news: 5, tech: 2).withZeroedScopes({1});

    expect(after.forFolder(1), 0);
    expect(after.forFolder(2), 5, reason: 'untouched folders keep their count');
    expect(after.forFolder(3), 2);
  });

  test('All reports the sum over the folders that are not zeroed', () {
    final after = _counts(gaming: 3, news: 5, tech: 2).withZeroedScopes({1});

    expect(after.all, 7,
        reason: 'clearing Gaming must not claim the whole app is caught up — '
            'News and Tech still have unread articles');
  });

  test('zeroing All reports 0 everywhere it matters', () {
    final after =
        _counts(gaming: 3, news: 5, tech: 2).withZeroedScopes({kAllScope});

    expect(after.all, 0);
    expect(after.forFolder(1), 3,
        reason: 'the All badge is suppressed, but the folder tabs still show '
            'what is genuinely unread in each');
  });

  test('several folders can be zeroed at once', () {
    final after = _counts(gaming: 3, news: 5, tech: 2).withZeroedScopes({1, 2});

    expect(after.forFolder(1), 0);
    expect(after.forFolder(2), 0);
    expect(after.forFolder(3), 2);
    expect(after.all, 2);
  });

  test('zeroing every folder leaves All at 0 without zeroing All directly',
      () {
    final after =
        _counts(gaming: 3, news: 5, tech: 2).withZeroedScopes({1, 2, 3});

    expect(after.all, 0,
        reason: 'the sum over an all-zeroed set is zero, which is the right '
            'answer without needing kAllScope');
  });

  test('clearing the set restores the true counts', () {
    final before = _counts(gaming: 3, news: 5, tech: 2);
    final suppressed = before.withZeroedScopes({1, kAllScope});
    expect(suppressed.all, 0);

    // What _clearZeroedScopes amounts to: the next read applies no suppression.
    final restored = before.withZeroedScopes({});

    expect(restored.all, 10);
    expect(restored.forFolder(1), 3);
  });

  test('suppression never mutates the counts it was given', () {
    final before = _counts(gaming: 3, news: 5, tech: 2);
    before.withZeroedScopes({1, 2, 3, kAllScope});

    expect(before.all, 10,
        reason: 'display-only means display-only — the source counts, which '
            'come straight from the database, must be untouched');
    expect(before.forFolder(1), 3);
  });

  test('an unknown scope id is harmless', () {
    final after = _counts(gaming: 3, news: 5).withZeroedScopes({99});

    expect(after.all, 8,
        reason: 'a folder deleted while its scope was zeroed must not corrupt '
            'the totals');
  });
}
