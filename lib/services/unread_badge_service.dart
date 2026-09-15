import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../repositories/settings_repository.dart';
import '../utils/device_localizations.dart';
import 'unread_widget_service.dart';
import 'alert_navigation_intent.dart';
import 'notification_group.dart';

const String kUnreadBadgeChannelId = 'flash_unread_count';
const String kUnreadBadgeChannelName = 'Unread count';

/// A fixed id, because there is only ever one of these and each update
/// replaces the last. Well clear of the keyword alerts, which run from 2000.
const int kUnreadBadgeNotificationId = 1;

/// The largest number the badge ever carries.
///
/// The badge is a small circle on top of an icon; past two digits the text is
/// shrunk to fit and stops being readable at a glance, which is the only thing
/// a badge is for. Beyond this the exact number has stopped being information
/// anyway — "you have a lot" is the whole message.
///
/// Note this caps the *number sent to the launcher*, so a launcher draws "99"
/// for any count at or above it. Whether it renders that as "99+" is the
/// launcher's own decision: the Android API takes an int, there is no way to
/// hand it the plus sign.
const int kMaxBadgeCount = 99;

/// Settings key. Absent means on — see [UnreadBadgeService].
const String kUnreadBadgeSettingKey = 'unread_badge_notification';

/// Tapping the badge just opens the app, so it carries a payload distinct from
/// the alerts one, which would otherwise drop the user on the Alerts tab.
const String kUnreadBadgePayload = 'unread';

/// The line the notification shows in the shade.
///
/// Takes the **true** unread total, not the capped badge number: the badge is
/// a two-digit circle and has to be capped, but this is a sentence with room
/// for the real figure, and "99 unread articles" when there are 300 is simply
/// false. A pure function so it can be tested — the sink around it cannot run
/// off-device.
String unreadBadgeText(int trueCount) =>
    deviceLocalizations()?.unreadCountNotification(trueCount) ??
    '$trueCount unread';

/// The half of this that talks to the notification plugin.
///
/// Split out so the service can be tested. `flutter_local_notifications`
/// resolves its platform implementation from `Platform.isAndroid`, which is
/// false in a host-run suite — touching it there throws a
/// LateInitializationError before any of the logic worth testing runs.
abstract class UnreadBadgeSink {
  /// Deliberately dumb: it is handed the finished [text] and the finished
  /// [badgeNumber] and does nothing but show them.
  ///
  /// Which number belongs where is the interesting decision — the badge is
  /// capped, the sentence is not — and it lives in [UnreadBadgeService] rather
  /// than here so it can be tested. Nothing inside a sink can be: the
  /// notification plugin does not run off-device, so any logic that ends up
  /// here is logic no test will ever execute.
  Future<void> post({required int badgeNumber, required String text});
  Future<void> cancel();
}

/// Puts the unread count on the launcher icon.
///
/// **A notification is what draws the badge. On every launcher.** That is the
/// one thing to know here, and it was measured rather than assumed.
///
/// The obvious design is the wrong one: `app_badge_plus` sends a vendor
/// broadcast that Samsung, Xiaomi and Sony have historically drawn a number
/// from, so it seems right to send that where it works and fall back to a
/// notification only on stock Android. It was built that way, and on a Galaxy
/// M51 running One UI the result was **no badge at all** — the broadcast is
/// received and cached (logcat shows `BadgeCache: add to cache ... count: 99`)
/// and then nothing is painted. Adding a notification, changing nothing else,
/// made the number appear on the icon immediately. Modern One UI badges from
/// the notification like everything else; the broadcast is a leftover that
/// still logs.
///
/// So the notification is posted everywhere, and what each launcher makes of
/// it differs:
///   * One UI draws the number — the [kMaxBadgeCount] cap is what it renders.
///   * The Pixel Launcher draws a plain dot and puts the number in the
///     long-press menu. It has no way to draw a number on an icon at all:
///     `app_badge_plus`'s own `NexusLauncherBadge` is an empty method whose
///     body is a log line saying to use notification dots instead.
///
/// The broadcast is still sent, because on launchers that genuinely honour it
/// it costs one call and needs no notification. It is just no longer trusted
/// to be sufficient anywhere.
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

  /// Skip the next post, once.
  ///
  /// **A one-shot, deliberately not a mode.** Mark-all-read dismisses the
  /// notification and then immediately runs a refresh, and that refresh
  /// legitimately finds new articles -- so without this the notification
  /// reappears seconds later and mark-all-read looks like it failed. The
  /// reader just asked for an empty deck; a notification is an interruption,
  /// and they have effectively declined one.
  ///
  /// Nothing else is hidden. The in-app count, the launcher badge, the widget
  /// and the list all stay truthful. Only the interruption is withheld, and
  /// only for the single refresh that mark-all-read itself started.
  ///
  /// **The failure mode this is shaped against is a flag that leaks** and
  /// silently kills notifications for the rest of the session. So it is
  /// consumed at the very top of [update], before any early return, which
  /// makes "survives one call" structurally impossible rather than a property
  /// of getting every branch right. There is no setter that turns it off,
  /// because there is no state to turn off.
  bool _suppressNextPost = false;

  /// Serialises [update] against itself.
  ///
  /// [update] has several `await`s before it touches `_postedCount` or
  /// `_cleared`, and most callers do not await it. Two overlapping calls could
  /// therefore interleave on that shared state and the last writer was
  /// whichever happened to finish first -- which is how a dismiss and a
  /// re-post could land in either order. Calls now run one at a time, in
  /// arrival order.
  Future<void> _queue = Future<void>.value();

  /// Withhold the next notification post, once.
  ///
  /// Call immediately before the refresh whose result should not interrupt.
  /// The very next [update] consumes it, whatever that update decides to do.
  void suppressNextNotification() {
    _suppressNextPost = true;
  }

  Future<void> update(int count) {
    final next = _queue.then((_) => _update(count));
    // Detached so one failure cannot poison every later update; the returned
    // future still carries the error to anyone awaiting this call.
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _update(int count) async {
    final safe = count < 0 ? 0 : count;
    final badge = safe > kMaxBadgeCount ? kMaxBadgeCount : safe;

    // Consumed here, before anything that can return early. Whatever else
    // this call does, the flag does not survive it.
    final suppressPost = _suppressNextPost;
    _suppressNextPost = false;

    // The home screen widget rides along here rather than at this service's
    // callers. Everything that changes the unread total already calls this,
    // so hooking in at the one place means the widget cannot be updated in
    // eight spots and forgotten in a ninth — and it shows the same number the
    // badge does, written in the same breath. Uncapped: the widget is a
    // TextView with room to render "99+" itself.
    // Already safe: UnreadWidgetService.update swallows its own failures,
    // for exactly the reason spelled out below. Left unwrapped so there is one
    // obvious place that catch lives rather than two that disagree.
    await UnreadWidgetService.instance.update(safe);

    // Sent everywhere and trusted nowhere — see the class comment. One call,
    // no notification needed, and it is the whole feature on the launchers
    // that do honour it.
    // **This one was the real gap, and it is where David saw the bug.**
    // It sat as a bare await in front of the `safe == 0` branch, so a throw
    // here skipped `_clear()` entirely and the notification was stranded --
    // silently, because no caller awaited this future to catch anything. A
    // Samsung launcher is exactly the kind to answer a badge broadcast oddly.
    // The badge is the least important of the three signals and must not be
    // able to take the other two down with it.
    try {
      await AppBadgePlus.updateBadge(badge);
    } catch (error, stack) {
      debugPrint('UnreadBadgeService: launcher badge failed: $error');
      debugPrintStack(stackTrace: stack);
    }

    if (!await _notificationBadgeEnabled()) {
      await _clear();
      return;
    }

    if (safe == 0) {
      await _clear();
      return;
    }
    // Compared on the capped value, not the true count: with 200 unread, the
    // badge reads the same at 200 as at 300, so re-posting on every change
    // above the cap would rewrite the shade entry for a number nobody can
    // see change.
    if (_postedCount == badge) return;

    // After the clear branches, so mark-all-read still dismisses; before the
    // post, so the refresh it kicked off cannot put one back. `_postedCount`
    // is deliberately left alone: the next genuine count change posts
    // normally, which is what "for that refresh only" means.
    if (suppressPost) return;

    await _sink.post(badgeNumber: badge, text: unreadBadgeText(safe));
    _postedCount = badge;
    _cleared = false;
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
    const androidInit = AndroidInitializationSettings('ic_stat_flash');
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
  Future<void> post({required int badgeNumber, required String text}) async {
    final plugin = await _pluginInstance();
    await plugin.show(
      kUnreadBadgeNotificationId,
      text,
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
// Without this the shade had a grouped keyword alert next to an
          // ungrouped count and could stack neither.
          groupKey: kFlashNotificationGroupKey,
          color: kFlashNotificationAccent,
          // What the launcher actually reads.
          number: badgeNumber,
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
