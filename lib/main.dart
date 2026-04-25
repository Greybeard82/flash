import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'app.dart';
import 'db/database.dart';
import 'repositories/settings_repository.dart';
import 'services/refresh_service.dart';
import 'utils/form_factor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Detect TV / form factor before the first frame
  await FormFactor.init();

  // Init database
  await AppDatabase.instance.database;

  // Request notification permission (Android 13+)
  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));
  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.requestNotificationsPermission();

  // Register background refresh
  final settingsRepo = SettingsRepository();
  final refreshService = RefreshService(settingsRepo);
  await refreshService.init();

  runApp(const FlashApp());
}
