import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/folder.dart';
import '../theme/app_theme.dart';
import '../theme/category_colors.dart';

/// Category chips under the app bar title. Implements [PreferredSizeWidget]
/// so it can sit in `AppBar.bottom`, where the mock puts it.
///
/// **This is where `category_colors.dart` finally gets used.** Pass 1 built the
/// six-hue table and wired it to nothing; `Folder.colorIndex` has been carried
/// through the database, the model and this widget's `folders` list since then
/// without anything reading it. An unselected chip is now tinted with its own
/// category's hue, which is the same hue the row ticks and the Categories
/// blocks use, so the three agree by construction rather than by somebody
/// remembering to keep them in step.
///
/// **Two things carry over from the round-pill version and must not be lost.**
/// The 36dp target floor, which is below Material's 48 and always has been —
/// the row is tuned to fit four chips across a phone, so raising it is a design
/// change rather than a bug fix. And long-press a chip to mark that category
/// read, which has no visible affordance at all and is therefore the easiest
/// thing in this file to delete by accident. Both are pinned in
/// `folder_tab_bar_test.dart`; the long-press was not covered before this
/// rewrite and now is.
class FolderTabBar extends StatefulWidget implements PreferredSizeWidget {
  static const double barHeight = 56.0;

  /// How wide each edge fade is.
  ///
  /// Wide enough to read as a soft edge rather than a hard line, narrow enough
  /// that it never covers a whole chip — the narrowest chip is 72dp
  /// ([_FolderTab._minWidth]), so a partly covered chip still shows more than
  /// half of itself.
  static const double edgeFadeWidth = 32.0;

  /// Matches the chip's own selection animation directly below, and the
  /// banner slide, and the switch. A fourth tempo for a fourth thing is how an
  /// app stops feeling like one app.
  static const Duration edgeFadeDuration = Duration(milliseconds: 200);

  @override
  Size get preferredSize => const Size.fromHeight(barHeight);

  final List<Folder> folders;
  final int selectedIndex; // 0 = All, 1..n = folders[index - 1]
  final Map<int, int> folderUnreadCounts;
  final int allUnreadCount;
  final ValueChanged<int> onTabSelected;
  final VoidCallback? onMarkAllRead;

  const FolderTabBar({
    super.key,
    required this.folders,
    required this.selectedIndex,
    required this.folderUnreadCounts,
    required this.allUnreadCount,
    required this.onTabSelected,
    this.onMarkAllRead,
  });

  @override
  State<FolderTabBar> createState() => _FolderTabBarState();
}

class _FolderTabBarState extends State<FolderTabBar> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _tabKeys = {};

  /// Whether there is anything past each edge.
  ///
  /// **Both start false and that is the correct resting state**, not a
  /// placeholder: a bar whose chips all fit has nothing past either edge and
  /// must show neither fade. An always-on fade is worse than no fade, because
  /// it is an affordance that lies — it promises more to the side every time
  /// anyone looks, including when there is nothing there.
  bool _fadeAtStart = false;
  bool _fadeAtEnd = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateEdgeFades);
    // Nothing has been laid out yet, so the controller has no position to ask.
    // The first honest answer is available at the end of this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdgeFades());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateEdgeFades);
    _scrollController.dispose();
    super.dispose();
  }

  /// Recomputes both edges from the scroll POSITION, which is the whole point.
  ///
  /// Not from whether a scroll is happening — that is what
  /// `ScrollFadeController` answers for the floating buttons, and it is a
  /// different question with a different answer. This one is "is there
  /// anything over there", and it has to be true while the finger is nowhere
  /// near the screen.
  void _updateEdgeFades() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Half a pixel, because a position that has settled exactly at an extent
    // can sit a rounding error away from it and flicker the fade on and off.
    const double epsilon = 0.5;
    final atStart = position.pixels > position.minScrollExtent + epsilon;
    final atEnd = position.pixels < position.maxScrollExtent - epsilon;
    if (atStart == _fadeAtStart && atEnd == _fadeAtEnd) return;
    setState(() {
      _fadeAtStart = atStart;
      _fadeAtEnd = atEnd;
    });
  }

  @override
  void didUpdateWidget(FolderTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // **The folder count is part of the condition, not just the index.**
    // A category created at the end of the list arrives as a chip that did
    // not exist in the previous build, and the selection can move onto it
    // while the index it is given happens to be one nothing was watching. A
    // condition reading only `selectedIndex` never fires for that case, and
    // the new chip stays parked off the right-hand edge of a bar that gives
    // no sign it scrolls — which is what "the category disappeared" actually
    // was.
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.folders.length != widget.folders.length) {
      _scrollToSelected();
    }
    // A chip added or removed changes maxScrollExtent without anybody
    // scrolling, so the listener above never fires for it. Deleting the
    // category that was making the bar overflow is exactly the case: the fade
    // has to go away, and nothing else would have told it to.
    if (oldWidget.folders.length != widget.folders.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdgeFades());
    }
  }

  GlobalKey _keyFor(int i) => _tabKeys.putIfAbsent(i, GlobalKey.new);

  /// Brings the selected chip into view **after the frame that builds it**.
  ///
  /// The post-frame callback is the entire fix, not a precaution.
  /// `didUpdateWidget` runs before `build`, so for a chip that has just
  /// appeared `_tabKeys` has no entry yet — it is populated inside `build` by
  /// [_keyFor] — and even with a key there would be no element and no
  /// geometry to aim at. Called synchronously, this hits the null guard below
  /// and does nothing at all, silently, which is the worst possible way for
  /// it to fail: the code reads as though it scrolls.
  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _tabKeys[widget.selectedIndex]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final tabs = <_TabItem>[
      // "All" is not a category and has no hue. It takes a neutral tint when
      // unselected — see [_FolderTab].
      _TabItem(label: l10n.allTab, count: widget.allUnreadCount),
      ...widget.folders.map((f) => _TabItem(
            label: f.name,
            count: widget.folderUnreadCounts[f.id] ?? 0,
            colorIndex: f.colorIndex,
          )),
    ];

    // **The colour the fade fades TO, taken from the theme rather than
    // assumed.** This widget lives in `AppBar.bottom` and paints no background
    // of its own, so the surface behind it is the app bar's: white in Quiet
    // Ink light, #0D1211 in Quiet Ink dark, #F2F1EE newsprint in Newspaper. A
    // fade hardcoded to white would be a grey smudge on newsprint and a pale
    // bruise in the dark, which is the specific way this goes wrong.
    final ThemeData theme = Theme.of(context);
    final Color surface =
        theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface;

    // Transparent: this lives in AppBar.bottom, and the app bar paints the
    // background.
    return SizedBox(
      height: FolderTabBar.barHeight,
      // Metrics change without anyone scrolling -- a window resize, a chip
      // whose count grew a digit -- and the controller listener does not fire
      // for those. This does.
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _updateEdgeFades());
          return false;
        },
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: List.generate(tabs.length, (i) {
                  final tab = tabs[i];
                  return _FolderTab(
                    key: ValueKey('folder_tab_$i'),
                    tabKey: _keyFor(i),
                    label: tab.label,
                    count: tab.count,
                    colorIndex: tab.colorIndex,
                    isSelected: i == widget.selectedIndex,
                    onTap: () => widget.onTabSelected(i),
                    onLongPress: widget.onMarkAllRead,
                  );
                }),
              ),
            ),
            _EdgeFade(visible: _fadeAtStart, atStart: true, surface: surface),
            _EdgeFade(visible: _fadeAtEnd, atStart: false, surface: surface),
          ],
        ),
      ),
    );
  }
}

/// One edge's fade: a strip of the surface colour dissolving into nothing.
///
/// **It never takes a tap.** The chip under it is a chip the user can see and
/// is reaching for; a decoration that swallowed that tap would be a worse bug
/// than the missing affordance this exists to fix. [IgnorePointer] is the
/// whole of the fix and `folder_tab_bar_fade_test.dart` taps the chip nearest
/// each edge to prove it.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({
    required this.visible,
    required this.atStart,
    required this.surface,
  });

  final bool visible;
  final bool atStart;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      top: 0,
      bottom: 0,
      start: atStart ? 0 : null,
      end: atStart ? null : 0,
      width: FolderTabBar.edgeFadeWidth,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: FolderTabBar.edgeFadeDuration,
          curve: Curves.easeOut,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                // Opaque against the outer edge, gone by the inner one.
                colors: atStart
                    ? [surface, surface.withValues(alpha: 0)]
                    : [surface.withValues(alpha: 0), surface],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem {
  final String label;
  final int count;

  /// The category's hue index, or null for "All", which is not a category.
  final int? colorIndex;

  const _TabItem({required this.label, required this.count, this.colorIndex});
}

class _FolderTab extends StatelessWidget {
  final GlobalKey tabKey;
  final String label;
  final int count;
  final int? colorIndex;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FolderTab({
    required super.key,
    required this.tabKey,
    required this.label,
    required this.count,
    required this.colorIndex,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  /// The chip's own geometry. 9dp corners rather than the r999 this replaced:
  /// a rounded rectangle reads as a filter, a full pill reads as a tag.
  static const double _radius = 9;
  static const double _height = 36;

  /// Selected chips carry 1dp more side padding than unselected ones. That is
  /// the mock's number, and it is not arbitrary — the label goes from w500 to
  /// w600 when selected, and the heavier face needs the extra dp to sit as
  /// comfortably inside the fill.
  static const double _selectedPadding = 13;
  static const double _unselectedPadding = 12;

  /// Below Material's 48dp, deliberately, and unchanged from the pill this
  /// replaced. See the class comment on [FolderTabBar].
  static const double _minWidth = 72;

  static const double _labelSize = 13;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // "All" has no category, so it has no hue. It takes the neutral container
    // tone instead of borrowing a category's colour, which would make the
    // aggregate look like one more category. The mock does not draw this state
    // — every unselected chip in it is a real category — so the neutral is an
    // inference, flagged as one.
    // Newspaper identifies its sections by name, not by colour, so it opts out
    // of hue entirely rather than being given six greys — which would be a
    // colour system with the colour removed. Every tone below is one the theme
    // already owns: no new token, and nothing for Design to supply.
    final bool mono = theme.flashColors.monochromeCategories;

    final CategoryPalette? palette = (mono || colorIndex == null)
        ? null
        : theme.flashColors.category(colorIndex!);

    final Color background = isSelected
        // Ink fill. Not `primary`, which in Newspaper is the red spot colour
        // already carrying the nav selection, the FAB and the masthead.
        ? (mono ? scheme.onSurface : scheme.primary)
        : (mono
            // The paper tint. `surfaceContainerHighest` rather than
            // `surfaceContainer`, because Newspaper authors the former
            // (_npSurface2) and inherits the latter from Material.
            ? scheme.surfaceContainerHighest
            : (palette?.chipBackground ?? scheme.surfaceContainer));

    final Color foreground = isSelected
        ? (mono ? scheme.surface : scheme.onPrimary)
        : (mono ? scheme.onSurface
            : (palette?.chipForeground ?? scheme.onSurfaceVariant));

    final label = Text(
      this.label,
      style: TextStyle(
        fontFamily: kSansFamily,
        fontSize: _labelSize,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        color: foreground,
      ),
    );

    // The count is its own widget now, not "(12)" inside the label string.
    //
    // Mono and tabular, so a chip does not twitch sideways as its count
    // changes width on refresh: "9" and "11" take the same advance. That is
    // what `kNumeralChipStyle` was declared for in pass 1 and never applied
    // to. It takes the label's colour rather than a colour of its own — a
    // count that can lose contrast against its own chip fill is exactly the
    // bug the old gold badge had, where a gold pill on a selected gold chip
    // was present in the layout and invisible on screen.
    final children = <Widget>[label];
    if (count > 0) {
      children
        ..add(const SizedBox(width: 6))
        ..add(Text(
          '$count',
          style: kNumeralChipStyle.copyWith(color: foreground),
        ));
    }

    // B3. Splitting "(12)" out of the label string fixed the layout and broke
    // the reading: two Text widgets side by side are two semantics nodes, so
    // TalkBack announced "Tech" and then, separately, "twelve" — a number with
    // nothing attached to it, and no way to tell it was a count of articles
    // rather than a position in a list.
    //
    // One label over the pair, with the visual text excluded so it is not
    // announced twice. The Semantics sits *inside* the InkWell on purpose:
    // outside it, or with `excludeSemantics` on the whole chip, the button
    // role and the tap action go with it.
    //
    // `articlesCount` is an existing key with all five locales, so this adds
    // no strings — the plural is the ARB's problem, not this widget's.
    //
    // **The count is omitted when it is zero**, rather than announced as
    // "0 articles": nothing is painted at zero, and a label describing a
    // numeral that is not on screen is its own small lie.
    final l10n = AppLocalizations.of(context)!;
    final semanticsLabel =
        count > 0 ? '${this.label}, ${l10n.articlesCount(count)}' : this.label;

    return Padding(
      key: tabKey,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          // No visible affordance, and none is wanted: a chip that advertised
          // "long-press to mark read" would carry more furniture than the
          // action deserves. That is exactly why it needs a test rather than a
          // reader's memory.
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(_radius),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            // Without this, a short label ("AI", "UK") padded out to _minWidth
            // by the target floor sits left-aligned in the extra space rather
            // than centred in it — Container only centres a child smaller than
            // its constraints when told to.
            alignment: Alignment.center,
            constraints: const BoxConstraints(
              minWidth: _minWidth,
              minHeight: _height,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isSelected ? _selectedPadding : _unselectedPadding,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(_radius),
            ),
            child: Semantics(
              label: semanticsLabel,
              child: ExcludeSemantics(
                child:
                    Row(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
