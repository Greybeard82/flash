// Theme persistence tests.
//
// Covers the DB half of the System/Light/Dark bug fix: the persisted
// 'theme' setting must always be the raw mode selector string
// ('system'/'light'/'dark'), never a resolved brightness — a relaunch must
// re-derive System from the live OS state, and replay an explicit Light/
// Dark choice exactly as stored, never a stale cached brightness.
//
// Deliberately plain test() against SettingsRepository, not testWidgets():
// this codebase's DB tests never combine testWidgets() with real sqflite
// I/O (the FFI Future can't resolve inside flutter_test's FakeAsync zone —
// see feed_repository_test.dart for the established pattern). Combined
// with theme_mode_test.dart (which proves a given mode string resolves to
// the right rendered ThemeMode, live OS state and all), these two together
// cover the full persist → relaunch → resolve pipeline.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/app.dart';
import 'package:flash/db/database.dart';
import 'package:flash/repositories/settings_repository.dart';

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
}

void main() {
  setUp(_setUp);
  tearDown(() => AppDatabase.instance.close());

  group('what gets stored', () {
    test('selecting Dark persists the literal string "dark", not a brightness',
        () async {
      final repo = SettingsRepository();
      await repo.set('theme', 'dark');

      final stored = await repo.get('theme');
      expect(stored, 'dark');
    });

    test('selecting System persists the literal string "system"', () async {
      final repo = SettingsRepository();
      await repo.set('theme', 'system');

      final stored = await repo.get('theme');
      expect(stored, 'system');
    });
  });

  group('persistence survives a simulated restart', () {
    test('explicit Dark: a fresh repository query still returns "dark", '
        'regardless of what the OS happens to be', () async {
      final repo = SettingsRepository();
      await repo.set('theme', 'dark');

      // "Restart": a brand-new repository instance re-queries the same
      // on-disk (in-memory-for-tests) DB — nothing here is in-process
      // widget/notifier state.
      final freshRepo = SettingsRepository();
      final stored = await freshRepo.get('theme');

      expect(stored, 'dark',
          reason: 'an explicit choice must survive a relaunch unchanged, '
              'never reset to System or replaced by the current OS state');
      expect(themeModeFromString(stored!), ThemeMode.dark);
    });

    test('System: a fresh repository query still returns "system", the mode '
        'selector — not a resolved brightness snapshotted at save time',
        () async {
      final repo = SettingsRepository();
      await repo.set('theme', 'system');

      final freshRepo = SettingsRepository();
      final stored = await freshRepo.get('theme');

      expect(stored, 'system',
          reason: 'must re-derive from the OS at each launch, so only the '
              'mode selector — never a resolved brightness — is persisted');
      expect(themeModeFromString(stored!), ThemeMode.system);
    });

    test('a fresh install seeds "system" as the default (schema.dart), '
        'not a leftover value from a previous run', () async {
      final freshRepo = SettingsRepository();
      final stored = await freshRepo.get('theme');

      expect(stored, 'system');
      expect(themeModeFromString(stored ?? 'system'), ThemeMode.system);
    });
  });
}
