import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../models/folder.dart';
import '../models/unread_counts.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/loading_controller.dart';
import '../services/refresh_service.dart';
import '../services/session_read_tracker.dart';
import '../services/share_service.dart';
import '../utils/resume_refresh_policy.dart';
import '../widgets/article_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/folder_tab_bar.dart';
import '../widgets/notification_banner.dart';
import '../widgets/shimmer_card.dart';
import 'reader_screen.dart';
import 'search_screen.dart';

class FeedScreen extends StatefulWidget {
  final VoidCallback onNavigateToFeeds;
  final int refreshTrigger;

  const FeedScreen({
    super.key,
    required this.onNavigateToFeeds,
    this.refreshTrigger = 0,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // ── Repos & services ───────────────────────────────────────────────────────
  final _articleRepo = ArticleRepository();
  final _feedRepo = FeedRepository();
  final _folderRepo = FolderRepository();
  final _settingsRepo = SettingsRepository();
  final _shareService = ShareService();

  // ── Scroll ─────────────────────────────────────────────────────────────────
  final ScrollController _scrollController = ScrollController();
  final Map<int, double> _tabScrollPositions = {};

  // ── Banner ─────────────────────────────────────────────────────────────────
  final _bannerKey = GlobalKey<NotificationBannerState>();

  // ── Cold-start animation ───────────────────────────────────────────────────
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // ── UI state ───────────────────────────────────────────────────────────────
  List<Folder> _folders = [];
  List<Article> _articles = [];
  UnreadCounts _counts = const UnreadCounts.empty();
  Map<int, int?> _feedFolderId = {};
  int _selectedTabIndex = 0;
  bool _booting = true;
  bool _loading = false;
  bool _refreshing = false;
  bool _hasFeeds = false;
  bool _markReadOnScroll = true;
  bool _newspaperMode = false;

  final Map<int, GlobalKey> _cardKeys = {};
  int _tabGeneration = 0;

  Timer? _scrollDebounce;
  final Set<int> _pendingMarkReadUI = {};

  static const _resumePolicy = ResumeRefreshPolicy();
  DateTime? _pausedAt;
  DateTime? _lastFetchAt;

  int? _folderOf(Article a) => _feedFolderId[a.feedId];

  int _scopeForTab(int tab) =>
      tab == 0 ? kAllScope : _folders[tab - 1].id!;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _boot();
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) _fetchAndReload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollDebounce?.cancel();
    _scrollController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final resumedAt = DateTime.now();
      final shouldFetch = _resumePolicy.shouldFetch(
        pausedAt: _pausedAt,
        resumedAt: resumedAt,
        lastFetchAt: _lastFetchAt,
      );
      _pausedAt = null;
      if (_booting || _loading) return;
      if (shouldFetch) {
        _fetchOnResume();
      } else {
        _reloadArticles();
      }
    }
  }

  Future<void> _fetchOnResume() async {
    await LoadingController.instance.run(() async {
      final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
      try {
        await RefreshService(_settingsRepo).refreshAll(coldStart: false);
        _lastFetchAt = DateTime.now();
      } catch (_) {}
      await _loadArticles();
      _restoreScrollOffset(offset);
    }, label: 'Refreshing');
  }

  // ── Boot ───────────────────────────────────────────────────────────────────

  Future<void> _boot() async {
    await LoadingController.instance.run(() async {
      final settings = await _settingsRepo.getAll();
      _markReadOnScroll = settings.markReadOnScroll;
      if (mounted) setState(() => _newspaperMode = settings.newspaperMode);

      if (mounted) setState(() => _booting = true);

      // Cold start: cleanup first, then fetch.
      try {
        await RefreshService(_settingsRepo).refreshAll(coldStart: true);
        _lastFetchAt = DateTime.now();
      } catch (_) {}

      await _loadArticles();
      if (mounted) setState(() => _booting = false);
      _scrollController.addListener(_onScroll);
    }, label: 'Loading');
  }

  // ── Core data operations ───────────────────────────────────────────────────

  Future<void> _loadArticles() async {
    if (!mounted) return;
    await LoadingController.instance.run(_loadArticlesBody, label: 'Loading');
  }

  Future<void> _loadArticlesBody() async {
    final (folders, feeds) = await (
      _folderRepo.getAll(),
      _feedRepo.getAll(),
    ).wait;

    final safeTab = _selectedTabIndex.clamp(0, folders.length);

    final (articles, folderCounts, allCount) = await (
      _articlesForTab(safeTab, folders),
      _articleRepo.getAllFolderUnreadCounts(),
      _articleRepo.getTotalUnreadCount(),
    ).wait;

    if (!mounted) return;
    setState(() {
      _folders = folders;
      _hasFeeds = feeds.isNotEmpty;
      _selectedTabIndex = safeTab;
      _articles = articles;
      _syncCardKeys(articles);
      _feedFolderId = {for (final f in feeds) f.id!: f.folderId};
      _counts = UnreadCounts.fromRepository(total: allCount, byFolder: folderCounts);
      _loading = false;
    });
    AppBadgePlus.updateBadge(allCount);
  }

  Future<void> _refreshCountsFromDb() async {
    final (folderCounts, allCount) = await (
      _articleRepo.getAllFolderUnreadCounts(),
      _articleRepo.getTotalUnreadCount(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _counts = UnreadCounts.fromRepository(total: allCount, byFolder: folderCounts);
    });
    AppBadgePlus.updateBadge(allCount);
  }

  Future<void> _reloadArticles() async {
    await LoadingController.instance.run(() async {
      final offset = _scrollController.hasClients ? _scrollController.offset : 0.0;
      // Refresh newspaper mode in case it was toggled in Settings.
      final settings = await _settingsRepo.getAll();
      if (mounted) setState(() => _newspaperMode = settings.newspaperMode);
      await _loadArticles();
      _restoreScrollOffset(offset);
    }, label: 'Loading');
  }

  Future<List<Article>> _articlesForTab(int tab, List<Folder> folders) {
    final scope = tab == 0 ? kAllScope : folders[tab - 1].id!;
    final sessionIds = SessionReadTracker.instance.idsForScope(scope);
    if (tab == 0) return _articleRepo.getAllArticles(sessionReadIds: sessionIds);
    return _articleRepo.getArticlesByFolder(
      folders[tab - 1].id!,
      sessionReadIds: sessionIds,
    );
  }

  void _syncCardKeys(List<Article> articles) {
    final activeIds = {for (final a in articles) if (a.id != null) a.id!};
    _cardKeys.removeWhere((id, _) => !activeIds.contains(id));
    for (final a in articles) {
      if (a.id != null) _cardKeys.putIfAbsent(a.id!, GlobalKey.new);
    }
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

  // Re-tap of Flash tab: fetch without cleanup.
  Future<void> _fetchAndReload() async {
    if (!mounted || _refreshing) return;
    setState(() => _refreshing = true);
    await LoadingController.instance.run(() async {
      try {
        await RefreshService(_settingsRepo).refreshAll();
        _lastFetchAt = DateTime.now();
      } finally {
        await _loadArticles();
        if (mounted) setState(() => _refreshing = false);
      }
    }, label: 'Refreshing');
  }

  // Pull-to-refresh: fetch without cleanup.
  Future<void> _refreshCurrentTab() async {
    if (_refreshing) return;
    HapticFeedback.lightImpact();
    setState(() => _refreshing = true);
    await LoadingController.instance.run(() async {
      try {
        final svc = RefreshService(_settingsRepo);
        if (_selectedTabIndex == 0) {
          await svc.refreshAll();
        } else {
          final feeds = await _feedRepo.getByFolder(_folders[_selectedTabIndex - 1].id!);
          for (final f in feeds) {
            await svc.refreshFeed(f);
          }
        }
        _lastFetchAt = DateTime.now();
      } finally {
        await _loadArticles();
        if (mounted) setState(() => _refreshing = false);
      }
    }, label: 'Refreshing');
  }

  // ── Tab switching ──────────────────────────────────────────────────────────

  Future<void> _onTabSelected(int index) async {
    if (index == _selectedTabIndex) return;
    await LoadingController.instance.run(() => _onTabSelectedBody(index), label: 'Loading');
  }

  Future<void> _onTabSelectedBody(int index) async {
    if (_scrollController.hasClients) {
      _tabScrollPositions[_selectedTabIndex] = _scrollController.offset;
    }

    final gen = ++_tabGeneration;
    setState(() {
      _selectedTabIndex = index;
      _loading = true;
    });
    final articles = await _articlesForTab(index, _folders);
    if (!mounted || gen != _tabGeneration) return;
    setState(() {
      _articles = articles;
      _syncCardKeys(articles);
      _loading = false;
    });

    final savedOffset = _tabScrollPositions[index] ?? 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (savedOffset > 0) {
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(savedOffset.clamp(0.0, max));
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  // ── Mark as read on scroll ─────────────────────────────────────────────────

  void _onScroll() {
    if (!_markReadOnScroll || _articles.isEmpty) return;
    final offset = _scrollController.offset;
    double cumulative = 0.0;
    final toWrite = <int>[];
    final readFolderIds = <int?>[];
    for (final article in _articles) {
      final key = article.id != null ? _cardKeys[article.id!] : null;
      double h = 120.0;
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) h = box.size.height;
      }
      if (cumulative + h / 2 < offset) {
        if (!article.isRead && article.id != null) {
          toWrite.add(article.id!);
          readFolderIds.add(_folderOf(article));
          _pendingMarkReadUI.add(article.id!);
        }
      } else {
        break;
      }
      cumulative += h;
    }

    // DB write is immediate.
    if (toWrite.isNotEmpty) {
      _articleRepo.markManyRead(toWrite);
      SessionReadTracker.instance
          .addAll(toWrite, scope: _scopeForTab(_selectedTabIndex));
      _counts = _counts.applyManyRead(readFolderIds);
      AppBadgePlus.updateBadge(_counts.all);
    }

    // UI dim update is debounced.
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 150), _flushMarkReadUI);
  }

  void _flushMarkReadUI() {
    if (_pendingMarkReadUI.isEmpty || !mounted) return;
    final ids = Set<int>.from(_pendingMarkReadUI);
    _pendingMarkReadUI.clear();
    setState(() {
      _articles = [
        for (final a in _articles)
          ids.contains(a.id) ? a.copyWith(isRead: true) : a,
      ];
    });
    unawaited(_refreshCountsFromDb());
  }

  // ── Article actions ────────────────────────────────────────────────────────

  Future<void> _openArticle(Article article) async {
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    final settings = await _settingsRepo.getAll();
    final wasUnread = article.id != null && !article.isRead;

    // Mark read immediately and dim in-place.
    if (wasUnread) {
      await _articleRepo.markAsRead(article.id!);
      SessionReadTracker.instance
          .add(article.id!, scope: _scopeForTab(_selectedTabIndex));
      if (mounted) {
        setState(() {
          _articles = [
            for (final a in _articles)
              a.id == article.id ? a.copyWith(isRead: true) : a,
          ];
          _counts = _counts.applyRead(_folderOf(article));
        });
        AppBadgePlus.updateBadge(_counts.all);
      }
    }

    if (!mounted) return;
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
          } else {
            if (!mounted) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ReaderScreen(
                  article: article.copyWith(isRead: true),
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
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ReaderScreen(
                article: article.copyWith(isRead: true),
                fontSize: settings.articleFontSize,
                onExtractionSucceeded: () =>
                    _settingsRepo.set('reader_compat_$domain', 'ok'),
                onExtractionFailed: () =>
                    _settingsRepo.set('reader_compat_$domain', 'fail'),
              ),
            ),
          );
        }
      }
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }

    // Restore scroll — list is unchanged except the tapped card is grey.
    if (mounted) _restoreScrollOffset(scrollOffset);
  }

  Future<bool> _preflightIsHtml(Uri uri) {
    return LoadingController.instance.run(() async {
      try {
        final r = await http.head(uri).timeout(const Duration(seconds: 5));
        return (r.headers['content-type'] ?? '').contains('text/html');
      } catch (_) {
        return true;
      }
    }, label: 'Loading');
  }

  Future<void> _markRead(Article article) async {
    if (article.id == null || article.isRead) return;
    await _articleRepo.markAsRead(article.id!);
    SessionReadTracker.instance
        .add(article.id!, scope: _scopeForTab(_selectedTabIndex));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _articles = [
        for (final a in _articles)
          a.id == article.id ? a.copyWith(isRead: true) : a,
      ];
      _counts = _counts.applyRead(_folderOf(article));
    });
    AppBadgePlus.updateBadge(_counts.all);
  }

  Future<void> _markUnread(Article article) async {
    if (article.id == null || !article.isRead) return;
    await _articleRepo.markAsUnread(article.id!);
    SessionReadTracker.instance.removeEverywhere(article.id!);
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _articles = [
        for (final a in _articles)
          a.id == article.id ? a.copyWith(isRead: false) : a,
      ];
      _counts = _counts.applyUnread(_folderOf(article));
    });
    AppBadgePlus.updateBadge(_counts.all);
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
    HapticFeedback.mediumImpact();
    await LoadingController.instance.run(_markAllReadBody, label: 'Marking all read');
  }

  Future<void> _markAllReadBody() async {
    final settings = await _settingsRepo.getAll();
    final cleanupDays = settings.cleanupAgeDays;

    if (_selectedTabIndex == 0) {
      // All tab: mark all read, clear tracker, run cleanup, cold-start fetch.
      await _articleRepo.markAllAsRead();
      SessionReadTracker.instance.clear();
      await _articleRepo.runCleanup(days: cleanupDays);

      if (!mounted) return;
      setState(() {
        _booting = true;
        _counts = _counts.clearedAll();
      });
      AppBadgePlus.updateBadge(0);
      try {
        await RefreshService(_settingsRepo).refreshAll(coldStart: false);
        _lastFetchAt = DateTime.now();
      } catch (_) {}
      await _loadArticles();
      if (mounted) setState(() => _booting = false);
    } else {
      // Category tab: mark read, remove folder's IDs from tracker, cleanup, refresh folder.
      final folderId = _folders[_selectedTabIndex - 1].id!;

      if (mounted) setState(() => _counts = _counts.clearedFolder(folderId));

      await _articleRepo.markAllAsReadByFolder(folderId);
      SessionReadTracker.instance.clearScope(folderId);
      await _articleRepo.runCleanup(folderId: folderId, days: cleanupDays);

      // Refresh feeds in this folder.
      try {
        final svc = RefreshService(_settingsRepo);
        final feeds = await _feedRepo.getByFolder(folderId);
        for (final f in feeds) {
          await svc.refreshFeed(f);
        }
      } catch (_) {}

      final (folderCounts, allCount) = await (
        _articleRepo.getAllFolderUnreadCounts(),
        _articleRepo.getTotalUnreadCount(),
      ).wait;

      if (!mounted) return;
      final freshArticles = await _articlesForTab(_selectedTabIndex, _folders);
      if (!mounted) return;
      setState(() {
        _articles = freshArticles;
        _syncCardKeys(freshArticles);
        _counts = UnreadCounts.fromRepository(total: allCount, byFolder: folderCounts);
      });
      AppBadgePlus.updateBadge(allCount);
      _bannerKey.currentState?.show(AppLocalizations.of(context)!.allMarkedRead);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: _newspaperMode ? _NewspaperMasthead() : Text(l10n.appTitle),
        centerTitle: false,
        actions: const [],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _hasFeeds && !_booting
          ? Padding(
              padding: EdgeInsets.only(
                  bottom: _folders.length > 1 ? FolderTabBar.barHeight : 0.0),
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
          NotificationBanner(key: _bannerKey),
          Expanded(child: _buildContent()),
          if (_hasFeeds && _folders.length > 1)
            FolderTabBar(
              folders: _folders,
              selectedIndex: _selectedTabIndex,
              folderUnreadCounts: _counts.byFolder,
              allUnreadCount: _counts.all,
              onTabSelected: _onTabSelected,
              onMarkAllRead: _markAllRead,
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final l10n = AppLocalizations.of(context)!;

    if (!_hasFeeds && !_booting) {
      return EmptyState(onAddFeed: widget.onNavigateToFeeds);
    }

    if (_booting) return _BootingAnimation(animation: _pulseAnim);

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
              l10n.noNewArticles,
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
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        child: ListView.separated(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          cacheExtent: 500,
          itemCount: _articles.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: (context, i) {
            final article = _articles[i];
            final cardKey = article.id != null ? _cardKeys[article.id!] : null;
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
      ),
    );
  }
}

class _NewspaperMasthead extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final today = DateTime.now();
    final dateline =
        'INTERNATIONAL EDITION · ${today.day.toString().padLeft(2, '0')}.'
        '${today.month.toString().padLeft(2, '0')}.${today.year}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Flash',
          style: TextStyle(
            fontFamily: 'Playfair Display',
            fontWeight: FontWeight.w700,
            fontSize: 26,
            color: ink,
            height: 1.1,
          ),
        ),
        Divider(height: 3, thickness: 1, color: ink.withValues(alpha: 0.4)),
        Text(
          dateline,
          style: TextStyle(
            fontFamily: 'PT Serif',
            fontSize: 9,
            letterSpacing: 0.8,
            color: ink.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

class _BootingAnimation extends StatelessWidget {
  final Animation<double> animation;
  const _BootingAnimation({required this.animation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: animation,
            child: Image.asset('assets/images/bolt_logo.png', width: 72, height: 72),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.refresh,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
