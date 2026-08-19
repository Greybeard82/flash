import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/feed.dart';
import '../models/folder.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../services/favicon_service.dart';
import '../services/feedly_service.dart';
import '../services/loading_controller.dart';
import '../services/rss_service.dart';
import '../repositories/article_repository.dart';
import '../repositories/settings_repository.dart';
import '../widgets/feed_card.dart';
import '../l10n/app_localizations.dart';

class FeedsScreen extends StatefulWidget {
  const FeedsScreen({super.key});

  @override
  State<FeedsScreen> createState() => _FeedsScreenState();
}

class _FeedsScreenState extends State<FeedsScreen> {
  final _feedRepo = FeedRepository();
  final _folderRepo = FolderRepository();
  final _feedlyService = FeedlyService();
  final _faviconService = FaviconService();
  final _scrollController = ScrollController();
  final _listKey = GlobalKey();

  List<Folder> _folders = [];
  Map<int, List<Feed>> _feedsByFolder = {};
  Map<int, int> _unreadCounts = {};
  bool _loading = true;

  // Auto-scroll while a feed is being dragged near the top/bottom edge.
  Timer? _autoScrollTimer;

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // _load is the completion callback for the add-feed, edit-feed and folder
    // sheets, each of which awaits network and DB work first — so this can
    // fire after the user has already left the tab.
    if (!mounted) return;
    setState(() => _loading = true);
    final feeds = await _feedRepo.getAll();
    final folders = await _folderRepo.getAll();
    final counts = await _feedRepo.getUnreadCounts();
    if (mounted) {
      setState(() {
        _folders = folders;
        _unreadCounts = counts;
        // Every feed belongs to a real folder: feeds.folder_id is
        // NOT NULL REFERENCES folders(id) ON DELETE CASCADE, with foreign
        // keys enabled in AppDatabase._initDatabase, so a feed can never
        // outlive its folder and there is no uncategorised bucket to build.
        final byFolder = <int, List<Feed>>{};
        for (final feed in feeds) {
          byFolder.putIfAbsent(feed.folderId, () => []).add(feed);
        }
        _feedsByFolder = byFolder;
        _loading = false;
      });
    }
  }

  // ── Drag and drop across categories ──────────────────────────────────────

  /// Moves [feed] into [targetFolderId] at [targetIndex] within that
  /// folder's list. Works for both a cross-category move (folder changes)
  /// and a same-category reorder (folder unchanged) — in both cases the
  /// destination list is renumbered 0..n-1 and persisted in one batch.
  ///
  /// [targetIndex] is expressed against the destination list *as currently
  /// rendered* (i.e. still including [feed] if it's a same-folder reorder),
  /// matching ReorderableListView's own convention — so a same-folder drop
  /// past the feed's original position is adjusted back by one to land in
  /// the intended slot once the feed is removed from its old spot first.
  void _moveFeed(Feed feed, int targetFolderId, int targetIndex) {
    final sourceFolderId = feed.folderId;
    final destList = List<Feed>.of(_feedsByFolder[targetFolderId] ?? []);

    var index = targetIndex;
    if (sourceFolderId == targetFolderId) {
      final originalIndex = destList.indexWhere((f) => f.id == feed.id);
      if (originalIndex != -1 && targetIndex > originalIndex) index--;
    }
    destList.removeWhere((f) => f.id == feed.id);
    final clamped = index.clamp(0, destList.length);
    final moved = feed.copyWith(folderId: targetFolderId);
    destList.insert(clamped, moved);

    setState(() {
      if (sourceFolderId != targetFolderId) {
        final sourceList = List<Feed>.of(_feedsByFolder[sourceFolderId] ?? [])
          ..removeWhere((f) => f.id == feed.id);
        _feedsByFolder[sourceFolderId] = sourceList;
      }
      _feedsByFolder[targetFolderId] = destList;
    });

    // The UI has already committed the move optimistically. If the write
    // fails, reload from the DB so the list can't keep showing an
    // arrangement that was never persisted.
    unawaited(_persistMove(moved, targetFolderId, destList));
  }

  Future<void> _persistMove(
    Feed feed,
    int targetFolderId,
    List<Feed> destList,
  ) async {
    try {
      await LoadingController.instance.run(
        () => _feedRepo.moveToFolder(feed, targetFolderId, destList),
        label: 'Moving feed',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.moveFeedFailed)),
      );
      await _load();
    }
  }

  void _onFeedDragStarted() => HapticFeedback.mediumImpact();

  void _onFeedDragEnd() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
  }

  void _onFeedDragUpdate(DragUpdateDetails details) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !_scrollController.hasClients) return;
    final local = box.globalToLocal(details.globalPosition);
    const edge = 56.0;
    final height = box.size.height;

    double direction = 0;
    if (local.dy < edge && local.dy >= -edge) {
      direction = -1;
    } else if (local.dy > height - edge && local.dy <= height + edge) {
      direction = 1;
    }

    if (direction == 0) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      return;
    }
    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final next =
          (pos.pixels + direction * 12).clamp(pos.minScrollExtent, pos.maxScrollExtent);
      _scrollController.jumpTo(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.categories),
        centerTitle: false,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'new_category',
            onPressed: _showAddFolderSheet,
            tooltip: l10n.newCategory,
            child: const Icon(Icons.new_label_outlined),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add_feed',
            onPressed: _showAddFeedSheet,
            icon: const Icon(Icons.add),
            label: Text(l10n.addFeed),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _feedsByFolder.values.every((f) => f.isEmpty) && _folders.isEmpty
              ? _emptyFeedsState()
              : RefreshIndicator(onRefresh: _load, child: _buildList()),
    );
  }

  Widget _buildList() {
    return ReorderableListView(
      key: _listKey,
      scrollController: _scrollController,
      padding: const EdgeInsets.only(bottom: 80),
      buildDefaultDragHandles: false,
      onReorder: _onReorderFolders,
      children: [
        for (int i = 0; i < _folders.length; i++)
          _FolderSection(
            key: ValueKey(_folders[i].id),
            folder: _folders[i],
            feeds: _feedsByFolder[_folders[i].id] ?? [],
            unreadCounts: _unreadCounts,
            onRenameFolder: () => _showRenameFolderSheet(_folders[i]),
            onDeleteFolder: () => _confirmDeleteFolder(_folders[i]),
            onEditFeed: (feed) => _showEditFeedSheet(feed),
            onDeleteFeed: (feed) => _confirmDeleteFeed(feed),
            dragIndex: i,
            onFeedDragStarted: _onFeedDragStarted,
            onFeedDragUpdate: _onFeedDragUpdate,
            onFeedDragEnd: _onFeedDragEnd,
            onFeedDropped: (feed, targetIndex) =>
                _moveFeed(feed, _folders[i].id!, targetIndex),
          ),
      ],
    );
  }

  void _onReorderFolders(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final folder = _folders.removeAt(oldIndex);
      _folders.insert(newIndex, folder);
    });
    unawaited(_persistFolderOrder());
  }

  Future<void> _persistFolderOrder() async {
    try {
      await LoadingController.instance
          .run(() => _folderRepo.reorder(_folders), label: 'Reordering');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.moveFeedFailed)),
      );
      await _load();
    }
  }

  Widget _emptyFeedsState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.rss_feed,
              size: 64,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(l10n.noFeedsYet,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  )),
        ],
      ),
    );
  }

  // ── Add feed ──

  void _showAddFeedSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AddFeedSheet(
        folders: _folders,
        feedlyService: _feedlyService,
        faviconService: _faviconService,
        feedRepo: _feedRepo,
        folderRepo: _folderRepo,
        articleRepo: ArticleRepository(),
        settingsRepo: SettingsRepository(),
        onFeedAdded: _load,
      ),
    );
  }

  // ── Add folder ──

  void _showAddFolderSheet() {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FolderNameSheet(
        title: l10n.newCategory,
        onSave: (name) => LoadingController.instance.run(() async {
          final position = await _folderRepo.getNextPosition();
          final now = DateTime.now().millisecondsSinceEpoch;
          await _folderRepo.insert(
            Folder(name: name, position: position, createdAt: now),
          );
          await _load();
        }, label: 'Adding category'),
      ),
    );
  }

  // ── Rename folder ──

  void _showRenameFolderSheet(Folder folder) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _FolderNameSheet(
        title: l10n.renameCategory,
        initialValue: folder.name,
        onSave: (name) => LoadingController.instance.run(() async {
          await _folderRepo.update(folder.copyWith(name: name));
          await _load();
        }, label: 'Renaming category'),
      ),
    );
  }

  // ── Delete folder ──

  Future<void> _confirmDeleteFolder(Folder folder) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _ConfirmSheet(
        title: l10n.deleteCategory,
        message: l10n.deleteFolderMessage(folder.name),
        confirmLabel: l10n.delete,
        isDestructive: true,
      ),
    );
    if (confirmed == true) {
      await LoadingController.instance.run(() async {
        await _folderRepo.delete(folder.id!);
        await _load();
      }, label: 'Deleting category');
    }
  }

  // ── Edit feed ──

  void _showEditFeedSheet(Feed feed) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditFeedSheet(
        feed: feed,
        folders: _folders,
        feedRepo: _feedRepo,
        onSaved: _load,
      ),
    );
  }

  // ── Delete feed ──

  Future<void> _confirmDeleteFeed(Feed feed) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => _ConfirmSheet(
        title: l10n.removeFeed,
        message: l10n.removeFeedMessage(feed.title),
        confirmLabel: l10n.remove,
        isDestructive: true,
      ),
    );
    if (confirmed == true) {
      await LoadingController.instance.run(() async {
        await _feedRepo.delete(feed.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.feedRemoved(feed.title))),
          );
        }
        await _load();
      }, label: 'Removing feed');
    }
  }
}

// ── Folder section ──

class _FolderSection extends StatefulWidget {
  final Folder folder;
  final List<Feed> feeds;
  final Map<int, int> unreadCounts;
  final VoidCallback onRenameFolder;
  final VoidCallback onDeleteFolder;
  final ValueChanged<Feed> onEditFeed;
  final ValueChanged<Feed> onDeleteFeed;
  final int dragIndex;

  // Cross-category feed drag plumbing, lifted to FeedsScreen so a drag
  // started in one section's row is accepted by a DragTarget in any other
  // section — LongPressDraggable/DragTarget work through the Overlay, so
  // this needs no shared list ancestor the way ReorderableListView would.
  final VoidCallback onFeedDragStarted;
  final ValueChanged<DragUpdateDetails> onFeedDragUpdate;
  final VoidCallback onFeedDragEnd;

  /// Called with (droppedFeed, targetIndex) when a feed is dropped here.
  final void Function(Feed feed, int targetIndex) onFeedDropped;

  const _FolderSection({
    super.key,
    required this.folder,
    required this.feeds,
    required this.unreadCounts,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onEditFeed,
    required this.onDeleteFeed,
    required this.dragIndex,
    required this.onFeedDragStarted,
    required this.onFeedDragUpdate,
    required this.onFeedDragEnd,
    required this.onFeedDropped,
  });

  @override
  State<_FolderSection> createState() => _FolderSectionState();
}

class _FolderSectionState extends State<_FolderSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _chevronController;

  @override
  void initState() {
    super.initState();
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0, // starts expanded
    );
  }

  @override
  void dispose() {
    _chevronController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _chevronController.forward();
    } else {
      _chevronController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.folder.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder header — tap to collapse, long-press for actions. Also a
        // drop target in its own right: dropping a source directly on the
        // header (e.g. while this category is collapsed, so no row/slot is
        // visible) appends it to the end of this folder's list.
        DragTarget<Feed>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (details) =>
              widget.onFeedDropped(details.data, widget.feeds.length),
          builder: (context, candidateData, rejectedData) {
            final isHovering = candidateData.isNotEmpty;
            return InkWell(
              onTap: _toggle,
              onLongPress: () => showModalBottomSheet(
                context: context,
                builder: (ctx) => _FolderActionsSheet(
                  folder: widget.folder,
                  onRename: widget.onRenameFolder,
                  onDelete: widget.onDeleteFolder,
                ),
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                color: isHovering
                    ? theme.colorScheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.label_outline_rounded,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    RotationTransition(
                      turns: Tween(begin: -0.25, end: 0.0)
                          .animate(_chevronController),
                      child: Icon(Icons.expand_more_rounded,
                          size: 18,
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.7)),
                    ),
                    const SizedBox(width: 4),
                    ReorderableDragStartListener(
                      index: widget.dragIndex,
                      child: Icon(Icons.drag_handle_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.35)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        // Animated expand/collapse
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _expanded
              ? Column(
                  children: [
                    _FeedDropSlot(
                      key: ValueKey('slot_${widget.folder.id}_0'),
                      index: 0,
                      onFeedDropped: widget.onFeedDropped,
                    ),
                    for (int i = 0; i < widget.feeds.length; i++) ...[
                      _DraggableFeedRow(
                        key: ValueKey(widget.feeds[i].id),
                        feed: widget.feeds[i],
                        unreadCount:
                            widget.unreadCounts[widget.feeds[i].id] ?? 0,
                        onEdit: () => _showFeedMenu(context, widget.feeds[i]),
                        onDragStarted: widget.onFeedDragStarted,
                        onDragUpdate: widget.onFeedDragUpdate,
                        onDragEnd: widget.onFeedDragEnd,
                      ),
                      _FeedDropSlot(
                        key: ValueKey('slot_${widget.folder.id}_${i + 1}'),
                        index: i + 1,
                        onFeedDropped: widget.onFeedDropped,
                      ),
                    ],
                  ],
                )
              : const SizedBox.shrink(),
        ),
        const Divider(height: 1),
      ],
    );
  }

  void _showFeedMenu(BuildContext context, Feed feed) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _FeedActionsSheet(
        feed: feed,
        onEdit: () => widget.onEditFeed(feed),
        onDelete: () => widget.onDeleteFeed(feed),
      ),
    );
  }
}

// ── Feed drop slot ──
//
// A thin insertion point rendered before every row and once after the
// last one (n feeds → n+1 slots). Highlights and grows when a compatible
// drag hovers over it, giving the Material "this is where it'll land" cue
// that a plain reorder-on-drop wouldn't show.
class _FeedDropSlot extends StatelessWidget {
  final int index;
  final void Function(Feed feed, int index) onFeedDropped;

  const _FeedDropSlot({
    super.key,
    required this.index,
    required this.onFeedDropped,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Feed>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onFeedDropped(details.data, index),
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        final accent = Theme.of(context).colorScheme.primary;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: isHovering ? 28 : 4,
          margin: isHovering
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 2)
              : EdgeInsets.zero,
          decoration: isHovering
              ? BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accent, width: 1.5),
                )
              : null,
        );
      },
    );
  }
}

// ── Draggable feed row ──

class _DraggableFeedRow extends StatelessWidget {
  final Feed feed;
  final int unreadCount;
  final VoidCallback onEdit;
  final VoidCallback onDragStarted;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final VoidCallback onDragEnd;

  const _DraggableFeedRow({
    super.key,
    required this.feed,
    required this.unreadCount,
    required this.onEdit,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final row = FeedCard(
      feed: feed,
      unreadCount: unreadCount,
      onEdit: onEdit,
    );

    return LongPressDraggable<Feed>(
      data: feed,
      onDragStarted: onDragStarted,
      onDragUpdate: onDragUpdate,
      onDragEnd: (_) => onDragEnd(),
      onDraggableCanceled: (_, __) => onDragEnd(),
      feedback: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width - 32,
          child: row,
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: row),
      child: row,
    );
  }
}

// ── Add Feed Sheet ──

class _AddFeedSheet extends StatefulWidget {
  final List<Folder> folders;
  final FeedlyService feedlyService;
  final FaviconService faviconService;
  final FeedRepository feedRepo;
  final FolderRepository folderRepo;
  final ArticleRepository articleRepo;
  final SettingsRepository settingsRepo;
  final VoidCallback onFeedAdded;

  const _AddFeedSheet({
    required this.folders,
    required this.feedlyService,
    required this.faviconService,
    required this.feedRepo,
    required this.folderRepo,
    required this.articleRepo,
    required this.settingsRepo,
    required this.onFeedAdded,
  });

  @override
  State<_AddFeedSheet> createState() => _AddFeedSheetState();
}

class _AddFeedSheetState extends State<_AddFeedSheet> {
  final _controller = TextEditingController();
  List<FeedlyResult> _results = [];
  bool _searching = false;
  bool _adding = false;
  String _error = '';

  /// Intentionally starts null — the user must pick a category.
  Folder? _selectedFolder;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final l10n = AppLocalizations.of(context)!;
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _searching = true;
      _error = '';
      _results = [];
    });

    if (widget.feedlyService.looksLikeUrl(query)) {
      await _addByUrl(query);
    } else {
      final results = await LoadingController.instance
          .run(() => widget.feedlyService.search(query), label: 'Searching');
      if (mounted) {
        setState(() {
          _results = results;
          _searching = false;
          if (results.isEmpty) _error = l10n.noFeedsFound;
        });
      }
    }
  }

  Future<void> _addByUrl(String url) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _adding = true);
    await LoadingController.instance.run(() => _addByUrlBody(url, l10n), label: 'Adding feed');
  }

  Future<void> _addByUrlBody(String url, AppLocalizations l10n) async {
    try {
      // Ensure folder exists
      final folderId = await _ensureFolder(context);
      if (folderId == null) return;

      // Check duplicate
      final existing = await widget.feedRepo.getByUrl(url);
      if (existing != null) {
        if (!mounted) return;
        setState(() {
          _error = l10n.feedAlreadyAdded;
          _searching = false;
          _adding = false;
        });
        return;
      }

      final rssService =
          RssService(widget.articleRepo, widget.feedRepo);
      final info = await rssService.validateFeedUrl(url);
      if (info == null) {
        if (!mounted) return;
        setState(() {
          _error = l10n.couldNotParseFeed;
          _searching = false;
          _adding = false;
        });
        return;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      var feed = Feed(
        folderId: folderId,
        title: info.title,
        url: url,
        siteUrl: info.siteUrl,
        description: info.description,
        createdAt: now,
      );
      feed = await widget.feedRepo.insert(feed);

      // Fetch favicon
      if (feed.siteUrl != null || url.isNotEmpty) {
        final domain = Uri.tryParse(feed.siteUrl ?? url)?.host ?? '';
        if (domain.isNotEmpty) {
          final faviconPath =
              await widget.faviconService.fetchAndCache(domain, feed.id!);
          if (faviconPath != null) {
            await widget.feedRepo.updateFaviconPath(feed.id!, faviconPath);
          }
        }
      }

      // Initial fetch — respects the same cap as every later refresh, so a
      // newly added feed doesn't arrive holding more than the setting allows.
      final settings = await widget.settingsRepo.getAll();
      await rssService.fetchAndStore(feed, articleLimit: settings.articleLimit);

      if (mounted) {
        Navigator.pop(context);
        widget.onFeedAdded();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = l10n.failedToAddFeed(e.toString());
          _searching = false;
          _adding = false;
        });
      }
    }
  }

  Future<void> _addFromFeedly(FeedlyResult result) async {
    await _addByUrl(result.feedUrl);
  }

  Future<int?> _ensureFolder(BuildContext context) async {
    if (_selectedFolder != null) return _selectedFolder!.id!;
    // Reuse an existing folder if one already exists
    final existing = await widget.folderRepo.getAll();
    if (existing.isNotEmpty) return existing.first.id!;
    // Create a default folder only when there are none at all
    if (!context.mounted) return null;
    final l10n = AppLocalizations.of(context)!;
    final now = DateTime.now().millisecondsSinceEpoch;
    final folder = await widget.folderRepo.insert(
      Folder(name: l10n.defaultFolderName, position: 0, createdAt: now),
    );
    return folder.id;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.addAFeed,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // Folder picker — chips keep the keyboard open
          if (widget.folders.isNotEmpty) ...[
            Text(l10n.addToCategory,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    )),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: widget.folders.map((f) {
                final selected = _selectedFolder?.id == f.id;
                return ChoiceChip(
                  label: Text(f.name),
                  selected: selected,
                  onSelected: (_) =>
                      setState(() => _selectedFolder = selected ? null : f),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],

          // Search field
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: l10n.searchHint,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _search,
              ),
            ),
          ),

          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: TextStyle(color: theme.colorScheme.error)),
          ],

          if (_searching || _adding)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Center(child: CircularProgressIndicator()),
            ),

          if (_results.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _results[i];
                  final l10n = AppLocalizations.of(context)!;
                  return ListTile(
                    title: Text(r.title),
                    subtitle: r.website != null ? Text(r.website!) : null,
                    trailing: r.subscribers != null
                        ? Text(
                            '${_formatSubscribers(r.subscribers!)} ${l10n.followers}',
                            style: theme.textTheme.labelSmall,
                          )
                        : null,
                    onTap: () => _addFromFeedly(r),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                  );
                },
              ),
            ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _formatSubscribers(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }
}

// ── Helper sheets ──

class _FolderNameSheet extends StatefulWidget {
  final String title;
  final String? initialValue;
  final ValueChanged<String> onSave;

  const _FolderNameSheet({
    required this.title,
    this.initialValue,
    required this.onSave,
  });

  @override
  State<_FolderNameSheet> createState() => _FolderNameSheetState();
}

class _FolderNameSheetState extends State<_FolderNameSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.categoryName,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context);
    widget.onSave(name);
  }
}

class _EditFeedSheet extends StatefulWidget {
  final Feed feed;
  final List<Folder> folders;
  final FeedRepository feedRepo;
  final VoidCallback onSaved;

  const _EditFeedSheet({
    required this.feed,
    required this.folders,
    required this.feedRepo,
    required this.onSaved,
  });

  @override
  State<_EditFeedSheet> createState() => _EditFeedSheetState();
}

class _EditFeedSheetState extends State<_EditFeedSheet> {
  late final TextEditingController _titleController;
  late Folder? _selectedFolder;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.feed.title);
    _selectedFolder =
        widget.folders.where((f) => f.id == widget.feed.folderId).firstOrNull;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.editFeed, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: l10n.feedName,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.folders.isNotEmpty)
            DropdownButtonFormField<Folder>(
              initialValue: _selectedFolder,
              decoration: InputDecoration(
                labelText: l10n.category,
                border: const OutlineInputBorder(),
              ),
              items: widget.folders
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(f.name),
                      ))
                  .toList(),
              onChanged: (f) => setState(() => _selectedFolder = f),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final updated = widget.feed.copyWith(
      title: title,
      folderId: _selectedFolder?.id ?? widget.feed.folderId,
    );
    await widget.feedRepo.update(updated);
    if (mounted) Navigator.pop(context);
    widget.onSaved();
  }
}

class _ConfirmSheet extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool isDestructive;

  const _ConfirmSheet({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: isDestructive
                      ? FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.error,
                          foregroundColor: theme.colorScheme.onError,
                        )
                      : null,
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderActionsSheet extends StatelessWidget {
  final Folder folder;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  const _FolderActionsSheet({
    required this.folder,
    this.onRename,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.renameFolder(folder.name)),
            onTap: () {
              Navigator.pop(context);
              onRename?.call();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            title: Text(
              l10n.deleteFolder(folder.name),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () {
              Navigator.pop(context);
              onDelete?.call();
            },
          ),
        ],
      ),
    );
  }
}

class _FeedActionsSheet extends StatelessWidget {
  final Feed feed;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FeedActionsSheet({
    required this.feed,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.edit),
            onTap: () {
              Navigator.pop(context);
              onEdit();
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            title: Text(l10n.remove,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}
