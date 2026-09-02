import 'package:flutter_test/flutter_test.dart';
import 'package:flash/reading/retirement_queue.dart';

void main() {
  late RetirementQueue q;
  setUp(() => q = RetirementQueue());

  group('RetirementQueue', () {
    test('starts empty', () {
      expect(q.isEmpty, isTrue);
      expect(q.length, 0);
    });

    test('enqueued ids are pending', () {
      q.enqueue([30, 20]);
      expect(q.isPending(30), isTrue);
      expect(q.isPending(20), isTrue);
      expect(q.length, 2);
    });

    test('an id that was never enqueued is not pending', () {
      q.enqueue([30]);
      expect(q.isPending(99), isFalse);
    });

    test('enqueueing the same id twice does not duplicate it', () {
      q.enqueue([30]);
      q.enqueue([30, 20]);
      expect(q.length, 2);
      expect(q.drain(), [30, 20]);
    });

    test('drain returns ids in the order they were enqueued', () {
      q.enqueue([50, 40]);
      q.enqueue([30]);
      expect(q.drain(), [50, 40, 30]);
    });

    test('drain empties the queue', () {
      q.enqueue([50, 40]);
      q.drain();
      expect(q.isEmpty, isTrue);
      expect(q.isPending(50), isFalse);
    });

    test('draining an empty queue returns an empty list', () {
      expect(q.drain(), isEmpty);
    });

    test('a released id is no longer pending and is never drained', () {
      q.enqueue([50, 40, 30]);
      q.release(40);
      expect(q.isPending(40), isFalse);
      expect(q.drain(), [50, 30]);
    });

    test('releasing an id that was never pending is a no-op', () {
      q.enqueue([50]);
      q.release(99);
      expect(q.drain(), [50]);
    });

    test('a released id can be enqueued again later', () {
      q.enqueue([50]);
      q.release(50);
      expect(q.isEmpty, isTrue);
      q.enqueue([50]);
      expect(q.drain(), [50]);
    });

    test('the queue refills after a drain', () {
      q.enqueue([50]);
      q.drain();
      q.enqueue([40, 30]);
      expect(q.drain(), [40, 30]);
    });
  });
}
