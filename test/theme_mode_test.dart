// Theme mode resolution tests.
//
// Covers the System/Light/Dark toggle: cold start must reflect the live OS
// brightness (not a stale/cached value), System must keep tracking the OS
// live while foregrounded and on resume from background, Light/Dark are
// sticky overrides that never follow the OS, and Newspaper mode overrides
// all of the above unconditionally.
//
// These are widget tests but deliberately never touch the real database —
// flutter_test's FakeAsync zone cannot wait out a real sqflite FFI Future
// (nothing else in this codebase combines testWidgets() with a real DB;
// see feed_repository_test.dart for the DB-only pattern used instead).
// FlashApp.initialSettingsForTesting seeds initial state directly, and
// widget.themeModeNotifier / newspaperModeNotifier — the exact mechanism
// SettingsScreen already uses — drive toggle presses.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/app.dart';

/// The State's ThemeMode isn't exposed publicly, so read the *effect* it
/// has on the live MaterialApp instead — this is what's actually rendered,
/// which is what the bug report is about.
ThemeMode _renderedThemeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

ThemeData _renderedLightTheme(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!;

Future<FlashApp> _pumpApp(
  WidgetTester tester, {
  required String theme,
  bool newspaperMode = false,
  Brightness platformBrightness = Brightness.light,
}) async {
  tester.platformDispatcher.platformBrightnessTestValue = platformBrightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

  final app = FlashApp(
    initialSettingsForTesting: (theme: theme, newspaperMode: newspaperMode),
    // Skips _AppShell (and the four DB-backed screens it eagerly builds) —
    // out of scope here and, more importantly, incompatible with
    // testWidgets()'s FakeAsync zone. See feed_repository_test.dart for
    // where DB-backed persistence is actually verified.
    homeOverrideForTesting: const SizedBox.shrink(),
  );
  await tester.pumpWidget(app);
  await tester.pump();
  return app;
}

void main() {
  group('cold start', () {
    testWidgets('System mode, OS = Light → renders Light on first frame',
        (tester) async {
      await _pumpApp(tester, theme: 'system', platformBrightness: Brightness.light);
      expect(_renderedThemeMode(tester), ThemeMode.system);
      expect(tester.platformDispatcher.platformBrightness, Brightness.light);
    });

    testWidgets('System mode, OS = Dark → renders Dark on first frame',
        (tester) async {
      await _pumpApp(tester, theme: 'system', platformBrightness: Brightness.dark);
      expect(_renderedThemeMode(tester), ThemeMode.system);
      expect(tester.platformDispatcher.platformBrightness, Brightness.dark);
    });

    testWidgets('explicit Light selected, OS = Dark → renders Light, OS ignored',
        (tester) async {
      await _pumpApp(tester, theme: 'light', platformBrightness: Brightness.dark);
      expect(_renderedThemeMode(tester), ThemeMode.light);
    });

    testWidgets('explicit Dark selected, OS = Light → renders Dark, OS ignored',
        (tester) async {
      await _pumpApp(tester, theme: 'dark', platformBrightness: Brightness.light);
      expect(_renderedThemeMode(tester), ThemeMode.dark);
    });
  });

  group('resume from background', () {
    testWidgets(
        'System mode: OS theme changed while backgrounded → resume picks it up '
        '— the exact bug report scenario', (tester) async {
      // App was backgrounded with the OS on Dark.
      await _pumpApp(tester, theme: 'system', platformBrightness: Brightness.dark);
      expect(_renderedThemeMode(tester), ThemeMode.system);
      expect(tester.platformDispatcher.platformBrightness, Brightness.dark);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // OS switches to Light while the app sits in the background — this is
      // the platform-brightness change the app must not have missed.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(_renderedThemeMode(tester), ThemeMode.system);
      expect(tester.platformDispatcher.platformBrightness, Brightness.light,
          reason: 'resume must re-check the OS theme, not replay a stale value');
    });
  });

  group('live OS theme change while foregrounded', () {
    testWidgets('System mode: didChangePlatformBrightness updates immediately, '
        'no resume/restart required', (tester) async {
      final app = await _pumpApp(tester,
          theme: 'system', platformBrightness: Brightness.light);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      // Fire the callback the same way the engine would — directly, so this
      // asserts app.dart's own hook, not just MaterialApp's built-in one.
      final state = tester.state<State<FlashApp>>(find.byType(FlashApp));
      (state as WidgetsBindingObserver).didChangePlatformBrightness();
      await tester.pump();

      expect(app.initialSettingsForTesting!.theme, 'system');
      expect(tester.platformDispatcher.platformBrightness, Brightness.dark);
      expect(_renderedThemeMode(tester), ThemeMode.system);
    });
  });

  group('toggle presses', () {
    testWidgets('System → Light stops tracking the OS', (tester) async {
      await _pumpApp(tester, theme: 'system', platformBrightness: Brightness.light);

      final appState = tester.state(find.byType(FlashApp)) as dynamic;
      appState.themeModeNotifier.value = 'light';
      await tester.pump();
      expect(_renderedThemeMode(tester), ThemeMode.light);

      // Now change the OS — an explicit Light choice must ignore it.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      (appState as WidgetsBindingObserver).didChangePlatformBrightness();
      await tester.pump();

      expect(_renderedThemeMode(tester), ThemeMode.light,
          reason: 'an explicit choice must not follow the OS');
    });

    testWidgets('Light → System picks up the current OS state immediately',
        (tester) async {
      await _pumpApp(tester, theme: 'light', platformBrightness: Brightness.dark);
      expect(_renderedThemeMode(tester), ThemeMode.light);

      final appState = tester.state(find.byType(FlashApp)) as dynamic;
      appState.themeModeNotifier.value = 'system';
      await tester.pump();

      expect(_renderedThemeMode(tester), ThemeMode.system);
      expect(tester.platformDispatcher.platformBrightness, Brightness.dark,
          reason: 'switching to System must reflect the OS as it is right now');
    });
  });

  group('Newspaper mode override', () {
    testWidgets(
        'System mode underneath, OS = Dark, app resumes from background → '
        'still renders Newspaper, not Dark', (tester) async {
      await _pumpApp(tester,
          theme: 'system', newspaperMode: true, platformBrightness: Brightness.light);

      // Newspaper always renders as its own (light-based) palette, ignoring
      // themeMode entirely — confirmed via the light theme's own colours
      // rather than themeMode, since Newspaper forces ThemeMode.light too.
      final newspaperTheme = _renderedLightTheme(tester);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(_renderedThemeMode(tester), ThemeMode.light,
          reason: 'Newspaper forces light rendering regardless of OS brightness');
      expect(_renderedLightTheme(tester).scaffoldBackgroundColor,
          newspaperTheme.scaffoldBackgroundColor,
          reason: 'still the Newspaper palette, not a resolved Dark theme');
    });

    testWidgets(
        'Newspaper toggled off while System is the underlying selection → '
        'immediately falls back to resolving System/OS, no stale styling',
        (tester) async {
      await _pumpApp(tester,
          theme: 'system', newspaperMode: true, platformBrightness: Brightness.dark);
      expect(_renderedThemeMode(tester), ThemeMode.light,
          reason: 'Newspaper active');

      final appState = tester.state(find.byType(FlashApp)) as dynamic;
      appState.newspaperModeNotifier.value = false;
      await tester.pump();

      expect(_renderedThemeMode(tester), ThemeMode.system,
          reason: 'System underneath re-asserts itself once Newspaper is off');
      expect(tester.platformDispatcher.platformBrightness, Brightness.dark);
    });
  });
}
