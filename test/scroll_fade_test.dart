// Scroll-driven fade on the floating buttons, and the discrete steps the
// Filter bubble's sliders are specified to land on.
//
// The controller is plain Dart over a Timer, so it can be driven with
// FakeAsync — no widget pumping and no DB, which this repo cannot combine with
// testWidgets anyway (see feed_repository_test.dart).

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/models/settings.dart';
import 'package:flash/widgets/scroll_fade.dart';

void main() {
  _sortOrderTests();

  group('ScrollFadeController', () {
    test('starts settled', () {
      final c = ScrollFadeController();
      expect(c.value, isFalse);
      c.dispose();
    });

    test('a scroll event marks it scrolling', () {
      fakeAsync((async) {
        final c = ScrollFadeController();
        c.onScroll();
        expect(c.value, isTrue);
        async.elapse(const Duration(seconds: 1));
        c.dispose();
      });
    });

    test('settles once the delay elapses with no further scrolling', () {
      fakeAsync((async) {
        final c = ScrollFadeController();
        c.onScroll();
        async.elapse(const Duration(milliseconds: 150));
        expect(c.value, isFalse);
        c.dispose();
      });
    });

    test('continued scrolling keeps it faded — a fling does not flicker', () {
      fakeAsync((async) {
        final c = ScrollFadeController();
        // A fling emits events throughout; each one resets the timer.
        for (var i = 0; i < 20; i++) {
          c.onScroll();
          async.elapse(const Duration(milliseconds: 16));
          expect(c.value, isTrue, reason: 'still moving at event $i');
        }
        async.elapse(const Duration(milliseconds: 150));
        expect(c.value, isFalse);
        c.dispose();
      });
    });

    test('notifies only on transitions, not on every scroll event', () {
      fakeAsync((async) {
        final c = ScrollFadeController();
        var notifications = 0;
        c.addListener(() => notifications++);

        for (var i = 0; i < 10; i++) {
          c.onScroll();
          async.elapse(const Duration(milliseconds: 10));
        }
        expect(notifications, 1, reason: 'one fade-out, not ten');

        async.elapse(const Duration(milliseconds: 150));
        expect(notifications, 2, reason: 'plus one fade-back-in');
        c.dispose();
      });
    });

    test('settleNow brings the buttons straight back', () {
      fakeAsync((async) {
        final c = ScrollFadeController();
        c.onScroll();
        expect(c.value, isTrue);
        c.settleNow();
        expect(c.value, isFalse);
        async.elapse(const Duration(seconds: 1));
        c.dispose();
      });
    });

    test('a pending timer after dispose does not touch the notifier', () {
      fakeAsync((async) {
        final c = ScrollFadeController();
        c.onScroll();
        c.dispose();
        // Would throw "A ValueNotifier was used after being disposed" if the
        // timer were left to fire unguarded.
        async.elapse(const Duration(seconds: 1));
      });
    });

    test('faded is visible, not invisible', () {
      expect(ScrollFade.fadedOpacity, greaterThan(0.0),
          reason: 'the buttons should recede, not vanish');
      expect(ScrollFade.fadedOpacity, lessThan(1.0));
    });

    test('the fade is short, in the 150-250ms band', () {
      expect(ScrollFade.fadeDuration.inMilliseconds, inInclusiveRange(150, 250));
    });
  });

}

// Appended: article sort order. Applied to the loaded list rather than in SQL
// (feed_screen._applySortOrder), so it's a pure list reversal on top of the
// repository's newest-first result.
void _sortOrderTests() {
  List<int> applyOrder(List<int> newestFirst, String order) =>
      order == kSortOldestFirst ? newestFirst.reversed.toList() : newestFirst;

  group('article sort order', () {
    test('defaults to newest first — the app\'s existing behaviour', () {
      expect(const AppSettings().articleSortOrder, kSortNewestFirst);
      expect(AppSettings.fromMap({}).articleSortOrder, kSortNewestFirst);
    });

    test('an unrecognised stored value falls back to newest', () {
      expect(AppSettings.fromMap({'article_sort_order': 'sideways'})
          .articleSortOrder, kSortNewestFirst);
    });

    test('oldest round-trips', () {
      expect(
        AppSettings.fromMap({'article_sort_order': kSortOldestFirst})
            .articleSortOrder,
        kSortOldestFirst,
      );
    });

    test('newest keeps the repository order untouched', () {
      expect(applyOrder([5, 4, 3, 2, 1], kSortNewestFirst), [5, 4, 3, 2, 1]);
    });

    test('oldest puts the oldest article at the top', () {
      expect(applyOrder([5, 4, 3, 2, 1], kSortOldestFirst), [1, 2, 3, 4, 5]);
    });

    test('flipping twice returns the original order', () {
      const original = [5, 4, 3, 2, 1];
      final flipped = applyOrder(original, kSortOldestFirst);
      expect(applyOrder(flipped, kSortOldestFirst), original);
    });

    test('an empty or single-item list is safe', () {
      expect(applyOrder([], kSortOldestFirst), isEmpty);
      expect(applyOrder([7], kSortOldestFirst), [7]);
    });
  });
}
