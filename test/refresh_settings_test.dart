import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/db/schema.dart';
import 'package:flash/models/settings.dart';
import 'package:flash/widgets/refresh_interval_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('background refresh interval default', () {
    // This default has been changed several times. Nothing in the suite
    // covered it, so every one of those changes landed silently — including
    // 30 -> 180, which broke no test. Pin it.
    test('a fresh AppSettings defaults to 3 hours', () {
      expect(const AppSettings().refreshIntervalMinutes, 180);
    });

    test('an empty settings row defaults to 3 hours', () {
      expect(AppSettings.fromMap({}).refreshIntervalMinutes, 180);
    });

    test('an unparseable stored value falls back to 3 hours', () {
      expect(
        AppSettings.fromMap({'refresh_interval_minutes': 'banana'})
            .refreshIntervalMinutes,
        180,
      );
    });

    test('a stored value is honoured', () {
      expect(
        AppSettings.fromMap({'refresh_interval_minutes': '60'})
            .refreshIntervalMinutes,
        60,
      );
    });

    test('0 survives — it means never, not missing', () {
      expect(
        AppSettings.fromMap({'refresh_interval_minutes': '0'})
            .refreshIntervalMinutes,
        0,
      );
    });

    test('copyWith round-trips', () {
      expect(
        const AppSettings()
            .copyWith(refreshIntervalMinutes: 240)
            .refreshIntervalMinutes,
        240,
      );
    });

    test('the seeded row matches the model default', () {
      // defaultSettings is written on database creation, so on a fresh
      // install the seed — not the fromMap fallback — is what the app runs
      // on. When these two drift, changing the model default looks like it
      // worked and changes nothing for a new user.
      final seeded = defaultSettings
          .firstWhere((r) => r['key'] == 'refresh_interval_minutes')['value'];
      expect(
        int.parse(seeded as String),
        const AppSettings().refreshIntervalMinutes,
      );
    });
  });

  group('refresh on Wi-Fi only', () {
    test('defaults off', () {
      expect(const AppSettings().refreshOnWifiOnly, isFalse);
      expect(AppSettings.fromMap({}).refreshOnWifiOnly, isFalse);
    });

    test('reads the stored flag', () {
      expect(
        AppSettings.fromMap({'refresh_wifi_only': 'true'}).refreshOnWifiOnly,
        isTrue,
      );
      expect(
        AppSettings.fromMap({'refresh_wifi_only': 'false'}).refreshOnWifiOnly,
        isFalse,
      );
    });

    test('copyWith round-trips', () {
      expect(
        const AppSettings().copyWith(refreshOnWifiOnly: true).refreshOnWifiOnly,
        isTrue,
      );
    });
  });

  group('the interval ladder', () {
    late AppLocalizations l10n;

    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('en'));
    });

    test('is exactly the eight options, in order', () {
      expect(
        refreshIntervalOptions(l10n).map((o) => o.$1).toList(),
        [30, 60, 120, 180, 240, 300, 360, 0],
      );
    });

    test('15 minutes is gone', () {
      // Android clamps a PeriodicWorkRequest at 15 minutes, so the option
      // promised a cadence the platform would not deliver.
      expect(
          refreshIntervalOptions(l10n).map((o) => o.$1), isNot(contains(15)));
    });

    test('the default is actually selectable', () {
      // A default that is not in the list would leave the field with nothing
      // to show for it — the failure mode the field's orElse now absorbs.
      expect(
        refreshIntervalOptions(l10n).map((o) => o.$1),
        contains(const AppSettings().refreshIntervalMinutes),
      );
    });

    test('30 minutes is the floor and 6 hours the ceiling', () {
      final minutes =
          refreshIntervalOptions(l10n).map((o) => o.$1).where((m) => m != 0);
      expect(minutes.reduce((a, b) => a < b ? a : b), 30);
      expect(minutes.reduce((a, b) => a > b ? a : b), 360);
    });

    test('0 reads as Never, not Manual only', () {
      final never = refreshIntervalOptions(l10n).firstWhere((o) => o.$1 == 0);
      expect(never.$2, 'Never');
    });

    test('every option has a non-empty label and no duplicates', () {
      final options = refreshIntervalOptions(l10n);
      expect(options.every((o) => o.$2.trim().isNotEmpty), isTrue);
      expect(options.map((o) => o.$1).toSet().length, options.length);
      expect(options.map((o) => o.$2).toSet().length, options.length);
    });
  });
}
