// Newspaper mode — settings persistence + theme contract.
//
// SPEC TEST: this references symbols Claude Code will add
// (AppSettings.newspaperMode, the 'newspaper_mode' setting key, and
// flashNewspaperTheme()). It will not compile/pass until they exist — that is
// the point. Implement until green; do not change the asserted values, they
// are the agreed spec.
//
// Drop this in at test/newspaper_mode_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flash/db/database.dart';
import 'package:flash/models/settings.dart';
import 'package:flash/repositories/settings_repository.dart';
import 'package:flash/theme/app_theme.dart';

void main() {
  group('newspaper_mode setting', () {
    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppDatabase.useForTesting();
    });
    tearDown(() async => AppDatabase.instance.close());

    test('defaults to OFF (false) on a fresh database', () async {
      await AppDatabase.instance.database; // triggers create + seed
      expect(await SettingsRepository().get('newspaper_mode'), 'false');
    });

    test('AppSettings parses the flag and defaults to false', () {
      expect(const AppSettings().newspaperMode, isFalse);
      expect(AppSettings.fromMap(const <String, String>{}).newspaperMode, isFalse);
      expect(
        AppSettings.fromMap(const {'newspaper_mode': 'true'}).newspaperMode,
        isTrue,
      );
    });

    test('persists a user toggle', () async {
      final repo = SettingsRepository();
      await repo.set('newspaper_mode', 'true');
      expect(await repo.get('newspaper_mode'), 'true');
      expect((await repo.getAll()).newspaperMode, isTrue);
    });
  });

  group('flashNewspaperTheme', () {
    final t = flashNewspaperTheme();

    test('is a light theme on the newsprint paper surface', () {
      expect(t.colorScheme.brightness, Brightness.light);
      expect(t.scaffoldBackgroundColor, const Color(0xFFF2F1EE));
      expect(t.colorScheme.surface, const Color(0xFFF2F1EE));
    });

    test('uses ink for text and the spot red as primary accent', () {
      expect(t.colorScheme.onSurface, const Color(0xFF1D1D1B));
      expect(t.colorScheme.primary, const Color(0xFFA0231A));
    });

    test('body uses the serif body font, headlines the display serif', () {
      expect(t.textTheme.bodyMedium?.fontFamily, 'PT Serif');
      expect(t.textTheme.headlineMedium?.fontFamily, 'Playfair Display');
    });
  });
}
