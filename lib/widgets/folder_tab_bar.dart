import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/folder.dart';

/// Category pills under the app bar title. Implements [PreferredSizeWidget]
/// so it can sit in `AppBar.bottom`, where the mockup puts it.
class FolderTabBar extends StatefulWidget implements PreferredSizeWidget {
  static const double barHeight = 56.0;

  @override
  Size get preferredSize => const Size.fromHeight(barHeight);

  final List<Folder> folders;
  final int selectedIndex; // 0 = All, 1+ = folders[index-1]
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
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollToSelected();
    }
  }

  GlobalKey _keyFor(int i) => _tabKeys.putIfAbsent(i, GlobalKey.new);

  void _scrollToSelected() {
    final context = _tabKeys[widget.selectedIndex]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    final tabs = <_TabItem>[
      _TabItem(
        label: AppLocalizations.of(context)!.allTab,
        unreadCount: widget.allUnreadCount,
      ),
      ...widget.folders.map((f) => _TabItem(
            label: f.name,
            unreadCount: widget.folderUnreadCounts[f.id] ?? 0,
          )),
    ];

    // Transparent: this lives in AppBar.bottom now, and the app bar paints
    // the background.
    return SizedBox(
      height: FolderTabBar.barHeight,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final tab = tabs[i];
            final isSelected = i == widget.selectedIndex;
            return _FolderTab(
              key: ValueKey('folder_tab_$i'),
              tabKey: _keyFor(i),
              label: tab.label,
              unreadCount: tab.unreadCount,
              isSelected: isSelected,
              accent: accent,
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
  final int unreadCount;

  const _TabItem({required this.label, required this.unreadCount});
}

class _FolderTab extends StatelessWidget {
  final GlobalKey tabKey;
  final String label;
  final int unreadCount;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _FolderTab({
    required super.key,
    required this.tabKey,
    required this.label,
    required this.unreadCount,
    required this.isSelected,
    required this.accent,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Selected: solid accent with a dark label. Unselected: hairline outline,
    // no fill, muted label.
    final labelColor = isSelected
        ? scheme.onPrimary
        : scheme.onSurface.withValues(alpha: 0.6);

    return Padding(
      key: tabKey,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            // Without alignment, a short label ("AI", "UK") padded out to
            // minWidth by the pill's own tap-target floor sits left-aligned
            // in the extra space rather than centred in it — Container only
            // centres a child smaller than its constraints when told to.
            alignment: Alignment.center,
            constraints: const BoxConstraints(minWidth: 72, minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isSelected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isSelected ? accent : scheme.outline,
                width: 1,
              ),
            ),
            // Count inline, in the label's own colour and weight, as the
            // mockup shows: "World News (12)". The badge this replaced painted
            // its own gold pill, which on a selected (gold) chip was
            // gold-on-gold — present in the layout, invisible on screen. Text
            // drawn in the label colour cannot lose contrast against its own
            // background. The chip's width now follows the count; the old
            // fixed-width slot is gone with the badge.
            child: Text(
              unreadCount > 0 ? '$label ($unreadCount)' : label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: labelColor,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
