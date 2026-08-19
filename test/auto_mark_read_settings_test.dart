// Storage and parsing for the end-of-feed auto mark-as-read setting.
//
// The behaviour was hardcoded (always on, 5s) before it became configurable,
// so the important properties are that upgrading users keep exactly what they
// had, and that a stored delay can never leave the Settings dropdown showing
// a value it has no item for — DropdownButton asserts on that.
//
// Plain test(), not testWidgets() — this codebase never combines testWidgets()
// with real sqflite FFI I/O (see feed_repository_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';
import 'package:flash/models/settings.dart';
import 'package:flash/repositories/settings_repository.dart';

Future<void> _setUp() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  AppDatabase.useForTesting();
}

void main() {
  group('parsing', () {
    test('defaults preserve the old hardcoded behaviour', () {
      const s = AppSettings();
      expect(s.autoMarkReadAtBottom, isTrue);
      expect(s.autoMarkReadAtBottomSeconds, 5);
    });

    test('an absent key still reads as on at 5s', () {
      final s = AppSettings.fromMap({});
      expect(s.autoMarkReadAtBottom, isTrue);
      expect(s.autoMarkReadAtBottomSeconds, 5);
    });

    test('"Immediately" is stored and read back as 0', () {
      final s = AppSettings.fromMap({'auto_mark_read_at_bottom_seconds': '0'});
      expect(s.autoMarkReadAtBottomSeconds, 0);
    });

    test('the toggle round-trips', () {
      expect(
        AppSettings.fromMap({'auto_mark_read_at_bottom': 'false'})
            .autoMarkReadAtBottom,
        isFalse,
      );
      expect(
        AppSettings.fromMap({'auto_mark_read_at_bottom': 'true'})
            .autoMarkReadAtBottom,
        isTrue,
      );
    });

    test('every offered option survives a round-trip unchanged', () {
      for (final seconds in AppSettings.autoMarkReadDelayOptions) {
        final s = AppSettings.fromMap({
          'auto_mark_read_at_bottom_seconds': seconds.toString(),
        });
        expect(s.autoMarkReadAtBottomSeconds, seconds);
      }
    });

    test('the options are 0 then 5-second steps', () {
      expect(AppSettings.autoMarkReadDelayOptions.first, 0);
      final rest = AppSettings.autoMarkReadDelayOptions.skip(1).toList();
      for (var i = 0; i < rest.length; i++) {
        expect(rest[i], (i + 1) * 5);
      }
    });
  });

  group('a stored value the dropdown has no item for is snapped, not shown', () {
    // DropdownButton throws if `value` matches none of its items, which would
    // make the Settings screen crash rather than degrade.
    test('an off-grid value snaps to the nearest option', () {
      expect(
        AppSettings.fromMap({'auto_mark_read_at_bottom_seconds': '7'})
            .autoMarkReadAtBottomSeconds,
        5,
      );
      expect(
        AppSettings.fromMap({'auto_mark_read_at_bottom_seconds': '13'})
            .autoMarkReadAtBottomSeconds,
        15,
      );
    });

    test('out-of-range values clamp to the ends', () {
      expect(
        AppSettings.fromMap({'auto_mark_read_at_bottom_seconds': '-10'})
            .autoMarkReadAtBottomSeconds,
        0,
      );
      expect(
        AppSettings.fromMap({'auto_mark_read_at_bottom_seconds': '9999'})
            .autoMarkReadAtBottomSeconds,
        AppSettings.autoMarkReadDelayOptions.last,
      );
    });

    test('garbage falls back to the default', () {
      expect(
        AppSettings.fromMap({'auto_mark_read_at_bottom_seconds': 'soon'})
            .autoMarkReadAtBottomSeconds,
        5,
      );
    });

    test('whatever is stored, it is always a valid dropdown item', () {
      for (final raw in ['0', '3', '7', '12', '28', '31', '-1', '', 'x']) {
        final s = AppSettings.fromMap({
          'auto_mark_read_at_bottom_seconds': raw,
        });
        expect(AppSettings.autoMarkReadDelayOptions,
            contains(s.autoMarkReadAtBottomSeconds),
            reason: 'stored "$raw" resolved to a value with no dropdown item');
      }
    });
  });

  group('persistence', () {
    setUp(_setUp);
    tearDown(() => AppDatabase.instance.close());

    test('a fresh install seeds the previous hardcoded behaviour', () async {
      await AppDatabase.instance.database;
      final settings = await SettingsRepository().getAll();

      expect(settings.autoMarkReadAtBottom, isTrue);
      expect(settings.autoMarkReadAtBottomSeconds, 5);
    });

    test('both keys survive a save and re-read', () async {
      final repo = SettingsRepository();
      await repo.set('auto_mark_read_at_bottom', 'false');
      await repo.set('auto_mark_read_at_bottom_seconds', '0');

      final fresh = await SettingsRepository().getAll();
      expect(fresh.autoMarkReadAtBottom, isFalse);
      expect(fresh.autoMarkReadAtBottomSeconds, 0);
    });

    test('the v10 migration seeds the keys for an upgrading user', () async {
      final db = await AppDatabase.instance.database;
      // Simulate a v9 database, which had neither key.
      await db.delete('settings',
          where: 'key IN (?, ?)',
          whereArgs: [
            'auto_mark_read_at_bottom',
            'auto_mark_read_at_bottom_seconds',
          ]);
      expect(await SettingsRepository().get('auto_mark_read_at_bottom'), isNull);

      await AppDatabase.instance.migrateForTesting(fromVersion: 9);

      final settings = await SettingsRepository().getAll();
      expect(settings.autoMarkReadAtBottom, isTrue,
          reason: 'upgrading users must see no behaviour change');
      expect(settings.autoMarkReadAtBottomSeconds, 5);
    });

    test('the migration does not overwrite a choice already made', () async {
      final repo = SettingsRepository();
      await repo.set('auto_mark_read_at_bottom', 'false');
      await repo.set('auto_mark_read_at_bottom_seconds', '20');

      await AppDatabase.instance.migrateForTesting(fromVersion: 9);

      final settings = await SettingsRepository().getAll();
      expect(settings.autoMarkReadAtBottom, isFalse);
      expect(settings.autoMarkReadAtBottomSeconds, 20);
    });
  });
}
