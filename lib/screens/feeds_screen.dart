import 'package:flutter/material.dart';
import '../models/feed.dart';
import '../models/folder.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../services/favicon_service.dart';
import '../services/feedly_service.dart';
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
  List<Feed> _feeds = [];
  List<Folder> _folders = [];
  Map<int, int> _unreadCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final feeds = await _feedRepo.getAll();
    final folders = await _folderRepo.getAll();
    final counts = await _feedRepo.getUnreadCounts();
    if (mounted) {
      setState(() {
        _feeds = feeds;
        _folders = folders;
        _unreadCounts = counts;
        _loading = false;
      });
    }
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
          : _feeds.isEmpty && _folders.isEmpty
              ? _emptyFeedsState()
              : RefreshIndicator(onRefresh: _load, child: _buildList()),
    );
  }

  Widget _buildList() {
    // Group feeds by folder
    final grouped = <int?, List<Feed>>{};
    for (final feed in _feeds) {
      grouped.putIfAbsent(feed.folderId, () => []).add(feed);
    }

    // Uncategorized feeds pinned at the bottom, outside the reorderable list
    final folderIds = _folders.map((f) => f.id).toSet();
    final orphanFeeds =
        _feeds.where((f) => !folderIds.contains(f.folderId)).toList();

    return ReorderableListView(
      padding: const EdgeInsets.only(bottom: 80),
      buildDefaultDragHandles: false,
      onReorder: _onReorderFolders,
      footer: orphanFeeds.isNotEmpty
          ? _FolderSection(
              key: const ValueKey('orphan'),
              folder: null,
              feeds: orphanFeeds,
              unreadCounts: _unreadCounts,
              onRenameFolder: null,
              onDeleteFolder: null,
              onEditFeed: (feed) => _showEditFeedSheet(feed),
              onDeleteFeed: (feed) => _confirmDeleteFeed(feed),
              onReorderFeeds: null,
              dragIndex: null,
            )
          : null,
      children: [
        for (int i = 0; i < _folders.length; i++)
          _FolderSection(
            key: ValueKey(_folders[i].id),
            folder: _folders[i],
            feeds: grouped[_folders[i].id] ?? [],
            unreadCounts: _unreadCounts,
            onRenameFolder: () => _showRenameFolderSheet(_folders[i]),
            onDeleteFolder: () => _confirmDeleteFolder(_folders[i]),
            onEditFeed: (feed) => _showEditFeedSheet(feed),
            onDeleteFeed: (feed) => _confirmDeleteFeed(feed),
            onReorderFeeds: (feeds) => _reorderFeeds(_folders[i], feeds),
            dragIndex: i,
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
    _folderRepo.reorder(_folders);
  }

  Future<void> _reorderFeeds(Folder folder, List<Feed> feeds) async {
    await _feedRepo.reorder(feeds);
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
        onSave: (name) async {
          final position = await _folderRepo.getNextPosition();
          final now = DateTime.now().millisecondsSinceEpoch;
          await _folderRepo.insert(
            Folder(name: name, position: position, createdAt: now),
          );
          _load();
        },
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
        onSave: (name) async {
          await _folderRepo.update(folder.copyWith(name: name));
          _load();
        },
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
      await _folderRepo.delete(folder.id!);
      _load();
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
      await _feedRepo.delete(feed.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.feedRemoved(feed.title))),
        );
      }
      _load();
    }
  }
}

// ── Folder section ──

class _FolderSection extends StatefulWidget {
  final Folder? folder;
  final List<Feed> feeds;
  final Map<int, int> unreadCounts;
  final VoidCallback? onRenameFolder;
  final VoidCallback? onDeleteFolder;
  final ValueChanged<Feed> onEditFeed;
  final ValueChanged<Feed> onDeleteFeed;
  final ValueChanged<List<Feed>>? onReorderFeeds;
  final int? dragIndex;

  const _FolderSection({
    super.key,
    required this.folder,
    required this.feeds,
    required this.unreadCounts,
    required this.onRenameFolder,
    required this.onDeleteFolder,
    required this.onEditFeed,
    required this.onDeleteFeed,
    required this.onReorderFeeds,
    required this.dragIndex,
  });

  @override
  State<_FolderSection> createState() => _FolderSectionState();
}

class _FolderSectionState extends State<_FolderSection>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  late final AnimationController _chevronController;
  late List<Feed> _localFeeds;

  @override
  void initState() {
    super.initState();
    _localFeeds = List.of(widget.feeds);
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0, // starts expanded
    );
  }

  @override
  void didUpdateWidget(_FolderSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feeds != widget.feeds) {
      _localFeeds = List.of(widget.feeds);
    }
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

  void _onReorderFeeds(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    setState(() {
      final feed = _localFeeds.removeAt(oldIndex);
      _localFeeds.insert(newIndex, feed);
    });
    widget.onReorderFeeds?.call(_localFeeds);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final name = widget.folder?.name ?? l10n.uncategorised;
    final canReorderFolders = widget.dragIndex != null;
    final canReorderFeeds = widget.onReorderFeeds != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Folder header — tap to collapse, long-press for actions
        InkWell(
          onTap: _toggle,
          onLongPress: widget.folder != null
              ? () => showModalBottomSheet(
                    context: context,
                    builder: (ctx) => _FolderActionsSheet(
                      folder: widget.folder!,
                      onRename: widget.onRenameFolder,
                      onDelete: widget.onDeleteFolder,
                    ),
                  )
              : null,
          child: Padding(
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
                      color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                ),
                if (canReorderFolders) ...[
                  const SizedBox(width: 4),
                  ReorderableDragStartListener(
                    index: widget.dragIndex!,
                    child: Icon(Icons.drag_handle_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.35)),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Animated expand/collapse
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          child: _expanded
              ? canReorderFeeds && _localFeeds.isNotEmpty
                  ? ReorderableListView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      onReorder: _onReorderFeeds,
                      children: [
                        for (int i = 0; i < _localFeeds.length; i++)
                          _ReorderableFeedRow(
                            key: ValueKey(_localFeeds[i].id),
                            feed: _localFeeds[i],
                            unreadCount:
                                widget.unreadCounts[_localFeeds[i].id] ?? 0,
                            onEdit: () =>
                                _showFeedMenu(context, _localFeeds[i]),
                            dragIndex: i,
                          ),
                      ],
                    )
                  : Column(
                      children: _localFeeds
                          .map((feed) => FeedCard(
                                feed: feed,
                                unreadCount:
                                    widget.unreadCounts[feed.id] ?? 0,
                                onEdit: () => _showFeedMenu(context, feed),
                              ))
                          .toList(),
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

// ── Reorderable feed row ──

class _ReorderableFeedRow extends StatelessWidget {
  final Feed feed;
  final int unreadCount;
  final VoidCallback onEdit;
  final int dragIndex;

  const _ReorderableFeedRow({
    super.key,
    required this.feed,
    required this.unreadCount,
    required this.onEdit,
    required this.dragIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: FeedCard(
            feed: feed,
            unreadCount: unreadCount,
            onEdit: onEdit,
          ),
        ),
        ReorderableDragStartListener(
          index: dragIndex,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.drag_handle_rounded,
              size: 20,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
            ),
          ),
        ),
      ],
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
  Folder? _selectedFolder;

  @override
  void initState() {
    super.initState();
    // _selectedFolder intentionally starts null — user must pick a category
  }

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
      final results = await widget.feedlyService.search(query);
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
    try {
      // Ensure folder exists
      final folderId = await _ensureFolder(context);
      if (folderId == null) return;

      // Check duplicate
      final existing = await widget.feedRepo.getByUrl(url);
      if (existing != null) {
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

      // Initial fetch
      await rssService.fetchAndStore(feed);

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
