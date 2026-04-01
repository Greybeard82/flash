import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'screens/feed_screen.dart';
import 'screens/feeds_screen.dart';
import 'screens/opinions_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';

class FlashApp extends StatelessWidget {
  const FlashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final lightTheme = lightDynamic != null
            ? flashLightTheme().copyWith(colorScheme: lightDynamic)
            : flashLightTheme();
        final darkTheme = darkDynamic != null
            ? flashDarkTheme().copyWith(colorScheme: darkDynamic)
            : flashDarkTheme();

        return MaterialApp(
          title: 'Flash',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: ThemeMode.system,
          home: const _AppShell(),
        );
      },
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  int _currentIndex = 0;

  // Incremented whenever the Feed tab is selected — FeedScreen listens and reloads
  final _feedReloadNotifier = ValueNotifier<int>(0);

  @override
  void dispose() {
    _feedReloadNotifier.dispose();
    super.dispose();
  }

  void _navigateTo(int index) {
    if (index == 0) _feedReloadNotifier.value++;
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          FeedScreen(
            onNavigateToFeeds: () => _navigateTo(1),
            reloadNotifier: _feedReloadNotifier,
          ),
          const FeedsScreen(),
          const OpinionsScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _navigateTo,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.bolt_rounded),
            label: 'Feed',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.rss_feed_rounded),
            label: 'Feeds',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shield_outlined),
            label: 'Opinions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
