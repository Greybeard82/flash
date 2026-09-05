import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app.dart';
import 'db/database.dart';
import 'repositories/settings_repository.dart';
import 'services/alert_navigation_intent.dart';
import 'services/refresh_service.dart';
import 'utils/form_factor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Detect TV / form factor before the first frame
  await FormFactor.init();

  // Init database
  await AppDatabase.instance.database;

  // Request notification permission (Android 13+), and register the tap
  // handler in the same call -- initialize() is the only place it can be
  // supplied, so a second initialize() later would not add one. It would,
  // however, take the existing one *away*: initialize overwrites the stored
  // callback unconditionally. Every other caller therefore passes this same
  // shared handler -- see onAlertNotificationResponse.
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(
    const InitializationSettings(android: androidInit),
    onDidReceiveNotificationResponse: onAlertNotificationResponse,
  );
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();

  // A tap that launched the app from cold never reaches the callback above:
  // the process did not exist when it happened, and by the time initialize()
  // runs Android has already handed the intent to the Activity. The launch
  // details are the only record of it, so they are checked here as well --
  // AlertNavigationIntent latches, so setting the flag before any widget is
  // built is fine.
  final launch = await plugin.getNotificationAppLaunchDetails();
  if (launch?.didNotificationLaunchApp ?? false) {
    handleAlertNotificationPayload(launch!.notificationResponse?.payload);
  }

  // Register background refresh
  final settingsRepo = SettingsRepository();
  final refreshService = RefreshService(settingsRepo);
  await refreshService.init();

  runApp(const FlashApp());
}

