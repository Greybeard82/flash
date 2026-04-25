import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
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
import 'reader_screen.dart';
import 'search_screen.dart';

class FeedScreen extends StatefulWidget {
  final VoidCallback onNavigateToFeeds;

  const FeedScreen({super.key, required this.onNavigateToFeeds});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
  // ── Repos & services ───────────────────────────────────────────────────────
  final _articleRepo = ArticleRepository();
  final _feedRepo = FeedRepository();
  final _folderRepo = FolderRepository();
  final _settingsRepo = SettingsRepository();
  final _shareService = ShareService();

  // ── Scroll ─────────────────────────────────────────────────────────────────
  final ScrollController _scrollController = ScrollController();

  // ── UI state ───────────────────────────────────────────────────────────────
  List<Folder> _folders = [];
  List<Article> _articles = [];
  Map<int, int> _folderUnreadCounts = {};
  int _allUnreadCount = 0;
  int _selectedTabIndex = 0;
  bool _loading = true;
  bool _refreshing = false;
  bool _hasFeeds = false;
  bool _markReadOnScroll = true;

  // Race guard: only the latest tab-switch result is applied.
  int _tabGeneration = 0;

  // Mark-as-read-on-scroll debounce
  Timer? _scrollDebounce;
  final Set<int> _pendingMarkRead = {};
  final List<GlobalKey?> _cardKeys = [];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // On every resume (returning from browser, reader, or background), reload
  // articles from the local DB to pick up any changes made by background
  // refresh — without triggering a full network fetch and without touching
  // the scroll position.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      _reloadArticles();
    }
  }

  // ── Boot ───────────────────────────────────────────────────────────────────

  Future<void> _boot() async {
    final settings = await _settingsRepo.getAll();
    _markReadOnScroll = settings.markReadOnScroll;

    // Show cached articles immediately.
    await _loadArticles(showLoading: true);
    _scrollController.addListener(_onScroll);

    // Then fetch fresh articles from the network in the background.
    // The refresh spinner in the FAB provides visual feedback.
    _fetchAndReload();
  }

  // ── Core data operations ───────────────────────────────────────────────────

  /// Reads articles for the current tab from the local DB and updates state.
  /// Always loads with includeRead: true so articles never disappear mid-session
  /// when marked as read. Pass [unreadOnly: true] only for the post-mark-all-read
  /// reload, where the intention is to show only freshly arrived articles.
  Future<void> _loadArticles({
    bool showLoading = false,
    bool unreadOnly = false,
  }) async {
    if (!mounted) return;
    if (showLoading) setState(() => _loading = true);

    final (folders, feeds) = await (
      _folderRepo.getAll(),
      _feedRepo.getAll(),
    ).wait;

    final safeTab = _selectedTabIndex.clamp(0, folders.length);

    final (articles, folderCounts, allCount) = await (
      _articlesForTab(safeTab, folders, unreadOnly: unreadOnly),
      _articleRepo.getAllFolderUnreadCounts(),
      _articleRepo.getUnreadCount(),
    ).wait;

    if (!mounted) return;
    setState(() {
      _folders = folders;
      _hasFeeds = feeds.isNotEmpty;
      _selectedTabIndex = safeTab;
      _articles = articles;
      _cardKeys
        ..clear()
        ..addAll(List.generate(articles.length, (_) => GlobalKey()));
      _folderUnreadCounts = folderCounts;
      _allUnreadCount = allCount;
      _loading = false;
    });
    AppBadgePlus.updateBadge(allCount);
  }

  /// Reloads articles from DB while preserving the current scroll position.
  /// Used on app resume — picks up background-refresh results without jumping.
  Future<void> _reloadArticles() async {
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    await _loadArticles();
    _restoreScrollOffset(offset);
  }

  Future<List<Article>> _articlesForTab(
    int tab,
    List<Folder> folders, {
    bool unreadOnly = false,
  }) {
    if (tab == 0) return _articleRepo.getAll(includeRead: !unreadOnly);
    return _articleRepo.getForFolder(folders[tab - 1].id!, includeRead: !unreadOnly);
  }

  void _restoreScrollOffset(double offset) {
    if (offset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (max > 0) _scrollController.jumpTo(offset.clamp(0.0, max));
    });
  }

  // ── Network refresh ────────────────────────────────────────────────────────

  /// Fetches all feeds from the network then reloads the local DB into state.
  /// Saves and restores the scroll position so the list doesn't jump.
  Future<void> _fetchAndReload() async {
    if (!mounted || _refreshing) return;
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    setState(() => _refreshing = true);
    try {
      await RefreshService(_settingsRepo).refreshAll();
    } finally {
      await _loadArticles();
      if (mounted) setState(() => _refreshing = false);
      _restoreScrollOffset(offset);
    }
  }

  /// Manual refresh — fetches only the current tab's feeds.
  Future<void> _refreshCurrentTab() async {
    if (_refreshing) return;
    HapticFeedback.lightImpact();
    final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    setState(() => _refreshing = true);
    try {
      final svc = RefreshService(_settingsRepo);
      if (_selectedTabIndex == 0) {
        await svc.refreshAll();
      } else {
        final feeds = await _feedRepo.getByFolder(_folders[_selectedTabIndex - 1].id!);
        for (final f in feeds) { await svc.refreshFeed(f); }
      }
    } finally {
      await _loadArticles();
      if (mounted) setState(() => _refreshing = false);
      _restoreScrollOffset(offset);
    }
  }

  // ── Tab switching ──────────────────────────────────────────────────────────

  Future<void> _onTabSelected(int index) async {
    if (index == _selectedTabIndex) return;
    final gen = ++_tabGeneration;
    setState(() {
      _selectedTabIndex = index;
      _loading = true;
    });
    final articles = await _articlesForTab(index, _folders);
    if (!mounted || gen != _tabGeneration) return;
    setState(() {
      _articles = articles;
      _cardKeys
        ..clear()
        ..addAll(List.generate(articles.length, (_) => GlobalKey()));
      _loading = false;
    });
    // New tab always starts at the top.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  // ── Mark as read on scroll ─────────────────────────────────────────────────

  void _onScroll() {
    if (!_markReadOnScroll || _articles.isEmpty) return;
    final offset = _scrollController.offset;
    double cumulative = 0.0;
    for (int i = 0; i < _articles.length; i++) {
      final key = i < _cardKeys.length ? _cardKeys[i] : null;
      double h = 120.0;
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) h = box.size.height;
      }
      if (cumulative + h / 2 < offset) {
        final a = _articles[i];
        if (!a.isRead && a.id != null) _pendingMarkRead.add(a.id!);
      } else {
        break;
      }
      cumulative += h;
    }
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 250), _flushMarkRead);
  }

  Future<void> _flushMarkRead() async {
    if (_pendingMarkRead.isEmpty) return;
    final ids = Set<int>.from(_pendingMarkRead);
    _pendingMarkRead.clear();
    await _articleRepo.markManyRead(ids.toList());
    if (!mounted) return;
    setState(() {
      for (int i = 0; i < _articles.length; i++) {
        if (ids.contains(_articles[i].id)) {
          _articles[i] = _articles[i].copyWith(isRead: true);
        }
      }
      _allUnreadCount = (_allUnreadCount - ids.length).clamp(0, _allUnreadCount);
    });
    AppBadgePlus.updateBadge(_allUnreadCount);
  }

  // ── Article actions ────────────────────────────────────────────────────────

  Future<void> _openArticle(Article article) async {
    final settings = await _settingsRepo.getAll();
    final wasUnread = article.id != null && !article.isRead;
    if (wasUnread) await _articleRepo.markRead(article.id!);
    if (!mounted) return;

    // Save scroll position now, before any navigation or lifecycle events fire.
    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

    final uri = Uri.tryParse(article.url);
    if (uri == null) return;

    if (settings.readerMode) {
      final domain = uri.host;
      final cached = await _settingsRepo.get('reader_compat_$domain');
      if (cached == 'fail') {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (cached == null) {
          final isHtml = await _preflightIsHtml(uri);
          if (!isHtml) {
            await _settingsRepo.set('reader_compat_$domain', 'fail');
            if (mounted) await launchUrl(uri, mode: LaunchMode.externalApplication);
            return;
          }
        }
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              article: article,
              fontSize: settings.articleFontSize,
              onExtractionSucceeded: () =>
                  _settingsRepo.set('reader_compat_$domain', 'ok'),
              onExtractionFailed: () =>
                  _settingsRepo.set('reader_compat_$domain', 'fail'),
            ),
          ),
        );
      }
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    // Update the article's read state in-place — no DB reload, no list rebuild.
    // This keeps the list stable and the scroll position intact.
    if (wasUnread && mounted) {
      setState(() {
        _articles = [
          for (final a in _articles)
            a.id == article.id ? a.copyWith(isRead: true) : a,
        ];
        _allUnreadCount = (_allUnreadCount - 1).clamp(0, _allUnreadCount);
      });
      AppBadgePlus.updateBadge(_allUnreadCount);
    }

    // Restore the exact scroll position the user was at before opening the article.
    // This runs after the state update above so the list has the right height.
    _restoreScrollOffset(scrollOffset);
  }

  Future<bool> _preflightIsHtml(Uri uri) async {
    try {
      final r = await http.head(uri).timeout(const Duration(seconds: 5));
      return (r.headers['content-type'] ?? '').contains('text/html');
    } catch (_) {
      return true;
    }
  }

  Future<void> _markRead(Article article) async {
    if (article.id == null || article.isRead) return;
    await _articleRepo.markRead(article.id!);
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _articles = [
        for (final a in _articles)
          a.id == article.id ? a.copyWith(isRead: true) : a,
      ];
      _allUnreadCount = (_allUnreadCount - 1).clamp(0, _allUnreadCount);
    });
    AppBadgePlus.updateBadge(_allUnreadCount);
  }

  Future<void> _markUnread(Article article) async {
    if (article.id == null || !article.isRead) return;
    await _articleRepo.markUnread(article.id!);
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _articles = [
        for (final a in _articles)
          a.id == article.id ? a.copyWith(isRead: false) : a,
      ];
      _allUnreadCount++;
    });
    AppBadgePlus.updateBadge(_allUnreadCount);
  }

  Future<void> _toggleSaved(Article article) async {
    if (article.id == null) return;
    final nowSaved = !article.isSaved;
    await _articleRepo.setSaved(article.id!, saved: nowSaved);
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _articles = [
        for (final a in _articles)
          a.id == article.id ? a.copyWith(isSaved: nowSaved) : a,
      ];
    });
  }

  // ── Mark all read ──────────────────────────────────────────────────────────

  Future<void> _markAllRead() async {
    final warned = (await _settingsRepo.get('mark_all_read_warned')) == 'true';
    if (!warned) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.markAllReadWarningTitle),
          content: Text(l10n.markAllReadWarningBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.markAllReadConfirm),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await _settingsRepo.set('mark_all_read_warned', 'true');
    }

    HapticFeedback.mediumImpact();

    // Step 1 — Mark all as read in the DB.
    if (_selectedTabIndex == 0) {
      await _articleRepo.markAllRead();
    } else {
      await _articleRepo.markAllReadForFolder(_folders[_selectedTabIndex - 1].id!);
    }

    // Step 2 — Clear the list immediately for instant feedback.
    if (!mounted) return;
    setState(() {
      _articles = [];
      _cardKeys.clear();
      _allUnreadCount = 0;
    });
    AppBadgePlus.updateBadge(0);

    // Step 3 — Fetch fresh articles from the network.
    setState(() => _refreshing = true);
    try {
      final svc = RefreshService(_settingsRepo);
      if (_selectedTabIndex == 0) {
        await svc.refreshAll();
      } else {
        final feeds = await _feedRepo.getByFolder(_folders[_selectedTabIndex - 1].id!);
        for (final f in feeds) { await svc.refreshFeed(f); }
      }
    } finally {
      // Step 4 — Reload unread-only: nothing previously read reappears.
      await _loadArticles(unreadOnly: true);
      if (mounted) setState(() => _refreshing = false);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.allMarkedRead)),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        centerTitle: false,
        actions: const [],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _hasFeeds
          ? Padding(
              padding: EdgeInsets.only(bottom: _folders.length > 1 ? 48.0 : 0.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'refresh',
                    onPressed: _refreshing ? null : _refreshCurrentTab,
                    tooltip: l10n.refresh,
                    mini: true,
                    child: _refreshing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'search',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SearchScreen()),
                    ),
                    tooltip: l10n.searchArticles,
                    mini: true,
                    child: const Icon(Icons.search_rounded),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton(
                    heroTag: 'mark_all_read',
                    onPressed: _markAllRead,
                    tooltip: l10n.markAllRead,
                    mini: true,
                    child: const Icon(Icons.done_all_rounded),
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
    final l10n = AppLocalizations.of(context)!;

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
      return RefreshIndicator(
        onRefresh: _refreshCurrentTab,
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.35),
            Text(
              l10n.noArticlesYet,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCurrentTab,
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        cacheExtent: 500,
        itemCount: _articles.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, i) {
          final article = _articles[i];
          final cardKey = i < _cardKeys.length ? _cardKeys[i] : null;
          return ArticleCard(
            key: cardKey,
            article: article,
            onTap: () => _openArticle(article),
            onMarkRead: () => _markRead(article),
            onMarkUnread: () => _markUnread(article),
            onShare: () => _shareService.shareArticle(article),
            onBookmark: () => _toggleSaved(article),
          );
        },
      ),
    );
  }
}
