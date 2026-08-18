// BottomDwellTimer state-machine tests.
//
// Plain Dart, no Flutter/DB — this is the pure timer logic behind the
// "reached bottom of a feed, wait 5s, then mark all read" feature, kept
// isolated from FeedScreen precisely so it can be exercised with FakeAsync
// (this codebase's widget tests can't combine testWidgets() with real
// sqflite I/O, see feed_repository_test.dart).

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/utils/bottom_dwell_timer.dart';

void main() {
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

  test('explicit cancel() (navigation away / backgrounding) stops a pending timer', () {
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

  test('reaching bottom, leaving, and reaching bottom again only ever runs '
      'one timer at a time — not a stacked extra fire', () {
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

  test('repeated "at bottom" calls do not start a second timer', () {
    fakeAsync((async) {
      var fired = 0;
      final dwell = BottomDwellTimer(onComplete: () => fired++);

      dwell.updateAtBottom(true);
      async.elapse(const Duration(seconds: 2));
      dwell.updateAtBottom(true); // still at bottom — must not restart
      async.elapse(const Duration(seconds: 3));

      expect(fired, 1, reason: 'should fire once at the original 5s mark, '
          'not be pushed back by the redundant updateAtBottom(true) call');
    });
  });
}
