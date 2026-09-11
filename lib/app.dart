import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';
import 'repositories/settings_repository.dart';
import 'services/alert_navigation_intent.dart';
import 'services/alerts_changed_notifier.dart';
import 'repositories/alert_match_repository.dart';
import 'services/article_detail_controller.dart';
import 'services/section_actions_controller.dart';
import 'services/feeds_changed_notifier.dart';
import 'services/settings_notifier.dart';
import 'widgets/spinning_refresh_icon.dart';
import 'widgets/article_detail_pane.dart';
import 'screens/feed_screen.dart';
import 'screens/feeds_screen.dart';
import 'screens/alerts_screen.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';
import 'utils/form_factor.dart';
import 'widgets/bubble_panel.dart';
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

/// The leftmost column of the three-column layout: the four app sections.
///
/// Deliberately not a [NavigationRail] — the rail is what this replaces at
/// this width, and rendering both would put two navigation surfaces answering
/// the same question side by side. Order matches the phone's bottom nav so
/// the app does not reorder itself when it gets wider.
class _SectionsColumn extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final int alertsCount;

  /// Which screen edge the bar is pinned to. Only the safe-area inset cares:
  /// the contents of the column are identical either way.
  final bool swapped;

  /// Mirrors the layout. Null on TV, which has no way to put it back.
  final VoidCallback? onSwapSides;

  const _SectionsColumn({
    required this.currentIndex,
    required this.onSelected,
    required this.alertsCount,
    required this.swapped,
    required this.onSwapSides,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    Widget entry(int index, Widget icon, String label) {
      final selected = index == currentIndex;
      final colour = selected
          ? theme.colorScheme.secondary
          : theme.colorScheme.onSurface.withValues(alpha: 0.6);
      return InkWell(
        onTap: () => onSelected(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Column(
            children: [
              IconTheme(
                data: IconThemeData(color: colour, size: 24),
                child: icon,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colour,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final alertsIcon = alertsCount > 0
        ? Badge.count(
            count: alertsCount,
            child: Icon(currentIndex == kAlertsNavIndex
                ? Icons.notifications_active_rounded
                : Icons.notifications_none_rounded),
          )
        : Icon(currentIndex == kAlertsNavIndex
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded);

    return SafeArea(
      // Pad the edge the bar is actually against. A hardcoded `right: false`
      // was right for as long as the bar could only be on the left; mirrored,
      // it would put the icons under a cutout.
      left: !swapped,
      right: swapped,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  entry(0, const FlashBolt(), l10n.appTitle),
                  entry(
                      1,
                      Icon(currentIndex == 1
                          ? Icons.rss_feed_rounded
                          : Icons.rss_feed_outlined),
                      l10n.categories),
                  entry(
                      2,
                      Icon(currentIndex == 2
                          ? Icons.bookmark_rounded
                          : Icons.bookmark_border_rounded),
                      l10n.bookmarks),
                  entry(kAlertsNavIndex, alertsIcon, l10n.alertsTab),
                  const SectionActionsList(),
                ],
              ),
            ),
          ),
          // Pinned below the scrollable entries rather than part of them.
          // Everything above leads somewhere; this one moves the bar itself,
          // and a short window must not be able to scroll it out of reach.
          if (onSwapSides != null) _SwapSidesButton(onPressed: onSwapSides!),
        ],
      ),
    );
  }
}

/// The current section's actions, rendered under the section switcher.
///
/// Deliberately never draws a selected state: these fire and are done, and
/// a persistent highlight would say the sidebar has two things selected at
/// once. Everything else — icon size, label style, padding — matches the
/// entries above so the column reads as one list.
class SectionActionsList extends StatelessWidget {
  /// Rail tiers get less vertical room per entry than the custom sidebar.
  final bool compact;

  const SectionActionsList({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return AnimatedBuilder(
      animation: SectionActionsController.instance,
      builder: (context, _) {
        final actions = SectionActionsController.instance.actions;
        if (actions.isEmpty) return const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(
              height: compact ? 12 : 20,
              indent: 12,
              endIndent: 12,
              color: theme.dividerColor,
            ),
            for (final action in actions)
              Tooltip(
                message: action.label,
                child: InkWell(
                  onTap: action.onPressed,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: compact ? 8 : 12, horizontal: 4),
                    child: Opacity(
                      // Disabled rather than hidden: Flash's refresh stays
                      // put while it runs, so the column does not reshuffle
                      // under a finger that is about to tap the next thing.
                      opacity: action.onPressed == null ? 0.4 : 1.0,
                      child: Column(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: action.busy
                                ? SpinningRefreshIcon(size: 20, color: colour)
                                : Icon(action.icon, size: 24, color: colour),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            action.label,
                            // Two lines, where the section entries above get
                            // one. Those are single words that fit a 72dp
                            // rail; these are phrases that do not, and on a
                            // real tablet they came out as "Mark all a…" and
                            // "Keyword a…". Wrapping is the cheap half of
                            // that trade — the rail was deliberately slimmed,
                            // and there is nothing but empty column below.
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: colour, height: 1.15),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Mirrors the tablet layout, from the bar it moves.
///
/// Deliberately not in Settings. This is a handedness choice — which thumb
/// reaches the navigation — and the only way to know whether you want it is
/// to look at the thing it moves while you move it. It is also cheap and
/// reversible, which is the test for whether a control belongs on the surface
/// it affects rather than two screens away from it.
///
/// Styled as one more entry in the column above it, because that is what it
/// reads as; the divider is the only thing saying it is a different kind of
/// entry, the same way [SectionActionsList] separates itself from the
/// destinations.
class _SwapSidesButton extends StatelessWidget {
  final VoidCallback onPressed;

  /// Rail tiers get less vertical room per entry, as in [SectionActionsList].
  final bool compact;

  const _SwapSidesButton({required this.onPressed, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colour = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    Widget button = Tooltip(
      message: l10n.swapSides,
      child: InkWell(
        onTap: onPressed,
        child: ConstrainedBox(
          // A 24dp icon and an 11sp label already clear this; stated anyway,
          // because the thing that would quietly break it is a future edit
          // dropping the label, and nobody would notice the target shrinking.
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding:
                EdgeInsets.symmetric(vertical: compact ? 8 : 12, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.swap_horiz_rounded, size: 24, color: colour),
                const SizedBox(height: 4),
                Text(
                  l10n.swapSides,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colour, height: 1.15),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (compact) {
      // The three-column bar is a fixed 72dp, so its label is constrained by
      // the column. A rail is not: Flutter sizes it to its widest child, so
      // without this the German label — "Seiten tauschen", longer than every
      // destination — would be the thing deciding how wide the rail is.
      button = ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: NavigationRailTheme.of(context).minWidth ?? 80),
        child: button,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: compact ? 12 : 20,
          indent: 12,
          endIndent: 12,
          color: theme.dividerColor,
        ),
        button,
      ],
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

/// Width at which the shell switches from "one screen at a time" to the
/// three-column reading layout. Material's Expanded breakpoint.
const double kThreeColumnBreakpoint = 840;

/// The sections list on the left. Its job is to get out of the way of the
/// two columns that actually hold content.
///
/// Measured rather than guessed, and the measurement says the labels cannot
/// be the thing that sets this width: at `labelSmall`, English "Categories"
/// wants 123dp of rail and German "Benachrichtigungen" wants 215dp, so two
/// of the four English labels were already ellipsised at the old 96dp and
/// every locale had at least one. A rail wide enough to spell them all out
/// would be wider than the one being complained about, not narrower.
///
/// So this is sized for the icon, which is what actually identifies a
/// destination here, and the label is a hint under it that may or may not
/// fit whole. 72dp leaves the 24dp icon comfortable without the empty
/// gutter either side that made the old width read as thick.
const double kSectionsColumnWidth = 72;

/// Width of the draggable handle between the article list and the reading
/// pane. The line inside it stays 1dp; the rest is invisible grab area,
/// because a 1dp touch target is not one.
const double kResizeHandleWidth = 12;

/// The middle column is held near phone width on purpose. Every screen in it
/// is the same widget the phone build renders, app bar and FAB cluster and
/// all; giving it roughly the width it was designed for is what makes that
/// reuse work instead of needing four bespoke narrow layouts.
const double kSectionColumnMaxWidth = 420;

/// Floor for the middle column. Below this the phone-oriented screens it
/// hosts start fighting their own chrome — the app bar's actions and the FAB
/// cluster were laid out for something near phone width.
const double kSectionColumnMinWidth = 340;

/// Cap on the reading pane. A web page stretched across the full width of a
/// 1700dp tablet is unreadable, so past this the whole composition centres
/// and leaves margins instead.
const double kDetailPaneMaxWidth = 880;

/// Floor for the reading pane, roughly a phone's own portrait width — the
/// baseline responsive web design already targets, so a site rendered this
/// narrow is a layout every site is built to handle.
const double kDetailPaneMinWidth = 420;

/// How the two content columns divide [available] — the width left after the
/// sections rail and the dividers.
///
/// The middle column used to be a fixed [SizedBox] and the reading pane a
/// plain [Expanded], which meant the middle never gave up a pixel and the
/// pane absorbed the entire shortfall. That was invisible on a large tablet
/// and cramped the pane badly at real phone-landscape widths (~923dp on the
/// Pixel, ~977dp on the Samsung), which is the whole reason this exists.
///
/// Both columns shrink together now, each giving up a share of the shortfall
/// proportional to how much it *can* give before hitting its own floor — so
/// the pane, which has far more slack between 880 and 420, yields more than
/// the middle column does, without the middle column staying rigid.
({double middle, double detail}) threeColumnWidths(double available) {
  const preferred = kSectionColumnMaxWidth + kDetailPaneMaxWidth;
  if (available >= preferred) {
    return (middle: kSectionColumnMaxWidth, detail: kDetailPaneMaxWidth);
  }

  const minimums = kSectionColumnMinWidth + kDetailPaneMinWidth;
  if (available <= minimums) {
    // Narrower than both floors combined — which the breakpoint alone does
    // not rule out, since 840dp leaves less than 760dp for the two of them.
    // Nothing is left to negotiate, so each column takes the same share of
    // what there is that its floor represents. Cramped, but it fits, which
    // an overflowing Row would not.
    final scale = available / minimums;
    return (
      middle: kSectionColumnMinWidth * scale,
      detail: kDetailPaneMinWidth * scale,
    );
  }

  final deficit = preferred - available;
  const middleRange = kSectionColumnMaxWidth - kSectionColumnMinWidth;
  const detailRange = kDetailPaneMaxWidth - kDetailPaneMinWidth;
  const totalRange = middleRange + detailRange;
  return (
    middle: kSectionColumnMaxWidth - deficit * (middleRange / totalRange),
    detail: kDetailPaneMaxWidth - deficit * (detailRange / totalRange),
  );
}

/// The widest the middle column may be dragged, given [available].
///
/// Whatever is left once the reading pane keeps its own floor — dragging
/// towards the list must not crush the pane any more than dragging the other
/// way may crush the list. [math.max] guards the narrow end: at the 840dp
/// breakpoint the two floors already want more room than there is, and a
/// clamp whose lower bound exceeds its upper throws.
double maxDraggableMiddleWidth(double available) =>
    math.max(kSectionColumnMinWidth, available - kDetailPaneMinWidth);

/// The widths actually used, once the reader's own preference is taken into
/// account.
///
/// [manualMiddle] is null until the divider is dragged, and null means the
/// automatic split — so the default behaviour is exactly [threeColumnWidths]
/// and nothing changes for anyone who never touches the handle.
///
/// Once it is non-null the reading pane deliberately loses its
/// [kDetailPaneMaxWidth] cap. That cap exists to stop a web page stretching
/// unreadably wide *when nobody has said otherwise*; someone who has just
/// dragged the divider to get more reading width has said otherwise, and
/// re-imposing it would silently ignore the drag.
({double middle, double detail}) resolvedColumnWidths(
  double available,
  double? manualMiddle,
) {
  if (manualMiddle == null) return threeColumnWidths(available);

  final middle = manualMiddle
      .clamp(kSectionColumnMinWidth, maxDraggableMiddleWidth(available))
      .toDouble();
  return (middle: middle, detail: available - middle);
}

/// Where one piece of the tablet shell sits: its left edge, and how wide it is.
typedef ShellSlot = ({double left, double width});

/// The five pieces of the three-column layout, named for what they are rather
/// than ordered by where they appear — which side each ends up on is exactly
/// what [threeColumnSlots]' `swapped` decides.
typedef ThreeColumnSlots = ({
  ShellSlot bar,
  ShellSlot rule,
  ShellSlot content,
  ShellSlot divider,
  ShellSlot detail,
});

/// The three pieces of the rail layout.
typedef RailSlots = ({ShellSlot bar, ShellSlot rule, ShellSlot content});

/// Reflects a slot about the middle of a shell [total] wide.
///
/// This line is the entire definition of "swap sides", and keeping it to one
/// line is the point: the mirrored layout is never computed a second way, so
/// it cannot disagree with the normal one about a width, a gap, or which rule
/// belongs to which column. Only the reflection can be wrong, and it is
/// wrong or right for all five pieces at once.
double mirrorLeft(double left, double width, double total) =>
    total - left - width;

/// Where the three-column layout's pieces go, given the column widths
/// [resolvedColumnWidths] chose.
///
/// The bar is pinned to a screen edge, *outside* the centred group — the same
/// arrangement the Row had and for the same reason: on a wide tablet the
/// leftover width belongs beside the content, not between the navigation and
/// the edge of the display. Mirroring moves the bar to the other edge and
/// takes the margin with it, rather than trapping it behind the bar.
ThreeColumnSlots threeColumnSlots({
  required double total,
  required double middleWidth,
  required double detailWidth,
  required bool swapped,
}) {
  const ruleWidth = 1.0;
  const regionStart = kSectionsColumnWidth + ruleWidth;

  // What Center used to do: the two columns and their handle sit in the
  // middle of whatever is left beside the bar. A dragged divider makes the
  // group exactly as wide as that space, so the gutter goes to zero and the
  // composition fills the display — which is why the bar appeared to snap
  // flush on first interaction before it was moved out of the group.
  final group = middleWidth + kResizeHandleWidth + detailWidth;
  final gutter = math.max(0.0, (total - regionStart - group) / 2);

  final contentLeft = regionStart + gutter;
  final dividerLeft = contentLeft + middleWidth;

  ShellSlot at(double left, double width) => (
        left: swapped ? mirrorLeft(left, width, total) : left,
        width: width,
      );

  return (
    bar: at(0, kSectionsColumnWidth),
    rule: at(kSectionsColumnWidth, ruleWidth),
    content: at(contentLeft, middleWidth),
    divider: at(dividerLeft, kResizeHandleWidth),
    detail: at(dividerLeft + kResizeHandleWidth, detailWidth),
  );
}

/// Where the rail layout's pieces go.
///
/// [barWidth] is measured rather than assumed. A [NavigationRail] sizes
/// itself to its widest child, and this app puts the section actions in its
/// `trailing` slot — those are phrases where the destinations are single
/// words, so the rail is not the 80dp Flutter's default suggests.
RailSlots railSlots({
  required double total,
  required double barWidth,
  required bool swapped,
}) {
  const ruleWidth = 1.0;

  // A rail is as wide as its widest label, and labels grow with the locale
  // and the font scale. Nothing guarantees one fits, and a content column of
  // negative width is not a cramped layout, it is a crash.
  final bar = math.min(barWidth, total);
  final content = math.max(0.0, total - bar - ruleWidth);

  ShellSlot at(double left, double width) => (
        left: swapped ? mirrorLeft(left, width, total) : left,
        width: width,
      );

  return (
    bar: at(0, bar),
    rule: at(bar, ruleWidth),
    content: at(bar + ruleWidth, content),
  );
}

/// The constraints the navigation bar is measured under.
///
/// **The width is unbounded, and it has to be.** [NavigationRail] aligns its
/// destinations with an [Align], and an Align with no size factor fills its
/// constraints whenever they are bounded — so handing the rail a bounded
/// maxWidth makes it as wide as whatever it is given. At the 600dp rail
/// boundary that meant the rail took the entire display and the content column
/// was left with nothing: four labels centred on an empty screen.
///
/// Unbounded is also simply what the [Row] this replaced did. A Row lays its
/// non-flexible children out with an infinite main-axis constraint, which is
/// why the rail shrink-wrapped there. Reproducing that exactly is the whole
/// requirement: swapping sides must not change how anything is sized.
BoxConstraints barMeasurementConstraints(double height) =>
    BoxConstraints(minHeight: height, maxHeight: height);

/// How far a horizontal drag on the divider moves the article list's edge.
///
/// Swapped, the list sits to the *right* of the reading pane, so the same
/// gesture has to mean the opposite thing: drag right and the list gives up
/// width instead of gaining it. Without this the handle runs away from the
/// finger — the kind of bug that is obvious the instant anyone touches it and
/// invisible in any amount of reading.
double dividerDragDelta(double dx, {required bool swapped}) =>
    swapped ? -dx : dx;

/// A column rule that stops below the status bar.
///
/// The app draws edge-to-edge, which is the current platform guidance and
/// stays. What that guidance also says is that going edge-to-edge must not
/// let content collide with the system bars -- and a decorative hairline
/// running up through the clock is exactly that collision. The background
/// still goes to the top of the display; only the rule stops short of it.
///
/// Both column boundaries use this. Insetting one and not the other would
/// just be a different inconsistency, noticed later.
class _ColumnRule extends StatelessWidget {
  /// The rule itself, so the draggable divider can put its own line here.
  final Widget child;

  const _ColumnRule({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: child,
      );
}

/// The draggable boundary between the article list and the reading pane.
///
/// Renders as the same 1dp rule the static [VerticalDivider] did, sat inside
/// a [kResizeHandleWidth]-wide transparent grab area — a 1dp target is not
/// something anyone hits on a touchscreen, and widening the visible line
/// instead would put a heavy bar between two columns that want to read as
/// adjacent.
///
/// The grip dots and the resize cursor are what say "this moves" — without
/// some cue it is indistinguishable from the static rule it replaced. Double
/// tap returns to the automatic split, the same gesture desktop split-panes
/// have used for this for years.
class _ResizableDivider extends StatelessWidget {
  /// Horizontal drag distance since the last update, positive to the right.
  final ValueChanged<double> onDrag;

  /// Double tap: back to the automatic split.
  final VoidCallback onReset;

  const _ResizableDivider({required this.onDrag, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final line = theme.dividerColor;
    final grip = theme.colorScheme.onSurface.withValues(alpha: 0.35);

    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        // Opaque, so the whole grab area takes the gesture rather than only
        // the pixels the line is painted on.
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onDoubleTap: onReset,
        child: SizedBox(
          width: kResizeHandleWidth,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _ColumnRule(child: Container(width: 1, color: line)),
              // Four dots rather than a solid bar: enough to read as a grip
              // at a glance, not enough to become furniture.
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(height: 3),
                    Container(
                      width: 3,
                      height: 3,
                      decoration:
                          BoxDecoration(color: grip, shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which piece of the shell a laid-out child is.
///
/// The rail tier uses three of these and the three-column tier all five; the
/// names are the same in both so the two delegates read as the same idea at
/// two sizes.
enum _Shell { bar, rule, content, divider, detail }

/// Lays the three-column shell out by position instead of by order.
///
/// This is the whole reason the layout is not a [Row]. Swapping sides by
/// reordering a Row's children would hand every column a new slot in the
/// child list, and Flutter matches elements to children by position — so the
/// article list would be offered the reading pane's element, both would be
/// discarded, and the feed would silently reload, lose its scroll position
/// and drop whatever article was open. The children below never change
/// order. Only where they are put changes.
///
/// It is also what makes the slide cost nothing: [MultiChildLayoutDelegate]'s
/// `relayout` hook re-runs layout on every tick of the animation without
/// rebuilding a single widget.
class _ThreeColumnShellLayout extends MultiChildLayoutDelegate {
  _ThreeColumnShellLayout({
    required this.swapProgress,
    required this.middleWidth,
    required this.detailWidth,
  }) : super(relayout: swapProgress);

  /// 0 is the normal order, 1 is mirrored, and everything between is the
  /// columns on their way across.
  final Animation<double> swapProgress;
  final double middleWidth;
  final double detailWidth;

  @override
  void performLayout(Size size) {
    final normal = threeColumnSlots(
      total: size.width,
      middleWidth: middleWidth,
      detailWidth: detailWidth,
      swapped: false,
    );
    final mirrored = threeColumnSlots(
      total: size.width,
      middleWidth: middleWidth,
      detailWidth: detailWidth,
      swapped: true,
    );
    final t = swapProgress.value;

    void place(_Shell id, ShellSlot from, ShellSlot to) {
      layoutChild(id, BoxConstraints.tight(Size(from.width, size.height)));
      positionChild(id, Offset(from.left + (to.left - from.left) * t, 0));
    }

    place(_Shell.bar, normal.bar, mirrored.bar);
    place(_Shell.rule, normal.rule, mirrored.rule);
    place(_Shell.content, normal.content, mirrored.content);
    place(_Shell.divider, normal.divider, mirrored.divider);
    place(_Shell.detail, normal.detail, mirrored.detail);
  }

  @override
  bool shouldRelayout(_ThreeColumnShellLayout old) =>
      old.middleWidth != middleWidth ||
      old.detailWidth != detailWidth ||
      old.swapProgress != swapProgress;
}

/// The same idea one tier down, where the bar is a [NavigationRail].
///
/// The rail is measured rather than told a width: it sizes itself to its
/// widest child, and this app puts the section actions in its `trailing`
/// slot, so it is not the 80dp a bare rail would be.
class _RailShellLayout extends MultiChildLayoutDelegate {
  _RailShellLayout({required this.swapProgress})
      : super(relayout: swapProgress);

  final Animation<double> swapProgress;

  @override
  void performLayout(Size size) {
    // The rail is measured, not told — and measured unbounded. See
    // barMeasurementConstraints: a bounded width makes the rail fill it.
    final bar = layoutChild(
      _Shell.bar,
      barMeasurementConstraints(size.height),
    );

    final normal =
        railSlots(total: size.width, barWidth: bar.width, swapped: false);
    final mirrored =
        railSlots(total: size.width, barWidth: bar.width, swapped: true);
    final t = swapProgress.value;

    double slide(ShellSlot from, ShellSlot to) =>
        from.left + (to.left - from.left) * t;

    positionChild(_Shell.bar, Offset(slide(normal.bar, mirrored.bar), 0));

    void place(_Shell id, ShellSlot from, ShellSlot to) {
      layoutChild(id, BoxConstraints.tight(Size(from.width, size.height)));
      positionChild(id, Offset(slide(from, to), 0));
    }

    place(_Shell.rule, normal.rule, mirrored.rule);
    place(_Shell.content, normal.content, mirrored.content);
  }

  @override
  bool shouldRelayout(_RailShellLayout old) =>
      old.swapProgress != swapProgress;
}

/// The rail and the button under it, inset from whichever edge they are
/// pinned to.
///
/// [NavigationRail] applies `SafeArea(left: true, right: false)` of its own,
/// which is exactly right flush left and exactly wrong flush right — mirrored,
/// its icons would sit under a display cutout. So the [MediaQuery] below hands
/// it only the top inset, which is the one it should still handle itself, and
/// the horizontal and bottom insets are applied out here where the Swap sides
/// button is also in scope. The [ColoredBox] keeps the rail's background
/// running under the inset and behind the button, which the internal SafeArea
/// did for free by sitting inside the rail's own [Material].
class _RailColumn extends StatelessWidget {
  final bool swapped;
  final Widget rail;

  /// Null on TV, and during onboarding there is no rail at all.
  final VoidCallback? onSwapSides;

  const _RailColumn({
    required this.swapped,
    required this.rail,
    required this.onSwapSides,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final inset = swapped ? media.padding.right : media.padding.left;

    return ColoredBox(
      color: theme.navigationRailTheme.backgroundColor ??
          theme.colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.only(
          left: swapped ? 0 : inset,
          right: swapped ? inset : 0,
          bottom: media.padding.bottom,
        ),
        child: MediaQuery(
          data: media.copyWith(
            padding: EdgeInsets.only(top: media.padding.top),
          ),
          child: Column(
            children: [
              Expanded(child: rail),
              // At the bottom of the rail, not under the destinations: the
              // rail's own `trailing` slot already holds the section actions
              // directly beneath them, and this is not one of those.
              if (onSwapSides != null)
                _SwapSidesButton(compact: true, onPressed: onSwapSides!),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppShellState extends State<_AppShell>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  bool _onboardingComplete = true; // assume complete until checked
  int _alertsCount = 0;

  /// Which article the right-hand column is showing. Lives here, above the
  /// IndexedStack, so it outlives section switches — picking Bookmarks with
  /// an article open leaves the article open.
  final _detailController = ArticleDetailController();

  /// Where the reader has dragged the divider, or null for the automatic
  /// split.
  ///
  /// Session-scoped on purpose, like Alerts' collapsed-section state: it is
  /// a reading-position preference, not a setting, and it costs nothing to
  /// re-drag. Persisting it would mean a Settings entry and a migration for
  /// something worth neither yet.
  double? _manualMiddleWidth;

  /// Which side the navigation bar is on.
  ///
  /// Persisted, where [_manualMiddleWidth] deliberately is not: a dragged
  /// divider is a reading position and costs one gesture to re-make, but
  /// handedness does not change between launches, and a layout that un-swaps
  /// itself every morning would be worse than not offering the choice.
  bool _layoutSwapped = false;

  /// Drives the slide: 0 is the normal order, 1 is mirrored.
  ///
  /// Set outright rather than animated when the saved side is restored at
  /// launch, and when the platform has animations turned off.
  late final AnimationController _swapController;
  late final CurvedAnimation _swapProgress;

  // Incremented each time the Feed tab is tapped while already on Feed —
  // triggers a reload via didUpdateWidget without remounting FeedScreen.
  int _feedRefreshTrigger = 0;

  @override
  void initState() {
    super.initState();
    _swapController =
        AnimationController(vsync: this, duration: kPageTransitionDuration);
    _swapProgress =
        CurvedAnimation(parent: _swapController, curve: Easing.standard);
    _checkOnboarding();
    _restoreLayoutSide();
    AlertNavigationIntent.instance.addListener(_onAlertsRequested);
    AlertsChangedNotifier.instance.addListener(_refreshAlertsCount);
    _refreshAlertsCount();
  }

  @override
  void dispose() {
    AlertNavigationIntent.instance.removeListener(_onAlertsRequested);
    AlertsChangedNotifier.instance.removeListener(_refreshAlertsCount);
    _detailController.dispose();
    _swapProgress.dispose();
    _swapController.dispose();
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
    _setCurrentIndex(kAlertsNavIndex);
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

  /// Puts the bar back where the reader left it, without animating there.
  ///
  /// TV is skipped rather than clamped: it has no Swap sides button, so a
  /// true here could only have arrived from a backup taken on a tablet, and
  /// honouring it would mirror a layout with no control to mirror back.
  Future<void> _restoreLayoutSide() async {
    if (FormFactor.isTV) return;
    final swapped =
        (await SettingsRepository().get('layout_swapped')) == 'true';
    if (!mounted || !swapped) return;
    setState(() => _layoutSwapped = true);
    // Not forward(): the layout was already this way round when the app was
    // closed, so there is nothing to show moving.
    _swapController.value = 1;
  }

  /// Mirror the layout, and remember which way round it ended up.
  void _toggleLayoutSide() {
    final swapped = !_layoutSwapped;
    setState(() => _layoutSwapped = swapped);

    if (MediaQuery.disableAnimationsOf(context)) {
      _swapController.value = swapped ? 1 : 0;
    } else if (swapped) {
      _swapController.forward();
    } else {
      _swapController.reverse();
    }

    // Not awaited: the columns are already moving, and the write has nothing
    // to tell them.
    unawaited(SettingsRepository()
        .set('layout_swapped', swapped ? 'true' : 'false'));
  }

  Future<void> _checkOnboarding() async {
    final complete =
        (await SettingsRepository().get('onboarding_complete')) == 'true';
    if (mounted && !complete) setState(() => _onboardingComplete = false);
  }

  /// Onboarding is over. Where the user lands depends on whether they took
  /// the starter pack.
  ///
  /// With it, they stay on Flash — it is about to fill with articles, and
  /// sending them to Categories to admire a list of folders would put the
  /// original "where is the news?" problem back one screen along. Without it,
  /// Categories is still the only screen with anything to do on it, so the
  /// old behaviour is kept exactly.
  ///
  /// Note the with-pack branch sets no index at all, and that is not an
  /// omission: `_currentIndex` is already 0 on a first run and
  /// `SectionActionsController` already starts on `kSectionFlash`, so
  /// selecting Flash again would be a no-op — one that
  /// section_index_single_writer_test.dart counts, and would fail on.
  void _finishOnboarding({required bool withStarterPack}) {
    setState(() => _onboardingComplete = true);

    if (withStarterPack) {
      // Drop the queued change rather than letting it fetch.
      //
      // Seeding inserted feeds, and FeedRepository.insert pings
      // FeedsChangedNotifier from inside — so a needsFetch is now queued. But
      // the branch above is what puts the IndexedStack into the tree for the
      // first time, so FeedScreen mounts fresh, and its initState runs _boot,
      // which ends in _backgroundRefresh. That is the fetch. Leaving the
      // queued change in place would buy a second, identical one the next
      // time the user came back to this tab.
      FeedsChangedNotifier.instance.reset();
      return;
    }

    _setCurrentIndex(1); // straight to Feeds, to add the first feed
  }

  /// The one way to change which section is showing.
  ///
  /// The sidebar's contextual actions are keyed by section, so the controller
  /// has to be told every time the section changes. It used to be told from
  /// `_navigateTo` alone, which left four other ways of moving between
  /// sections — both back presses, an alert notification, the end of
  /// onboarding — changing the screen without changing the actions beside it.
  /// Routing every mutation through here is what stops a sixth caller
  /// reintroducing that: there is no longer a version of this that only does
  /// half the job.
  void _setCurrentIndex(int index) {
    if (!mounted) return;
    setState(() => _currentIndex = index);
    SectionActionsController.instance.selectSection(index);
  }

  void _navigateTo(int index) {
    if (index == 0 && _currentIndex == 0) {
      // Already on Feed tab — trigger reload without remounting
      setState(() => _feedRefreshTrigger++);
      return;
    }
    _setCurrentIndex(index);
    // Cheap, and it is the moment the number is about to be looked at.
    unawaited(_refreshAlertsCount());
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
    // TV keeps the rail whatever its width: it is a 10-foot UI driven by a
    // d-pad, not a tablet you reach out and touch, and a reading pane it
    // cannot scroll comfortably is not an improvement there.
    final useThreeColumn =
        !isTV && _onboardingComplete && width >= kThreeColumnBreakpoint;
    final useRail = !useThreeColumn && (isTV || width >= 600);
    // TV is never mirrored. It is a d-pad UI with no Swap sides button,
    // so a swapped layout there would be one nobody could put back.
    final swapped = _layoutSwapped && !isTV;

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

    if (useThreeColumn) {
      // What the bar, its rule and the drag handle take before the two
      // content columns divide the rest. Past their combined preferred width
      // the sum stops growing and the remainder becomes equal margins either
      // side of the group — see kDetailPaneMaxWidth, and threeColumnSlots,
      // which is where that centring now lives.
      const chrome = kSectionsColumnWidth + 1 + kResizeHandleWidth;
      final available = width - chrome;
      final columns = resolvedColumnWidths(available, _manualMiddleWidth);

      // Clamped as it is stored, not only as it is read: without this a drag
      // that keeps pushing past a floor banks the overshoot, and the divider
      // then sits still for the first inch of the drag back.
      void dragDivider(double dx) {
        setState(() {
          _manualMiddleWidth = ((_manualMiddleWidth ?? columns.middle) +
                  dividerDragDelta(dx, swapped: swapped))
              .clamp(kSectionColumnMinWidth, maxDraggableMiddleWidth(available))
              .toDouble();
        });
      }

      return PopScope(
        // Same reasoning as the two branches below: canPop stays false so
        // every back press arrives here and is answered in order.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (dismissTopBubblePanel()) return;
          // The reading pane is the innermost thing open, so it closes first.
          if (_detailController.article != null) {
            _detailController.clear();
            return;
          }
          if (_currentIndex != 0) {
            _setCurrentIndex(0);
            return;
          }
          SystemNavigator.pop();
        },
        child: SectionActionsHost(
          child: ArticleDetailScope(
            controller: _detailController,
            child: Scaffold(
              // Positions, not order — see _ThreeColumnShellLayout. The bar
              // is still pinned to a screen edge outside the centred group,
              // which is what threeColumnSlots encodes: it used to sit inside
              // it, which put the whole wide-screen margin to its left, and on
              // a 1707dp tablet the composition caps at ~1385dp so the rail
              // began 161dp in. Since the margin is the same colour as the
              // rail, that read as one enormous gutter.
              body: CustomMultiChildLayout(
                delegate: _ThreeColumnShellLayout(
                  swapProgress: _swapProgress,
                  middleWidth: columns.middle,
                  detailWidth: columns.detail,
                ),
                // This order is fixed and has to stay fixed: it is what keeps
                // the feed, the open article and the reading pane from being
                // torn down and rebuilt every time the sides are swapped.
                // Painting runs content first and the bar last, so while the
                // two cross, the bar slides over the columns rather than
                // vanishing behind them.
                children: [
                  LayoutId(id: _Shell.content, child: _buildScreenStack()),
                  LayoutId(
                    id: _Shell.divider,
                    child: _ResizableDivider(
                      onDrag: dragDivider,
                      onReset: () =>
                          setState(() => _manualMiddleWidth = null),
                    ),
                  ),
                  LayoutId(
                    id: _Shell.detail,
                    child: AnimatedBuilder(
                      animation: _detailController,
                      builder: (context, _) {
                        final article = _detailController.article;
                        if (article == null) {
                          return const ArticleDetailPlaceholder();
                        }
                        return ArticleDetailPane(
                          article: article,
                          onClose: _detailController.clear,
                        );
                      },
                    ),
                  ),
                  LayoutId(
                    id: _Shell.rule,
                    child: const _ColumnRule(
                        child: VerticalDivider(thickness: 1, width: 1)),
                  ),
                  LayoutId(
                    id: _Shell.bar,
                    child: _SectionsColumn(
                      currentIndex: _currentIndex,
                      onSelected: _navigateTo,
                      alertsCount: _alertsCount,
                      swapped: swapped,
                      // Never TV here: useThreeColumn rules it out above.
                      onSwapSides: _toggleLayoutSide,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (useRail) {
      // Onboarding has no bar to put on either side, so the screen takes the
      // whole width until it is done — as it always has.
      final Widget body = _onboardingComplete
          ? CustomMultiChildLayout(
              delegate: _RailShellLayout(swapProgress: _swapProgress),
              // Fixed order, for the same reason as the tier above.
              children: [
                LayoutId(id: _Shell.content, child: _buildScreenStack()),
                LayoutId(
                  id: _Shell.rule,
                  child: const _ColumnRule(
                      child: VerticalDivider(thickness: 1, width: 1)),
                ),
                LayoutId(
                  id: _Shell.bar,
                  child: _RailColumn(
                    swapped: swapped,
                    onSwapSides: isTV ? null : _toggleLayoutSide,
                    rail: NavigationRail(
                      selectedIndex: _currentIndex,
                      onDestinationSelected: _navigateTo,
                      extended: isTV,
                      labelType: isTV
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      destinations: railDestinations,
                      // NavigationRail lays its children out in a Column and
                      // gives `trailing` whatever height it asks for, so this
                      // has to be a single self-sizing widget rather than
                      // something that expects to fill the rail. Compact
                      // spacing because the destinations above it are already
                      // taller here than in the custom sidebar.
                      trailing: const SectionActionsList(compact: true),
                    ),
                  ),
                ),
              ],
            )
          : _buildScreenStack();

      Widget shell = SectionActionsHost(child: Scaffold(body: body));

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
        // Never true, deliberately. Flutter evaluates canPop *before* calling
        // the callback, so the old `_currentIndex == 0` handed the pop away on
        // the one tab that needed the callback most: Quick Settings and Filter
        // open from Flash, which is index 0, so back closed the app with the
        // panel still on screen and `didPop: true` made the callback return
        // before it could ask. With canPop false every back press arrives here
        // and is answered in order — including the exit, which is now ours to
        // perform.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // A bubble panel is an overlay, not a route, so it cannot answer a
          // back press itself — without this the tab would change underneath
          // an open panel. Asked first, and swallowed if one was closed.
          if (dismissTopBubblePanel()) return;
          if (_currentIndex != 0) {
            _setCurrentIndex(0);
            return;
          }
          // On Flash with nothing open, back means leave. Explicit because
          // canPop: false means Flutter did not do it for us.
          SystemNavigator.pop();
        },
        child: shell,
      );
    }

    // Phone: classic bottom navigation bar
    return PopScope(
      // False for the same reason as the rail branch above — see the comment
      // there. Same bug, same fix, and they have to stay in step.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (dismissTopBubblePanel()) return;
        if (_currentIndex != 0) {
          _setCurrentIndex(0);
          return;
        }
        SystemNavigator.pop();
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
