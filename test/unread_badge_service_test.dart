// The unread count on the launcher icon.
//
// Android has no single mechanism for this, so the service has two, and the
// interesting behaviour is entirely in choosing between them:
//
//   * Samsung, Xiaomi, Sony and friends accept a numeric badge over a
//     broadcast. `app_badge_plus` sends it, a real number lands on the icon,
//     and nothing else is needed.
//   * The Pixel Launcher accepts nothing. `app_badge_plus`'s own
//     `NexusLauncherBadge` is an empty method — there is no stock-Android API
//     for drawing a number on your own icon. The only thing that badges it is
//     a notification, so on those launchers one is posted.
//
// The rule these pin: the notification is posted **only** where the native
// badge does not work. Posting it anyway on a Samsung would be a permanent
// entry in the shade buying nothing, and that is the failure worth guarding.

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
  final posted = <int>[];
  int cancels = 0;

  @override
  Future<void> post(int count) async => posted.add(count);

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

  test('the native badge is always written, whatever the launcher', () async {
    _nativeSupported = true;
    await _service().update(7);

    final update = _badgeCalls.firstWhere((c) => c.method == 'updateBadge');
    expect(update.arguments, containsPair('count', 7));
  });

  test('a launcher that draws its own badge gets no notification', () async {
    _nativeSupported = true;

    await _service().update(12);

    expect(_sink.posted, isEmpty,
        reason: 'a Samsung already shows the number on the icon; a second '
            'mechanism would just be a permanent line in the shade');
  });

  test('a launcher that cannot badge gets one carrying the count', () async {
    _nativeSupported = false;

    await _service().update(12);

    expect(_sink.posted, [12],
        reason: 'this is the only thing that badges a Pixel, and the number '
            'it carries is what the launcher reads');
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

  test('a negative count is floored at zero', () async {
    await _service().update(-3);

    final update = _badgeCalls.firstWhere((c) => c.method == 'updateBadge');
    expect(update.arguments, containsPair('count', 0));
    expect(_sink.posted, isEmpty);
  });
}
