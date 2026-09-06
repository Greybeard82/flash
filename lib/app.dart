import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'repositories/settings_repository.dart';
import 'services/alert_navigation_intent.dart';
import 'services/alerts_changed_notifier.dart';
import 'repositories/alert_match_repository.dart';
import 'services/settings_notifier.dart';
import 'screens/feed_screen.dart';
import 'screens/feeds_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';
import 'utils/form_factor.dart';
import 'widgets/global_loading_indicator.dart';
import 'widgets/flash_bolt.dart';

/// Maps the persisted mode selector to Flutter's [ThemeMode]. Kept as a
/// free function (rather than inline) so both the real DB-backed load path
/// and the test-only seed path use the exact same mapping.
ThemeMode themeModeFromString(String value) => value == 'light'
    ? ThemeMode.light
    : value == 'dark'
        ? ThemeMode.dark
        : ThemeMode.system;

class FlashApp extends StatefulWidget {
  /// Test-only seam: seeds initial theme/newspaper state directly instead
  /// of reading it from the database in initState. Widget tests can't
  /// combine testWidgets() with real sqflite I/O (the real FFI Future never
  /// resolves inside flutter_test's FakeAsync zone), so this lets tests
  /// drive theme resolution — including the resume/live-brightness hooks —
  /// without touching the DB at all. Unused in production.
  @visibleForTesting
  final ({String theme, bool newspaperMode})? initialSettingsForTesting;

  /// Test-only seam: replaces the real `home` (`_AppShell`, which eagerly
  /// builds all four main screens — each of which hits the real DB in its
  /// own initState) with a trivial widget. The theme/lifecycle machinery
  /// under test lives entirely in this widget's own State, above `home`,
  /// so this isolates it from unrelated DB-backed subtrees. Unused in
  /// production.
  @visibleForTesting
  final Widget? homeOverrideForTesting;

  const FlashApp({
    super.key,
    this.initialSettingsForTesting,
    this.homeOverrideForTesting,
  });

  @override
  State<FlashApp> createState() => _FlashAppState();
}

class _FlashAppState extends State<FlashApp> with WidgetsBindingObserver {
  final _settingsRepo = SettingsRepository();
  ThemeMode _themeMode = ThemeMode.system;
  bool _newspaper = false;
  String _palette = kDefaultPalette;

  // Notifiers passed down so SettingsScreen can trigger instant rebuilds.
  final themeModeNotifier = ValueNotifier<String>('system');
  final newspaperModeNotifier = ValueNotifier<bool>(false);
  final paletteNotifier = ValueNotifier<String>(kDefaultPalette);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final seed = widget.initialSettingsForTesting;
    if (seed != null) {
      _themeMode = themeModeFromString(seed.theme);
      _newspaper = seed.newspaperMode;
      // Keep the notifiers' cached value in sync with the seed — otherwise
      // a notifier sitting on its unset default silently no-ops the next
      // time it's set to that same value (ValueNotifier only notifies on
      // an actual change), before any listener is attached to observe it.
      themeModeNotifier.value = seed.theme;
      newspaperModeNotifier.value = seed.newspaperMode;
    } else {
      _loadSettings();
    }
    themeModeNotifier.addListener(_onThemeChanged);
    newspaperModeNotifier.addListener(_onNewspaperChanged);
    paletteNotifier.addListener(_onPaletteChanged);
    // Theme and Newspaper mode are set from the Quick Settings bubble on the
    // feed — the only place they live now — which writes them straight to the
    // DB. Without this the change would only appear on the next launch. Same
    // pattern FeedScreen already uses to pick up settings changes.
    SettingsNotifier.instance.addListener(_onSettingsChangedExternally);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SettingsNotifier.instance.removeListener(_onSettingsChangedExternally);
    themeModeNotifier.removeListener(_onThemeChanged);
    themeModeNotifier.dispose();
    newspaperModeNotifier.removeListener(_onNewspaperChanged);
    newspaperModeNotifier.dispose();
    paletteNotifier.removeListener(_onPaletteChanged);
    paletteNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // 'theme' is always the mode selector ('system'/'light'/'dark'), never
    // a resolved brightness — System re-derives from the live OS brightness
    // on every build via ThemeMode.system, so nothing here is cached stale.
    final theme = await _settingsRepo.get('theme') ?? 'system';
    final newspaper = (await _settingsRepo.get('newspaper_mode')) == 'true';
    final palette = await _settingsRepo.get('color_palette') ?? kDefaultPalette;
    // Keep the notifiers' cached value in sync with what's actually loaded
    // — see the matching comment in initState for why this matters.
    themeModeNotifier.value = theme;
    newspaperModeNotifier.value = newspaper;
    paletteNotifier.value = palette;
    _applyTheme(theme);
    if (mounted) setState(() { _newspaper = newspaper; _palette = palette; });
  }

  /// A setting was written somewhere other than the Settings screen — today,
  /// the Quick Settings bubble on the feed. Re-read from the DB and push the
  /// values through the same notifiers the Settings screen drives, so both
  /// routes converge rather than each having their own path.
  ///
  /// Skipped when [FlashApp.initialSettingsForTesting] is in play, since that
  /// seam exists precisely to keep the DB out of widget tests.
  Future<void> _onSettingsChangedExternally() async {
    if (widget.initialSettingsForTesting != null) return;
    await _loadSettings();
  }

  void _onThemeChanged() => _applyTheme(themeModeNotifier.value);
  void _onNewspaperChanged() {
    if (mounted) setState(() => _newspaper = newspaperModeNotifier.value);
  }
  void _onPaletteChanged() {
    if (mounted) setState(() => _palette = paletteNotifier.value);
  }

  void _applyTheme(String value) {
    if (mounted) setState(() => _themeMode = themeModeFromString(value));
  }

  // ── Keep "System" tracking the live OS theme ────────────────────────────
  //
  // MaterialApp(themeMode: ThemeMode.system) already re-resolves platform
  // brightness on every build, so in principle a rebuild alone is enough —
  // these two hooks exist because a background app can miss/delay the
  // platform's brightness-change notification (the reported bug: OS was
  // Light at 9am, app opened Dark because it never re-checked after being
  // backgrounded overnight). Forcing a rebuild here costs nothing when the
  // brightness didn't actually change, and fixes it when it did.

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    _reresolveSystemTheme();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _reresolveSystemTheme();
    }
  }

  /// Newspaper mode overrides System/Light/Dark entirely (build() forces
  /// ThemeMode.light whenever it's on), and an explicit Light/Dark choice
  /// is a sticky override that must never follow the OS — so there is
  /// nothing to re-resolve in either case; only System mode needs a nudge.
  void _reresolveSystemTheme() {
    if (_newspaper || _themeMode != ThemeMode.system) return;
    if (mounted) setState(() {});
  }

  /// Keeps the native window background in step with whatever this build
  /// actually renders — including Newspaper mode, and including System mode
  /// resolving against the live OS brightness. Without this the Activity
  /// guesses from the OS uiMode and gets it wrong for every explicit
  /// Light/Dark choice that disagrees with the system.
  void _syncNativeWindowBackground(
    ThemeData light,
    ThemeData dark,
    ThemeMode mode,
  ) {
    final resolved = switch (mode) {
      ThemeMode.light => light,
      ThemeMode.dark => dark,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark
            ? dark
            : light,
    };
    final colour = resolved.scaffoldBackgroundColor;
    if (colour == _lastNativeBackground) return;
    _lastNativeBackground = colour;
    unawaited(setNativeWindowBackground(colour));
  }

  Color? _lastNativeBackground;

  @override
  Widget build(BuildContext context) {
    // Newspaper mode always renders as paper (light), ignoring the theme and
    // palette choice entirely.
    final theme = _newspaper
        ? flashNewspaperTheme()
        : flashPaletteTheme(palette: _palette, brightness: Brightness.light);
    final darkTheme = _newspaper
        ? flashNewspaperTheme()
        : flashPaletteTheme(palette: _palette, brightness: Brightness.dark);
    final themeMode  = _newspaper ? ThemeMode.light : _themeMode;

    _syncNativeWindowBackground(theme, darkTheme, themeMode);

    return MaterialApp(
      title: 'Flash',
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('es'),
        Locale('fr'),
        Locale('de'),
        Locale('it'),
      ],
      home: widget.homeOverrideForTesting ??
          _AppShell(
            themeModeNotifier: themeModeNotifier,
            newspaperModeNotifier: newspaperModeNotifier,
          ),
    );
  }
}

class _AppShell extends StatefulWidget {
  final ValueNotifier<String> themeModeNotifier;
  final ValueNotifier<bool> newspaperModeNotifier;

  const _AppShell({
    required this.themeModeNotifier,
    required this.newspaperModeNotifier,
  });

  @override
  State<_AppShell> createState() => _AppShellState();
}

/// Alerts' slot in the bottom nav and the rail — Settings' old index, now
/// that Settings is reached from the Quick Settings panel instead.
const int kAlertsNavIndex = 3;

class _AppShellState extends State<_AppShell> {
  int _currentIndex = 0;
  bool _onboardingComplete = true; // assume complete until checked
  int _alertsCount = 0;

  // Incremented each time the Feed tab is tapped while already on Feed —
  // triggers a reload via didUpdateWidget without remounting FeedScreen.
  int _feedRefreshTrigger = 0;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
    AlertNavigationIntent.instance.addListener(_onAlertsRequested);
    AlertsChangedNotifier.instance.addListener(_refreshAlertsCount);
    _refreshAlertsCount();
  }

  @override
  void dispose() {
    AlertNavigationIntent.instance.removeListener(_onAlertsRequested);
    AlertsChangedNotifier.instance.removeListener(_refreshAlertsCount);
    super.dispose();
  }

  /// A keyword-alert notification was tapped. Alerts is its own destination
  /// now, so this puts the nav bar on it.
  ///
  /// The flag is deliberately *not* cleared here. AlertsScreen calls
  /// [AlertNavigationIntent.consumePending] to reload and scroll to the top,
  /// and it may not exist yet on a cold start -- the tap is recorded in
  /// `main()`, before any of this is built -- so clearing it on the way past
  /// would land the user on an Alerts list left wherever they last scrolled
  /// it, with nothing to say why the app opened.
  void _onAlertsRequested() {
    if (!mounted || _currentIndex == kAlertsNavIndex) return;
    setState(() => _currentIndex = kAlertsNavIndex);
  }

  /// The number on the Alerts destination.
  ///
  /// `totalEntryCount()` -- every entry, read and unread alike -- because that
  /// is exactly what the Alerts pill showed before it became a destination.
  /// Re-read whenever the alerts change and on every tab switch, which is the
  /// same reach the pill had: it refreshed when FeedScreen reloaded, so a
  /// background fetch was never live there either.
  Future<void> _refreshAlertsCount() async {
    final count = await AlertMatchRepository().totalEntryCount();
    if (mounted && count != _alertsCount) setState(() => _alertsCount = count);
  }

  Future<void> _checkOnboarding() async {
    final complete =
        (await SettingsRepository().get('onboarding_complete')) == 'true';
    if (mounted && !complete) setState(() => _onboardingComplete = false);
  }

  void _finishOnboarding() {
    setState(() {
      _onboardingComplete = true;
      _currentIndex = 1; // go straight to Feeds tab to add first feed
    });
  }

  void _navigateTo(int index) {
    if (index == 0 && _currentIndex == 0) {
      // Already on Feed tab — trigger reload without remounting
      setState(() => _feedRefreshTrigger++);
    } else {
      setState(() => _currentIndex = index);
      // Cheap, and it is the moment the number is about to be looked at.
      unawaited(_refreshAlertsCount());
    }
  }

  // All screens are kept alive in the IndexedStack so state (scroll position,
  // loaded articles) survives tab switches and theme changes.
  Widget _buildScreenStack() {
    if (!_onboardingComplete) {
      return OnboardingScreen(onDone: _finishOnboarding);
    }
    return Stack(
      children: [
        IndexedStack(
          index: _currentIndex,
          children: [
            FeedScreen(
              onNavigateToFeeds: () => _navigateTo(1),
              refreshTrigger: _feedRefreshTrigger,
              isVisible: _currentIndex == 0,
            ),
            const FeedsScreen(),
            const BookmarksScreen(),
            const AlertsScreen(),
          ],
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: GlobalLoadingIndicator(),
        ),
      ],
    );
  }

  /// The bell, with the entry count on it when there is one.
  ///
  /// The count came with the feature: the Alerts pill carried it, and moving
  /// Alerts to the nav bar without it would have quietly dropped the only
  /// place the app says how much the keywords have caught.
  Widget _alertsIcon(IconData icon) => _alertsCount > 0
      ? Badge.count(count: _alertsCount, child: Icon(icon))
      : Icon(icon);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isTV = FormFactor.isTV;
    final width = MediaQuery.of(context).size.width;
    final useRail = isTV || width >= 600;

    final railDestinations = [
      NavigationRailDestination(
        // One mark, not an outline/filled pair: NavigationRail already
        // supplies the selected and unselected colours through IconTheme, and
        // FlashBolt reads them.
        icon: const FlashBolt(),
        selectedIcon: const FlashBolt(),
        label: Text(l10n.appTitle),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.rss_feed_outlined),
        selectedIcon: const Icon(Icons.rss_feed_rounded),
        label: Text(l10n.categories),
      ),
      NavigationRailDestination(
        icon: const Icon(Icons.bookmark_border_rounded),
        selectedIcon: const Icon(Icons.bookmark_rounded),
        label: Text(l10n.bookmarks),
      ),
      NavigationRailDestination(
        icon: _alertsIcon(Icons.notifications_none_rounded),
        selectedIcon: _alertsIcon(Icons.notifications_active_rounded),
        label: Text(l10n.alertsTab),
      ),
    ];

    if (useRail) {
      Widget shell = Scaffold(
        body: Row(
          children: [
            if (_onboardingComplete) ...[
              NavigationRail(
                selectedIndex: _currentIndex,
                onDestinationSelected: _navigateTo,
                extended: isTV,
                labelType: isTV
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                destinations: railDestinations,
              ),
              const VerticalDivider(thickness: 1, width: 1),
            ],
            Expanded(child: _buildScreenStack()),
          ],
        ),
      );

      // On TV scale text up so it's legible from the couch
      if (isTV) {
        shell = MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.4),
          ),
          child: shell,
        );
      }

      return PopScope(
        canPop: _currentIndex == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _currentIndex = 0);
        },
        child: shell,
      );
    }

    // Phone: classic bottom navigation bar
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _currentIndex = 0);
      },
      child: Scaffold(
        body: _buildScreenStack(),
        bottomNavigationBar: _onboardingComplete ? BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _navigateTo,
          items: [
            BottomNavigationBarItem(
              icon: const FlashBolt(),
              activeIcon: const FlashBolt(),
              label: l10n.appTitle,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.rss_feed_outlined),
              activeIcon: const Icon(Icons.rss_feed_rounded),
              label: l10n.categories,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.bookmark_border_rounded),
              activeIcon: const Icon(Icons.bookmark_rounded),
              label: l10n.bookmarks,
            ),
            BottomNavigationBarItem(
              icon: _alertsIcon(Icons.notifications_none_rounded),
              activeIcon: _alertsIcon(Icons.notifications_active_rounded),
              label: l10n.alertsTab,
            ),
          ],
        ) : null,
      ),
    );
  }
}
