import 'package:flutter/material.dart';
import 'app.dart';
import 'db/database.dart';
import 'repositories/settings_repository.dart';
import 'services/refresh_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init database
  await AppDatabase.instance.database;

  // Register background refresh
  final settingsRepo = SettingsRepository();
  final refreshService = RefreshService(settingsRepo);
  await refreshService.init();

  runApp(const FlashApp());
}
