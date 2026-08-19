// BottomDwellTimer state-machine tests.
//
// Plain Dart, no Flutter/DB — this is the pure timer logic behind the
// "reached the end of a feed, mark it read" setting, kept isolated from
// FeedScreen precisely so it can be exercised with FakeAsync (this codebase's
// widget tests can't combine testWidgets() with real sqflite I/O, see
// feed_repository_test.dart).
//
// The delay is user-configurable in 5-second steps, with 0 meaning
// "immediately", and the whole behaviour can be switched off.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/utils/bottom_dwell_timer.dart';

void main() {
  group('default 5s delay', () {
    test('fires after the full duration once at bottom', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 5));

        expect(fired, 1);
      });
    });

    test('does not fire before the duration elapses', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(milliseconds: 4500));

        expect(fired, 0);
        expect(dwell.isPending, isTrue);
      });
    });

    test('scrolling away from the bottom cancels the pending timer', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 2));
        dwell.updateAtBottom(false);
        async.elapse(const Duration(seconds: 5));

        expect(fired, 0);
        expect(dwell.isPending, isFalse);
      });
    });

    test('explicit cancel() (navigation away / backgrounding) stops a pending '
        'timer', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 2));
        dwell.cancel();
        async.elapse(const Duration(seconds: 5));

        expect(fired, 0);
        expect(dwell.isPending, isFalse);
      });
    });

    test('repeated "at bottom" calls do not restart or stack the timer', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 2));
        dwell.updateAtBottom(true); // still at bottom — must not restart
        async.elapse(const Duration(seconds: 3));

        expect(fired, 1,
            reason: 'should fire once at the original 5s mark, not be pushed '
                'back by the redundant updateAtBottom(true) call');
      });
    });
  });

  group('fires only once per visit to the bottom', () {
    test('further scroll events while parked at the bottom do not re-fire', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 5));
        expect(fired, 1);

        // Still at the bottom, still generating scroll events (an overscroll
        // wobble is enough). Without the fired latch this re-armed and fired
        // again every 5 seconds.
        for (var i = 0; i < 5; i++) {
          dwell.updateAtBottom(true);
          async.elapse(const Duration(seconds: 5));
        }

        expect(fired, 1);
      });
    });

    test('leaving the bottom and returning arms it again', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 5));
        expect(fired, 1);

        dwell.updateAtBottom(false); // scrolled back up
        dwell.updateAtBottom(true); // and back down again
        async.elapse(const Duration(seconds: 5));

        expect(fired, 2);
      });
    });

    test('reaching bottom, leaving, and reaching bottom again only ever runs '
        'one timer at a time', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 2));
        dwell.updateAtBottom(false);
        async.elapse(const Duration(milliseconds: 500));
        dwell.updateAtBottom(true); // restarts a fresh 5s wait
        async.elapse(const Duration(seconds: 5));

        expect(fired, 1);
      });
    });
  });

  group('"Immediately" (zero delay)', () {
    test('fires on the next event-loop turn, not synchronously', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(
          duration: Duration.zero,
          onComplete: () => fired++,
        );

        dwell.updateAtBottom(true);
        expect(fired, 0,
            reason: 'firing inline would re-enter setState from inside a '
                'scroll notification');

        async.elapse(Duration.zero);
        expect(fired, 1);
      });
    });

    test('still fires only once while parked at the bottom', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(
          duration: Duration.zero,
          onComplete: () => fired++,
        );

        // A fling generates a burst of scroll events at the bottom edge.
        for (var i = 0; i < 20; i++) {
          dwell.updateAtBottom(true);
          async.elapse(Duration.zero);
        }

        expect(fired, 1,
            reason: 'zero delay makes every scroll event a fire opportunity — '
                'the latch is what keeps it to one');
      });
    });

    test('can still be cancelled before the event loop turns', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(
          duration: Duration.zero,
          onComplete: () => fired++,
        );

        dwell.updateAtBottom(true);
        dwell.cancel();
        async.elapse(const Duration(seconds: 1));

        expect(fired, 0);
      });
    });
  });

  group('disabled', () {
    test('never fires however long you sit at the bottom', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(
          enabled: false,
          onComplete: () => fired++,
        );

        dwell.updateAtBottom(true);
        async.elapse(const Duration(minutes: 5));

        expect(fired, 0);
        expect(dwell.isPending, isFalse);
      });
    });
  });

  group('reconfiguring from Settings', () {
    test('turning it off abandons a wait already in progress', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 3));
        dwell.configure(enabled: false, duration: const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 10));

        expect(fired, 0);
      });
    });

    test('shortening the delay abandons the old wait rather than letting it '
        'fire first', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(
          duration: const Duration(seconds: 30),
          onComplete: () => fired++,
        );

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 20));
        dwell.configure(enabled: true, duration: const Duration(seconds: 5));

        // The abandoned 30s timer would have fired at t=30.
        async.elapse(const Duration(seconds: 12));
        expect(fired, 0, reason: 'nothing re-armed it yet');

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 5));
        expect(fired, 1, reason: 'and now it uses the new 5s delay');
      });
    });

    test('an unchanged configure() does not disturb a pending wait', () {
      fakeAsync((async) {
        var fired = 0;
        final dwell = BottomDwellTimer(onComplete: () => fired++);

        dwell.updateAtBottom(true);
        async.elapse(const Duration(seconds: 4));
        // Any settings save pings every listener, including saves that
        // changed something else entirely.
        dwell.configure(enabled: true, duration: const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 1));

        expect(fired, 1,
            reason: 'an unrelated settings change must not reset the clock');
      });
    });

    test('exposes its current configuration', () {
      final dwell = BottomDwellTimer(onComplete: () {});
      expect(dwell.enabled, isTrue);
      expect(dwell.duration, const Duration(seconds: 5));

      dwell.configure(enabled: false, duration: Duration.zero);
      expect(dwell.enabled, isFalse);
      expect(dwell.duration, Duration.zero);
    });
  });
}
