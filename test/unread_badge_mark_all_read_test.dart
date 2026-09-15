// 1.4 — mark all read. One symptom, three mechanisms, three tests.
//
// David saw one thing on the Samsung: the articles cleared and the unread
// notification survived. Three separate defects produce exactly that, and
// fixing any one of them alone would have left the other two shipping. The
// groups below are deliberately independent, so a regression in one does not
// hide behind another passing.
//
// Note what is NOT here: nothing asserts against `_cleared`'s early return.
// That guard was the original suspicion and it is sound in both directions --
// `_cleared = true` is only reached after a cancel that returned, and a cancel
// that throws leaves it false so the next call retries. Testing it would have
// been testing the wrong thing.


import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/services/unread_badge_service.dart';
import 'package:flash/services/unread_widget_service.dart';

const _badgeChannel = MethodChannel('app_badge_plus');
const _widgetChannel = MethodChannel('home_widget');

/// Makes the launcher badge plugin throw, standing in for the Samsung
/// behaviour that stranded the notification.
late bool _badgeThrows;

/// Records what reached the notification layer, in order.
class _RecordingSink implements UnreadBadgeSink {
  final List<String> calls = [];
  Object? postThrows;
  Object? cancelThrows;

  @override
  Future<void> post({required int badgeNumber, required String text}) async {
    calls.add('post:$badgeNumber');
    if (postThrows != null) throw postThrows!;
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    if (cancelThrows != null) throw cancelThrows!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingSink sink;
  late UnreadBadgeService service;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.useForTesting();
    await AppDatabase.instance.database;

    _badgeThrows = false;
    UnreadWidgetService.instance.debugReset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_widgetChannel, (call) async => true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_badgeChannel, (call) async {
      if (_badgeThrows) throw PlatformException(code: 'boom');
      if (call.method == 'isSupported') return false;
      return null;
    });

    sink = _RecordingSink();
    service = UnreadBadgeService.debugCreate(sink: sink);
  });

  tearDown(() async => AppDatabase.instance.close());

  // ---------------------------------------------------------------- 1 of 3
  group('the suppression is a one-shot and cannot leak', () {
    test('it withholds exactly one post, and the next one goes through', () {
      // The whole specification in one case. Arm, then two updates: the first
      // is silent, the second is not.
      return service.update(0).then((_) {
        sink.calls.clear();
        service.suppressNextNotification();
        return service.update(12).then((_) {
          expect(sink.calls, isEmpty, reason: 'the armed update must be quiet');
          return service.update(13).then((_) {
            expect(sink.calls, ['post:13'],
                reason: 'the NEXT update is a normal one. If this is empty the '
                    'flag became a mode and notifications are off for the '
                    'rest of the session.');
          });
        });
      });
    });

    test('it is consumed even when the update returns early', () async {
      // **The anti-leak property, and the reason the flag is read at the top
      // of update() rather than next to the post.** An update that dismisses
      // takes an early return and never reaches the post at all; if that path
      // did not consume the flag it would still be armed afterwards and would
      // silently eat a later, legitimate notification.
      service.suppressNextNotification();
      await service.update(0); // early-returns at the `safe == 0` branch
      sink.calls.clear();

      await service.update(7);
      expect(sink.calls, ['post:7'],
          reason: 'the flag was eaten by the count-0 update, so this one is '
              'an ordinary post');
    });

    test('arming twice still only withholds one', () async {
      await service.update(0);
      sink.calls.clear();
      service.suppressNextNotification();
      service.suppressNextNotification();

      await service.update(4);
      expect(sink.calls, isEmpty);
      await service.update(5);
      expect(sink.calls, ['post:5'], reason: 'it is a bool, not a counter');
    });

    test('an unarmed run is completely unaffected', () async {
      await service.update(9);
      expect(sink.calls, ['post:9'],
          reason: 'the default path must not have acquired a condition');
    });

    test('suppression withholds the post but never the dismiss', () async {
      await service.update(9);
      sink.calls.clear();

      service.suppressNextNotification();
      await service.update(0);
      expect(sink.calls, ['cancel'],
          reason: 'mark-all-read must still clear the shade. Suppression is '
              'about not interrupting, not about leaving a stale count up.');
    });
  });

  // ---------------------------------------------------------------- 2 of 3
  group('the race: updates are serialised, not interleaved', () {
    test('overlapping calls land in arrival order', () async {
      // Fired together without awaiting, the way the app used to. The dismiss
      // is issued first, so it must be applied first, whatever the internal
      // awaits do.
      final a = service.update(5);
      final b = service.update(0);
      await Future.wait([a, b]);

      expect(sink.calls, ['post:5', 'cancel'],
          reason: 'if these arrive out of order the notification survives a '
              'clear, which is the reported symptom');
    });

    test('many overlapping calls still finish in order', () async {
      final futures = [
        service.update(1),
        service.update(2),
        service.update(3),
        service.update(0),
      ];
      await Future.wait(futures);

      expect(sink.calls, ['post:1', 'post:2', 'post:3', 'cancel']);
      expect(sink.calls.last, 'cancel',
          reason: 'the last caller wins, deterministically');
    });

    test('one failing update does not poison the queue', () async {
      sink.postThrows = StateError('boom');
      await expectLater(service.update(3), throwsA(isA<StateError>()));

      sink.postThrows = null;
      await service.update(4);
      expect(sink.calls, contains('post:4'),
          reason: 'a serialising queue that latches its own error would take '
              'the badge down for the session');
    });
  });

  // ---------------------------------------------------------------- 3 of 3
  group('the Samsung path: a badge failure cannot stop the clear', () {
    // This is where David actually saw it. AppBadgePlus.updateBadge and the
    // widget update are awaited BEFORE the `safe == 0` branch, so a throw from
    // either used to skip `_clear()` — silently, because nothing awaited the
    // future to catch it.
    //
    // Both are now wrapped. The test drives the real code path rather than a
    // stand-in: it cannot inject a throw into AppBadgePlus from here, so it
    // asserts the property that matters — that a count of zero always reaches
    // the sink — in an environment where the platform channels are absent and
    // therefore already failing.

    test('count 0 still reaches cancel when the badge plugin throws',
        () async {
      // The actual regression test. Before the fix this assertion failed:
      // the throw propagated out of update() and _clear() never ran.
      _badgeThrows = true;
      await service.update(0);
      expect(sink.calls, ['cancel'],
          reason: 'a launcher that rejects a badge broadcast must not be able '
              'to strand a notification');
    });

    test('a post still happens when the badge plugin throws', () async {
      _badgeThrows = true;
      await service.update(6);
      expect(sink.calls, ['post:6'],
          reason: 'the badge is the least important of the three signals');
    });

    test('and the failure does not surface to the caller', () async {
      // Callers treat this as fire-and-forget in several places. If a badge
      // failure threw out of update() it would become an unhandled async
      // error, which is how this stayed invisible for so long.
      _badgeThrows = true;
      await expectLater(service.update(3), completes);
    });

    test('the sequence survives end to end', () async {
      // The whole mark-all-read shape, in order, with the platform layer
      // unavailable throughout.
      await service.update(40); // articles present
      await service.update(0); // mark all read
      service.suppressNextNotification();
      await service.update(12); // the refresh it started

      expect(sink.calls, ['post:40', 'cancel'],
          reason: 'post, dismiss, and then silence — the refresh finds twelve '
              'articles and does not interrupt about them');
    });
  });
}
