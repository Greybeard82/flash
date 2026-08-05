// ResumeRefreshPolicy tests.
//
// Written independently of the implementation. Decides whether returning to
// the app from the background should trigger a NETWORK fetch. A DB reload
// always happens on resume; this policy only gates the network call, so that
// popping back from the browser after five seconds doesn't re-fetch 20 feeds.
//
// Covered behaviours:
//  1. Never fetch if the app was never actually backgrounded
//  2. Never fetch after a brief excursion (reader / browser / share sheet)
//  3. Fetch after a real absence
//  4. Never fetch if a fetch already ran recently
//  5. Thresholds are configurable and boundaries are inclusive-safe

import 'package:flutter_test/flutter_test.dart';
import 'package:flash/utils/resume_refresh_policy.dart';

void main() {
  final now = DateTime(2026, 8, 5, 12, 0, 0);
  const policy = ResumeRefreshPolicy(
    minBackgroundDuration: Duration(seconds: 30),
    minFetchInterval: Duration(minutes: 5),
  );

  group('defaults', () {
    test('ship with 30s background and 5min fetch thresholds', () {
      const p = ResumeRefreshPolicy();
      expect(p.minBackgroundDuration, const Duration(seconds: 30));
      expect(p.minFetchInterval, const Duration(minutes: 5));
    });
  });

  group('never backgrounded', () {
    test('no pausedAt means no fetch', () {
      expect(
        policy.shouldFetch(
          pausedAt: null,
          resumedAt: now,
          lastFetchAt: null,
        ),
        isFalse,
      );
    });
  });

  group('brief excursions', () {
    test('5 seconds away does not fetch', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.subtract(const Duration(seconds: 5)),
          resumedAt: now,
          lastFetchAt: null,
        ),
        isFalse,
      );
    });

    test('29 seconds away does not fetch', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.subtract(const Duration(seconds: 29)),
          resumedAt: now,
          lastFetchAt: null,
        ),
        isFalse,
      );
    });

    test('exactly 30 seconds away does fetch', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.subtract(const Duration(seconds: 30)),
          resumedAt: now,
          lastFetchAt: null,
        ),
        isTrue,
      );
    });
  });

  group('real absence', () {
    test('ten minutes away with no prior fetch does fetch', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.subtract(const Duration(minutes: 10)),
          resumedAt: now,
          lastFetchAt: null,
        ),
        isTrue,
      );
    });

    test('an hour away does fetch', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.subtract(const Duration(hours: 1)),
          resumedAt: now,
          lastFetchAt: now.subtract(const Duration(hours: 1)),
        ),
        isTrue,
      );
    });
  });

  group('recent-fetch suppression', () {
    test('a fetch two minutes ago suppresses another', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.subtract(const Duration(minutes: 10)),
          resumedAt: now,
          lastFetchAt: now.subtract(const Duration(minutes: 2)),
        ),
        isFalse,
      );
    });

    test('a fetch six minutes ago allows another', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.subtract(const Duration(minutes: 10)),
          resumedAt: now,
          lastFetchAt: now.subtract(const Duration(minutes: 6)),
        ),
        isTrue,
      );
    });

    test('background gate is checked even when the last fetch is ancient', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.subtract(const Duration(seconds: 3)),
          resumedAt: now,
          lastFetchAt: now.subtract(const Duration(days: 1)),
        ),
        isFalse,
        reason: 'a 3-second excursion is never a resume-refresh',
      );
    });
  });

  group('clock weirdness', () {
    test('a pausedAt in the future does not fetch', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.add(const Duration(minutes: 5)),
          resumedAt: now,
          lastFetchAt: null,
        ),
        isFalse,
      );
    });

    test('a lastFetchAt in the future does not fetch', () {
      expect(
        policy.shouldFetch(
          pausedAt: now.subtract(const Duration(hours: 1)),
          resumedAt: now,
          lastFetchAt: now.add(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });
  });

  group('custom thresholds', () {
    test('an aggressive policy fetches after five seconds', () {
      const eager = ResumeRefreshPolicy(
        minBackgroundDuration: Duration(seconds: 5),
        minFetchInterval: Duration(seconds: 10),
      );
      expect(
        eager.shouldFetch(
          pausedAt: now.subtract(const Duration(seconds: 6)),
          resumedAt: now,
          lastFetchAt: now.subtract(const Duration(seconds: 30)),
        ),
        isTrue,
      );
    });
  });
}
