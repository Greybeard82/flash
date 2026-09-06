import 'package:flutter/foundation.dart';

/// Broadcast signal that the set of alert matches has changed.
///
/// Two listeners, for two different reasons. `AlertsScreen` is kept alive in
/// the app's [IndexedStack] and so runs `initState` once per launch — without
/// this it would show whatever was in the table when the app started, for the
/// rest of the session. `_AppShell` needs it for the count on the Alerts
/// destination, which is the number the old Alerts pill carried and would
/// otherwise have been lost when the pill was removed.
///
/// Fired from the UI isolate only, which is the same reach the pill had: it
/// refreshed when FeedScreen reloaded, so a background WorkManager fetch was
/// never live there either and showed up on the next foreground refresh. A
/// notifier cannot cross the isolate boundary — see [AlertNavigationIntent]'s
/// comment on why the notification payload has to round-trip through Android.
class AlertsChangedNotifier extends ChangeNotifier {
  static final AlertsChangedNotifier instance = AlertsChangedNotifier._();

  AlertsChangedNotifier._();

  void alertsChanged() => notifyListeners();
}
