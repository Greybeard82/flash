import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'repositories/settings_repository.dart';
import 'screens/feed_screen.dart';
import 'screens/feeds_screen.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'utils/form_factor.dart';

class FlashApp extends StatefulWidget {
  const FlashApp({super.key});

  @override
  State<FlashApp> createState() => _FlashAppState();
}

class _FlashAppState extends State<FlashApp> {
  final _settingsRepo = SettingsRepository();
  ThemeMode _themeMode = ThemeMode.system;

  // Notifier passed down to SettingsScreen so it can trigger a theme rebuild
  final themeModeNotifier = ValueNotifier<String>('system');

  @override
  void initState() {
    super.initState();
    _loadTheme();
    themeModeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeModeNotifier.removeListener(_onThemeChanged);
    themeModeNotifier.dispose();
    super.dispose();
  }

  Future<void> _loadTheme() async {
    final value = await _settingsRepo.get('theme') ?? 'system';
    _applyTheme(value);
  }

  void _onThemeChanged() => _applyTheme(themeModeNotifier.value);

  void _applyTheme(String value) {
    final mode = value == 'light'
        ? ThemeMode.light
        : value == 'dark'
            ? ThemeMode.dark
            : ThemeMode.system;
    if (mounted) setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flash',
      debugShowCheckedModeBanner: false,
      theme: flashLightTheme(),
      darkTheme: flashDarkTheme(),
      themeMode: _themeMode,
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
      home: _AppShell(themeModeNotifier: themeModeNotifier),
    );
  }
}

class _AppShell extends StatefulWidget {
  final ValueNotifier<String> themeModeNotifier;

  const _AppShell({required this.themeModeNotifier});

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _currentIndex = 0;
  bool _onboardingComplete = true; // assume complete until checked

  // Incremented each time the Feed tab is tapped — forces FeedScreen to remount
  // (and reload its articles) without keeping stale state across navigations.
  int _feedKey = 0;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
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
    if (index == 0) _feedKey++;
    setState(() => _currentIndex = index);
  }

  Widget get _activeScreen {
    if (!_onboardingComplete) {
      return OnboardingScreen(onDone: _finishOnboarding);
    }
    return switch (_currentIndex) {
      0 => FeedScreen(
          key: ValueKey(_feedKey),
          onNavigateToFeeds: () => _navigateTo(1),
        ),
      1 => const FeedsScreen(),
      2 => const BookmarksScreen(),
      _ => SettingsScreen(themeModeNotifier: widget.themeModeNotifier),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isTV = FormFactor.isTV;
    final width = MediaQuery.of(context).size.width;
    final useRail = isTV || width >= 600;


    final railDestinations = [
      NavigationRailDestination(
        icon: const Icon(Icons.bolt_outlined),
        selectedIcon: const Icon(Icons.bolt_rounded),
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
        icon: const Icon(Icons.settings_outlined),
        selectedIcon: const Icon(Icons.settings_rounded),
        label: Text(l10n.settings),
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
            Expanded(child: _activeScreen),
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
      onPopInvoked: (didPop) {
        if (!didPop) setState(() => _currentIndex = 0);
      },
      child: Scaffold(
        body: _activeScreen,
        bottomNavigationBar: _onboardingComplete ? BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _navigateTo,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.bolt_rounded),
              label: l10n.appTitle,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.rss_feed_rounded),
              label: l10n.categories,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.bookmark_border_rounded),
              label: l10n.bookmarks,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.settings_outlined),
              label: l10n.settings,
            ),
          ],
        ) : null,
      ),
    );
  }
}
