import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/article.dart';
import '../models/folder.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/refresh_service.dart';
import '../services/share_service.dart';
import '../widgets/article_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/folder_tab_bar.dart';
import '../widgets/shimmer_card.dart';

class FeedScreen extends StatefulWidget {
  final VoidCallback onNavigateToFeeds;
  final ValueNotifier<int> reloadNotifier;

  const FeedScreen({
    super.key,
    required this.onNavigateToFeeds,
    required this.reloadNotifier,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _articleRepo = ArticleRepository();
  final _feedRepo = FeedRepository();
  final _folderRepo = FolderRepository();
  final _settingsRepo = SettingsRepository();
  final _shareService = ShareService();

  final ScrollController _scrollController = ScrollController();

  List<Folder> _folders = [];
  List<Article> _articles = [];
  Map<int, int> _folderUnreadCounts = {};
  int _allUnreadCount = 0;
  int _selectedTabIndex = 0;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasFeeds = false;
  bool _markReadOnScroll = true;

  Timer? _markReadDebounce;
  final Set<int> _pendingMarkRead = {};

  @override
  void initState() {
    super.initState();
    _init();
    widget.reloadNotifier.addListener(_onReloadRequested);
  }

  @override
  void dispose() {
    widget.reloadNotifier.removeListener(_onReloadRequested);
    _markReadDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // Called whenever the user taps back to the Feed tab
  void _onReloadRequested() {
    _loadAll();
  }

  Future<void> _init() async {
    final settings = await _settingsRepo.getAll();
    _markReadOnScroll = settings.markReadOnScroll;
    await _loadAll();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final folders = await _folderRepo.getAll();
    final feeds = await _feedRepo.getAll();
    _hasFeeds = feeds.isNotEmpty;

    final articles = await _articlesForTab(_selectedTabIndex, folders);
    final folderCounts = await _buildFolderUnreadCounts(folders);
    final allCount = await _articleRepo.getUnreadCount();

    if (mounted) {
      setState(() {
        _folders = folders;
        _articles = articles;
        _folderUnreadCounts = folderCounts;
        _allUnreadCount = allCount;
        _loading = false;
      });
    }
  }

  Future<List<Article>> _articlesForTab(int tabIndex, List<Folder> folders) async {
    if (tabIndex == 0) return _articleRepo.getAll(includeRead: false);
    final folder = folders[tabIndex - 1];
    return _articleRepo.getForFolder(folder.id!, includeRead: false);
  }

  Future<Map<int, int>> _buildFolderUnreadCounts(List<Folder> folders) async {
    final counts = <int, int>{};
    for (final folder in folders) {
      counts[folder.id!] = await _articleRepo.getUnreadCountForFolder(folder.id!);
    }
    return counts;
  }

  Future<void> _refreshCurrentTab() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    HapticFeedback.lightImpact();
    try {
      final refreshSvc = RefreshService(_settingsRepo);
      if (_selectedTabIndex == 0) {
        await refreshSvc.refreshAll();
      } else {
        final folder = _folders[_selectedTabIndex - 1];
        final feeds = await _feedRepo.getByFolder(folder.id!);
        for (final feed in feeds) {
          await refreshSvc.refreshFeed(feed);
        }
      }
    } finally {
      await _loadAll();
      if (mounted) setState(() => _refreshing = false);
    }
  }

  // FIX: only mark articles that have fully scrolled off the top of the viewport.
  // Articles below the top edge are still being read — do not mark them yet.
  void _onScroll() {
    if (!_markReadOnScroll) return;
    if (_articles.isEmpty) return;

    final scrollOffset = _scrollController.offset;
    const estimatedCardHeight = 88.0;

    // Number of cards that have scrolled completely off the top
    final offScreenCount = (scrollOffset / estimatedCardHeight).floor();

    for (int i = 0; i < offScreenCount && i < _articles.length; i++) {
      final article = _articles[i];
      if (!article.isRead && article.id != null) {
        _pendingMarkRead.add(article.id!);
      }
    }

    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 500), _flushMarkRead);
  }

  Future<void> _flushMarkRead() async {
    if (_pendingMarkRead.isEmpty) return;
    final ids = List<int>.from(_pendingMarkRead);
    _pendingMarkRead.clear();
    await _articleRepo.markManyRead(ids);
    if (mounted) {
      setState(() {
        _articles = _articles.map((a) {
          if (ids.contains(a.id)) return a.copyWith(isRead: true);
          return a;
        }).toList();
        _allUnreadCount = (_allUnreadCount - ids.length).clamp(0, _allUnreadCount);
      });
    }
  }

  Future<void> _onTabSelected(int index) async {
    if (index == _selectedTabIndex) return;
    setState(() {
      _selectedTabIndex = index;
      _loading = true;
    });
    final articles = await _articlesForTab(index, _folders);
    if (mounted) {
      setState(() {
        _articles = articles;
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    HapticFeedback.mediumImpact();
    if (_selectedTabIndex == 0) {
      await _articleRepo.markAllRead();
    } else {
      final folder = _folders[_selectedTabIndex - 1];
      await _articleRepo.markAllReadForFolder(folder.id!);
    }
    await _loadAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All marked as read')),
      );
    }
  }

  Future<void> _openArticle(Article article) async {
    final uri = Uri.tryParse(article.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!article.isRead && article.id != null) {
      await _articleRepo.markRead(article.id!);
      if (mounted) {
        setState(() {
          _articles = _articles.map((a) {
            if (a.id == article.id) return a.copyWith(isRead: true);
            return a;
          }).toList();
        });
      }
    }
  }

  Future<void> _markRead(Article article) async {
    if (article.id == null) return;
    await _articleRepo.markRead(article.id!);
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {
        _articles = _articles.map((a) {
          if (a.id == article.id) return a.copyWith(isRead: true);
          return a;
        }).toList();
      });
    }
  }

  Future<void> _markUnread(Article article) async {
    if (article.id == null) return;
    await _articleRepo.markUnread(article.id!);
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {
        _articles = _articles.map((a) {
          if (a.id == article.id) return a.copyWith(isRead: false);
          return a;
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flash'),
        centerTitle: false,
        actions: [
        ],
      ),
      floatingActionButton: _hasFeeds
          ? Padding(
              // Raise FABs above the folder tab bar (48px) when it's visible
              padding: EdgeInsets.only(
                bottom: (_hasFeeds && _folders.length > 1) ? 48.0 : 0.0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'mark_all_read',
                    onPressed: _markAllRead,
                    tooltip: 'Mark all as read',
                    mini: true,
                    child: const Icon(Icons.done_all_rounded),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    heroTag: 'refresh',
                    onPressed: _refreshing ? null : _refreshCurrentTab,
                    tooltip: 'Refresh',
                    mini: true,
                    child: _refreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            )
          : null,
      body: Column(
        children: [
          Expanded(child: _buildContent()),
          if (_hasFeeds && _folders.length > 1)
            FolderTabBar(
              folders: _folders,
              selectedIndex: _selectedTabIndex,
              folderUnreadCounts: _folderUnreadCounts,
              allUnreadCount: _allUnreadCount,
              onTabSelected: _onTabSelected,
              onMarkAllRead: _markAllRead,
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (!_hasFeeds) {
      return EmptyState(onAddFeed: widget.onNavigateToFeeds);
    }
    if (_loading) {
      return ListView.builder(
        itemCount: 8,
        itemBuilder: (_, __) => const ShimmerCard(),
      );
    }
    if (_articles.isEmpty) {
      return Center(
        child: Text(
          'No articles yet.\nPull down to refresh.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshCurrentTab,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _articles.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, i) {
          final article = _articles[i];
          return ArticleCard(
            article: article,
            onTap: () => _openArticle(article),
            onMarkRead: () => _markRead(article),
            onMarkUnread: () => _markUnread(article),
            onShare: () => _shareService.shareArticle(article),
          );
        },
      ),
    );
  }
}
