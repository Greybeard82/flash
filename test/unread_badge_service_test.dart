// The unread count on the launcher icon.
//
// Android has no single mechanism for this, so the service has two, and the
// interesting behaviour is entirely in choosing between them:
//
//   * The vendor broadcast, which some launchers honour and modern One UI
//     merely caches without painting anything.
//   * A notification, which is what actually badges both a Galaxy and a
//     Pixel — as a number on the former, a dot on the latter.
//
// The rule these pin: a notification is what draws the badge, on every
// launcher, so one is always posted. That was measured, not assumed — the
// first version skipped it wherever `isSupported()` said the vendor broadcast
// worked, which on a real Galaxy M51 meant no badge at all. See
// UnreadBadgeService's class comment.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/repositories/settings_repository.dart';
import 'package:flash/services/unread_badge_service.dart';

const _badgeChannel = MethodChannel('app_badge_plus');

/// Every call the service made to the native-badge plugin, in order.
late List<MethodCall> _badgeCalls;

/// Records what the service asked of the notification, in place of the real
/// plugin — which cannot run here at all, see [UnreadBadgeSink].
class _FakeSink implements UnreadBadgeSink {
  /// The capped number the launcher would draw.
  final posted = <int>[];

  /// The finished line the shade would show.
  final texts = <String>[];
  int cancels = 0;

  @override
  Future<void> post({required int badgeNumber, required String text}) async {
    posted.add(badgeNumber);
    texts.add(text);
  }

  @override
  Future<void> cancel() async => cancels++;
}

late _FakeSink _sink;

/// What the launcher claims about native badge support for this test.
late bool _nativeSupported;

void _installMocks() {
  _badgeCalls = [];
  _sink = _FakeSink();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_badgeChannel, (call) async {
    _badgeCalls.add(call);
    if (call.method == 'isSupported') return _nativeSupported;
    return null;
  });
}

/// The count handed to the native badge plugin.
int _badgeOf(List<MethodCall> calls) =>
    calls.firstWhere((c) => c.method == 'updateBadge').arguments['count']
        as int;

/// A fresh service, because it caches both the launcher answer and the last
/// count it posted for the life of the process.
UnreadBadgeService _service() =>
    UnreadBadgeService.debugCreate(sink: _sink);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.useForTesting();
    await AppDatabase.instance.database;
    _nativeSupported = false;
    _installMocks();
  });

  tearDown(() async => AppDatabase.instance.close());

  test('the broadcast is still sent, for launchers that do honour it',
      () async {
    _nativeSupported = true;
    await _service().update(7);

    final update = _badgeCalls.firstWhere((c) => c.method == 'updateBadge');
    expect(update.arguments, containsPair('count', 7));
  });

  test('a notification is posted even where the broadcast claims to work',
      () async {
    // The regression that shipped: this skipped the notification wherever
    // isSupported() was true, and a real Galaxy M51 then showed no badge at
    // all — it caches the broadcast and paints nothing.
    _nativeSupported = true;

    await _service().update(12);

    expect(_sink.posted, [12],
        reason: 'the notification is what draws the badge, on every launcher');
  });

  test('a notification is posted where the broadcast is unsupported',
      () async {
    _nativeSupported = false;

    await _service().update(12);

    expect(_sink.posted, [12]);
  });

  test('the same count twice posts once', () async {
    final service = _service();
    await service.update(5);
    await service.update(5);

    expect(_sink.posted, [5],
        reason: 'the badge is rewritten on every read, refresh and scroll '
            'flush — re-posting each time would rebuild the shade entry '
            'dozens of times a minute');
  });

  test('a changed count re-posts', () async {
    final service = _service();
    await service.update(5);
    await service.update(4);

    expect(_sink.posted, [5, 4]);
  });

  test('reaching zero cancels it rather than posting a zero', () async {
    final service = _service();
    await service.update(3);
    await service.update(0);

    expect(_sink.posted, [3]);
    expect(_sink.cancels, 1,
        reason: '"0 unread" is not a badge, it is clutter');
  });

  test('zero on a cold start still cancels a badge left by a past session',
      () async {
    // The notification outlives the process. A service that only cancelled
    // when it remembered posting would leave yesterday's badge on the icon.
    await _service().update(0);

    expect(_sink.cancels, 1,
        reason: 'nothing was posted this session, but something may still be '
            'showing from the last one');
  });

  test('turning the setting off posts nothing and clears what is there',
      () async {
    await SettingsRepository().set(kUnreadBadgeSettingKey, 'false');

    await _service().update(9);

    expect(_sink.posted, isEmpty);
    expect(_sink.cancels, 1);
  });

  test('the setting does not suppress the native badge', () async {
    // It exists to control the notification. A Samsung user turning it off
    // should not lose the real badge, which costs them nothing.
    await SettingsRepository().set(kUnreadBadgeSettingKey, 'false');

    await _service().update(9);

    final update = _badgeCalls.firstWhere((c) => c.method == 'updateBadge');
    expect(update.arguments, containsPair('count', 9));
  });

  group('the badge is capped so it stays readable', () {
    test('a count past the cap is sent as the cap', () async {
      _nativeSupported = true;
      await _service().update(238);

      expect(_badgeOf(_badgeCalls), kMaxBadgeCount,
          reason: 'past two digits the launcher shrinks the text to fit and '
              'the badge stops being readable at a glance');
    });

    test('a count below the cap is sent exactly', () async {
      _nativeSupported = true;
      await _service().update(42);

      expect(_badgeOf(_badgeCalls), 42);
    });

    test('the cap itself is sent unchanged', () async {
      _nativeSupported = true;
      await _service().update(kMaxBadgeCount);

      expect(_badgeOf(_badgeCalls), kMaxBadgeCount);
    });

    test('the notification carries the capped number but the true total in '
        'its text', () async {
      await _service().update(300);

      expect(_sink.posted, [kMaxBadgeCount],
          reason: 'the badge the launcher draws is capped');
      expect(_sink.texts.single, contains('300'),
          reason: 'the sentence in the shade has room for the real number, '
              'and "99 unread articles" when there are 300 is just wrong');
    });

    test('the shade text quotes the real total, not the capped badge', () {
      // The badge has to be capped because it is a two-digit circle. This is a
      // sentence, and it has room — capping it here would be a plain untruth.
      expect(unreadBadgeText(300), contains('300'));
      expect(unreadBadgeText(300), isNot(contains('99')));
    });

    test('the shade text is singular for one', () {
      expect(unreadBadgeText(1), '1 unread article');
    });

    test('two different counts above the cap post only once', () async {
      final service = _service();
      await service.update(200);
      await service.update(300);

      expect(_sink.posted, [kMaxBadgeCount],
          reason: 'the badge reads the same either way, so rewriting the '
              'shade entry changes nothing the user can see');
    });

    test('crossing the cap downwards does re-post', () async {
      final service = _service();
      await service.update(200);
      await service.update(50);

      expect(_sink.posted, [kMaxBadgeCount, 50]);
    });
  });

  test('a negative count is floored at zero', () async {
    await _service().update(-3);

    final update = _badgeCalls.firstWhere((c) => c.method == 'updateBadge');
    expect(update.arguments, containsPair('count', 0));
    expect(_sink.posted, isEmpty);
  });
}
