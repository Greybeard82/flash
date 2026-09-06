import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../repositories/settings_repository.dart';
import '../utils/device_localizations.dart';
import 'alert_navigation_intent.dart';

const String kUnreadBadgeChannelId = 'flash_unread_count';
const String kUnreadBadgeChannelName = 'Unread count';

/// A fixed id, because there is only ever one of these and each update
/// replaces the last. Well clear of the keyword alerts, which run from 2000.
const int kUnreadBadgeNotificationId = 1;

/// Settings key. Absent means on — see [UnreadBadgeService].
const String kUnreadBadgeSettingKey = 'unread_badge_notification';

/// Tapping the badge just opens the app, so it carries a payload distinct from
/// the alerts one, which would otherwise drop the user on the Alerts tab.
const String kUnreadBadgePayload = 'unread';

/// The half of this that talks to the notification plugin.
///
/// Split out so the service can be tested. `flutter_local_notifications`
/// resolves its platform implementation from `Platform.isAndroid`, which is
/// false in a host-run suite — touching it there throws a
/// LateInitializationError before any of the logic worth testing runs.
abstract class UnreadBadgeSink {
  Future<void> post(int count);
  Future<void> cancel();
}

/// Puts the unread count on the launcher icon.
///
/// Two mechanisms, because Android has no single one.
///
/// Samsung, Xiaomi, Sony and friends accept a numeric badge directly through a
/// broadcast, which is what `app_badge_plus` sends — a real number drawn on
/// the icon, no notification involved. That is the good path and it needs
/// nothing from this class beyond the call.
///
/// **The Pixel Launcher does not support it at all.** There is no API in stock
/// Android for an app to draw a number on its own icon; `app_badge_plus`'s own
/// `NexusLauncherBadge` is an empty method whose only body is a log line
/// saying to use notification dots instead. The only thing that badges a stock
/// launcher is a notification, so on those launchers this posts one: silent,
/// low importance, carrying `setNumber(count)`. That gets a **dot** on the
/// icon and the **number** in the long-press menu — as close as the platform
/// allows, and not the same thing as the number Samsung draws.
///
/// The notification is only ever posted where the native badge is unavailable.
/// Anywhere the broadcast works, posting one as well would be a permanent
/// entry in the shade buying nothing.
class UnreadBadgeService {
  static final UnreadBadgeService instance = UnreadBadgeService._();

  UnreadBadgeService._({UnreadBadgeSink? sink})
      : _sink = sink ?? _NotificationBadgeSink();

  /// A fresh instance for tests.
  ///
  /// The singleton caches the launcher's answer and the last count it posted
  /// for the life of the process, which is right in the app and useless in a
  /// suite where each case has to start from nothing.
  @visibleForTesting
  factory UnreadBadgeService.debugCreate({UnreadBadgeSink? sink}) =>
      UnreadBadgeService._(sink: sink);

  final UnreadBadgeSink _sink;
  final _settings = SettingsRepository();

  /// Cached because `isSupported()` probes the launcher — it resolves the home
  /// activity and writes a zero badge — and the answer cannot change while the
  /// app is running short of the user swapping launchers.
  bool? _nativeSupported;

  /// The last count actually posted, so repeated updates with the same number
  /// don't re-post the notification. The badge is written from every read,
  /// every refresh and every scroll flush; without this the shade entry would
  /// be rebuilt dozens of times a minute.
  int? _postedCount;

  /// Whether the notification has been cancelled at least once this session.
  ///
  /// Separate from `_postedCount == null` because a notification outlives the
  /// process: on a cold start with everything already read, `_postedCount` is
  /// null but yesterday's badge is still sitting on the icon, and a `_clear()`
  /// that trusted the count alone would decide there was nothing to do.
  bool _cleared = false;

  Future<void> update(int count) async {
    final safe = count < 0 ? 0 : count;

    // Always. Where it works this is the whole feature, and it is cheap.
    await AppBadgePlus.updateBadge(safe);

    if (await _nativeBadgeWorks()) {
      // A launcher that draws the number itself needs no notification, and
      // one would sit in the shade forever for nothing.
      return;
    }

    if (!await _notificationBadgeEnabled()) {
      await _clear();
      return;
    }

    if (safe == 0) {
      await _clear();
      return;
    }
    if (_postedCount == safe) return;

    await _sink.post(safe);
    _postedCount = safe;
    _cleared = false;
  }

  Future<bool> _nativeBadgeWorks() async {
    if (_nativeSupported != null) return _nativeSupported!;
    try {
      _nativeSupported = await AppBadgePlus.isSupported();
    } catch (_) {
      // A launcher that throws is one that cannot badge.
      _nativeSupported = false;
    }
    return _nativeSupported!;
  }

  Future<bool> _notificationBadgeEnabled() async {
    final stored = await _settings.get(kUnreadBadgeSettingKey);
    // Absent means never set, which is the default-on case.
    return (stored ?? 'true') == 'true';
  }

  Future<void> _clear() async {
    if (_cleared) return;
    await _sink.cancel();
    _postedCount = null;
    _cleared = true;
  }

  /// Called when the setting is toggled, so turning it off removes the
  /// notification immediately rather than at the next count change.
  Future<void> onSettingChanged({required bool enabled}) async {
    if (enabled) {
      // Forget what was posted so the next count change re-posts it.
      _postedCount = null;
      return;
    }
    await _clear();
  }
}

class _NotificationBadgeSink implements UnreadBadgeSink {
  FlutterLocalNotificationsPlugin? _plugin;

  Future<FlutterLocalNotificationsPlugin> _pluginInstance() async {
    final existing = _plugin;
    if (existing != null) return existing;
    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // The shared handler, like every other initialize() in the app — this call
    // overwrites whatever was registered before it.
    await plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: onAlertNotificationResponse,
    );
    _plugin = plugin;
    return plugin;
  }

  @override
  Future<void> post(int count) async {
    final plugin = await _pluginInstance();
    await plugin.show(
      kUnreadBadgeNotificationId,
      // Terse, but still translated: the launcher only wants the number off
      // it, and the user still sees the line in the shade.
      deviceLocalizations()?.unreadCountNotification(count) ??
          '$count unread',
      null,
      NotificationDetails(
        android: AndroidNotificationDetails(
          kUnreadBadgeChannelId,
          kUnreadBadgeChannelName,
          channelDescription:
              'Carries the unread count to the launcher icon on launchers '
              'that cannot show a badge on their own.',
          // Low, silent and alert-once: it changes constantly, and a sound or
          // a heads-up for "you still have unread articles" would be
          // intolerable.
          importance: Importance.low,
          priority: Priority.low,
          silent: true,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          showWhen: false,
          // What the launcher actually reads.
          number: count,
          channelShowBadge: true,
          // Not ongoing. An un-dismissible notification for a count the user
          // may not care about right now is worse than one they can swipe
          // away; it comes back on the next count change either way.
          ongoing: false,
          autoCancel: false,
        ),
      ),
      payload: kUnreadBadgePayload,
    );
  }

  @override
  Future<void> cancel() async {
    final plugin = await _pluginInstance();
    await plugin.cancel(kUnreadBadgeNotificationId);
  }
}
