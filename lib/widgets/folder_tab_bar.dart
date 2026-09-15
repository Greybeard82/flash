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

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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

    // Transparent: this lives in AppBar.bottom, and the app bar paints the
    // background.
    return SizedBox(
      height: FolderTabBar.barHeight,
      child: SingleChildScrollView(
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
