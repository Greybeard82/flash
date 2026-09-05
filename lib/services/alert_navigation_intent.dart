import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Round-tripped through Android and handed back on tap. The background
/// isolate cannot reach the UI isolate's notifiers, so the request to open the
/// Alerts tab has to travel out through the notification and back in — see
/// [AlertNavigationIntent].
const String kAlertNotificationPayload = 'alerts';

/// The one notification-tap handler in the app.
///
/// It lives here, rather than privately in `main()`, because
/// `FlutterLocalNotificationsPlugin()` is a factory singleton whose
/// `initialize` **unconditionally overwrites** the stored response callback.
/// `RefreshService` initializes the plugin again before posting an alert, and
/// that path also runs on the UI isolate (pull-to-refresh, the refresh FAB,
/// the boot fetch) — so an `initialize` there without this handler silently
/// de-registered the one `main()` had installed, and from the first alert
/// onwards tapping a notification on a running app did nothing at all. Every
/// caller of `initialize` now passes this same function.
@pragma('vm:entry-point')
void onAlertNotificationResponse(NotificationResponse response) =>
    handleAlertNotificationPayload(response.payload);

/// The payload is how a keyword alert asks for the Alerts tab. It has to
/// travel through the notification rather than through a notifier because the
/// notification may have been posted from the background WorkManager isolate,
/// where every singleton is a separate instance that the UI isolate cannot
/// see.
void handleAlertNotificationPayload(String? payload) {
  if (payload == kAlertNotificationPayload) {
    AlertNavigationIntent.instance.requestAlertsTab();
  }
}

/// Broadcast signal that the user asked to be taken to the Alerts tab —
/// today, by tapping a keyword-alert notification.
///
/// Modelled on [ReadStateNotifier], with one difference that matters: this one
/// **latches**. A tap on a notification while the app is dead starts the
/// process, and the launch details are read in `main()` long before
/// `_AppShell` — never mind `FeedScreen` — has been built, so a plain
/// `notifyListeners()` would fire into an empty listener list and the app
/// would open on the ordinary feed as if nothing had been tapped. The request
/// is therefore held in [_pending] until something actually consumes it, which
/// makes the cold-start tap and the tap on a running app the same code path.
///
/// The two halves are deliberately split. `_AppShell` listens and moves the
/// nav bar to the Flash destination; `FeedScreen` calls [consumePending] to
/// select the Alerts pill. Only the second clears the flag, so the shell
/// switching tabs cannot swallow the request before the screen that acts on
/// it has been mounted.
///
/// **The background isolate can never signal through this.** WorkManager runs
/// `callbackDispatcher` in its own isolate, where `main()` never ran and every
/// singleton — this one included — is a distinct instance with no way to reach
/// the objects the UI is listening to. Setting the flag there would set it on
/// a copy nothing reads. That is why the intent round-trips through the
/// notification itself: the payload survives the isolate boundary because it
/// goes out through Android and comes back into the UI isolate on the tap.
class AlertNavigationIntent extends ChangeNotifier {
  static final AlertNavigationIntent instance = AlertNavigationIntent._();

  AlertNavigationIntent._();

  bool _pending = false;

  /// Whether a request is still waiting to be acted on. Reading this does not
  /// clear it — see [consumePending].
  bool get isPending => _pending;

  /// Call when a keyword-alert notification is tapped, from either the warm
  /// `onDidReceiveNotificationResponse` callback or the cold-start
  /// `getNotificationAppLaunchDetails()` check.
  void requestAlertsTab() {
    _pending = true;
    notifyListeners();
  }

  /// Takes the pending request, returning true exactly once per
  /// [requestAlertsTab]. Clearing on read is what stops the Alerts tab
  /// re-selecting itself on every later rebuild, which would otherwise trap
  /// the user there for the rest of the session.
  bool consumePending() {
    if (!_pending) return false;
    _pending = false;
    return true;
  }
}
