import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/folder.dart';
import 'unread_badge.dart';

class FolderTabBar extends StatefulWidget {
  static const double barHeight = 60.0;

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
    final surface = theme.colorScheme.surfaceContainerHighest;

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

    return Container(
      height: FolderTabBar.barHeight,
      color: surface,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
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
    final labelColor = isSelected
        ? accent
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Container(
      key: tabKey,
      constraints: const BoxConstraints(minWidth: 72, minHeight: 48),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 3,
                  width: isSelected ? 24 : 0,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: labelColor,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 4),
                      UnreadBadge(count: unreadCount, small: true),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
