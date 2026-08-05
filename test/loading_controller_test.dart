// LoadingController tests.
//
// Written independently of the implementation. The controller is a global,
// reference-counted busy flag: ANY async operation anywhere in the app wraps
// itself in it, and a single indicator in the app shell listens.
//
// Covered behaviours:
//  1. Idle by default
//  2. begin/end reference counting — concurrent operations don't cancel each other
//  3. Unbalanced end() clamps at zero instead of going negative
//  4. run() ends the operation even when the action throws, and rethrows
//  5. Listeners are notified on busy transitions
//  6. The current label reflects the most recent in-flight operation

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/loading_controller.dart';

void main() {
  late LoadingController c;

  setUp(() {
    c = LoadingController.instance;
    c.reset();
  });

  group('idle state', () {
    test('starts idle', () {
      expect(c.isBusy, isFalse);
      expect(c.activeCount, 0);
      expect(c.label, isNull);
    });
  });

  group('reference counting', () {
    test('begin makes it busy, matching end makes it idle', () {
      c.begin();
      expect(c.isBusy, isTrue);
      expect(c.activeCount, 1);
      c.end();
      expect(c.isBusy, isFalse);
      expect(c.activeCount, 0);
    });

    test('two concurrent operations require two ends', () {
      c.begin();
      c.begin();
      expect(c.activeCount, 2);
      c.end();
      expect(c.isBusy, isTrue,
          reason: 'one operation is still in flight');
      c.end();
      expect(c.isBusy, isFalse);
    });

    test('unbalanced end clamps at zero', () {
      c.end();
      c.end();
      expect(c.activeCount, 0);
      expect(c.isBusy, isFalse);
      c.begin();
      expect(c.activeCount, 1,
          reason: 'no negative debt carried over');
    });
  });

  group('label', () {
    test('reports the most recent labelled operation', () {
      c.begin('Refreshing feeds');
      expect(c.label, 'Refreshing feeds');
      c.begin('Summarising');
      expect(c.label, 'Summarising');
    });

    test('clears when everything finishes', () {
      c.begin('Refreshing feeds');
      c.end();
      expect(c.label, isNull);
    });
  });

  group('run()', () {
    test('is busy during the action and idle after', () async {
      var busyDuringAction = false;
      await c.run(() async {
        busyDuringAction = c.isBusy;
        return null;
      });
      expect(busyDuringAction, isTrue);
      expect(c.isBusy, isFalse);
    });

    test('returns the action result', () async {
      final result = await c.run<int>(() async => 42);
      expect(result, 42);
    });

    test('ends and rethrows when the action throws', () async {
      await expectLater(
        c.run(() async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      expect(c.isBusy, isFalse, reason: 'must not leak a stuck spinner');
      expect(c.activeCount, 0);
    });

    test('nested runs stay busy until the outermost completes', () async {
      await c.run(() async {
        await c.run(() async => null);
        expect(c.isBusy, isTrue,
            reason: 'inner finished but outer is still running');
      });
      expect(c.isBusy, isFalse);
    });
  });

  group('notifications', () {
    test('notifies on the idle→busy and busy→idle transitions', () {
      var notifications = 0;
      void listener() => notifications++;
      c.addListener(listener);

      c.begin();
      c.end();

      expect(notifications, greaterThanOrEqualTo(2));
      c.removeListener(listener);
    });

    test('does not notify on a no-op end while already idle', () {
      var notifications = 0;
      void listener() => notifications++;
      c.addListener(listener);

      c.end();

      expect(notifications, 0);
      c.removeListener(listener);
    });
  });
}
