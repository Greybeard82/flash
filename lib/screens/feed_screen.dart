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

  const FeedScreen({
    super.key,
    required this.onNavigateToFeeds,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> with WidgetsBindingObserver {
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
  int _loadGeneration = 0;
  double _savedScrollOffset = 0.0;

  Timer? _markReadDebounce;
  final Set<int> _pendingMarkRead = {};
  final List<GlobalKey?> _cardKeys = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _markReadDebounce?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAll(showLoading: false);
    }
  }

  Future<void> _init() async {
    await _loadSettings();
    await _loadAll();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadSettings() async {
    final settings = await _settingsRepo.getAll();
    _markReadOnScroll = settings.markReadOnScroll;
  }

  Future<void> _loadAll({bool showLoading = true}) async {
    if (!mounted) return;
    if (_scrollController.hasClients) {
      _savedScrollOffset = _scrollController.offset;
    }
    if (showLoading) setState(() => _loading = true);

    // Fetch folders and feeds in parallel first (articles depend on folder list)
    final (folders, feeds) = await (
      _folderRepo.getAll(),
      _feedRepo.getAll(),
    ).wait;

    final safeTabIndex = _selectedTabIndex.clamp(0, folders.length);

    // Fetch articles and counts in parallel
    final (articles, folderCounts, allCount) = await (
      _articlesForTab(safeTabIndex, folders),
      _articleRepo.getAllFolderUnreadCounts(),
      _articleRepo.getUnreadCount(),
    ).wait;

    if (mounted) {
      setState(() {
        _folders = folders;
        _hasFeeds = feeds.isNotEmpty;
        _selectedTabIndex = safeTabIndex;
        _articles = articles;
        _cardKeys
          ..clear()
          ..addAll(List.generate(articles.length, (_) => GlobalKey()));
        _folderUnreadCounts = folderCounts;
        _allUnreadCount = allCount;
        _loading = false;
      });
      _updateBadge(allCount);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _savedScrollOffset > 0) {
          _scrollController.jumpTo(
            _savedScrollOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      });
    }
  }

  Future<List<Article>> _articlesForTab(int tabIndex, List<Folder> folders) async {
    if (tabIndex == 0) return _articleRepo.getAll(includeRead: true);
    final folder = folders[tabIndex - 1];
    return _articleRepo.getForFolder(folder.id!, includeRead: true);
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

  void _onScroll() {
    if (!_markReadOnScroll) return;
    if (_articles.isEmpty) return;

    final scrollOffset = _scrollController.offset;
    double cumulative = 0.0;
    for (int i = 0; i < _articles.length; i++) {
      final key = i < _cardKeys.length ? _cardKeys[i] : null;
      double cardHeight = 120.0;
      if (key?.currentContext != null) {
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) cardHeight = box.size.height;
      }
      // Mark read when the card's midpoint scrolls above the viewport top.
      if (cumulative + cardHeight / 2 < scrollOffset) {
        final article = _articles[i];
        if (!article.isRead && article.id != null) {
          _pendingMarkRead.add(article.id!);
        }
      } else {
        break;
      }
      cumulative += cardHeight;
    }

    _markReadDebounce?.cancel();
    _markReadDebounce = Timer(const Duration(milliseconds: 250), _flushMarkRead);
  }

  Future<void> _flushMarkRead() async {
    if (_pendingMarkRead.isEmpty) return;
    final ids = Set<int>.from(_pendingMarkRead);
    _pendingMarkRead.clear();
    await _articleRepo.markManyRead(ids.toList());
    if (mounted) {
      setState(() {
        for (int i = 0; i < _articles.length; i++) {
          if (ids.contains(_articles[i].id)) {
            _articles[i] = _articles[i].copyWith(isRead: true);
          }
        }
        _allUnreadCount = (_allUnreadCount - ids.length).clamp(0, _allUnreadCount);
      });
      _updateBadge(_allUnreadCount);
    }
  }

  void _updateBadge(int count) {
    AppBadgePlus.updateBadge(count);
  }

  Future<void> _onTabSelected(int index) async {
    if (index == _selectedTabIndex) return;
    setState(() {
      _selectedTabIndex = index;
      _loading = true;
    });
    final generation = ++_loadGeneration;
    final articles = await _articlesForTab(index, _folders);
    if (mounted && generation == _loadGeneration) {
      setState(() {
        _articles = articles;
        _cardKeys
          ..clear()
          ..addAll(List.generate(articles.length, (_) => GlobalKey()));
        _loading = false;
      });
    }
  }

  Future<void> _markAllRead() async {
    // Show a one-time confirmation dialog the very first time this is tapped.
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
    if (_selectedTabIndex == 0) {
      await _articleRepo.markAllRead();
    } else {
      final folder = _folders[_selectedTabIndex - 1];
      await _articleRepo.markAllReadForFolder(folder.id!);
    }
    await _loadAll();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.allMarkedRead)),
      );
    }
  }

  Future<void> _openArticle(Article article) async {
    // Always read fresh so Settings-tab changes take effect immediately.
    final settings = await _settingsRepo.getAll();

    final wasUnread = article.id != null && !article.isRead;
    if (wasUnread) {
      await _articleRepo.markRead(article.id!);
    }

    if (!mounted) return;

    final uri = Uri.tryParse(article.url);
    if (uri == null) return;

    if (settings.readerMode) {
      final domain = uri.host;
      final cached = await _settingsRepo.get('reader_compat_$domain');

      if (cached == 'fail') {
        // Known incompatible domain — go straight to browser.
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }

      if (cached == null) {
        // Unknown domain — pre-flight HEAD check before showing reader.
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
      // Apply read state after pop so the setState doesn't cause a scroll jump.
      if (wasUnread && mounted) {
        setState(() {
          _articles = _articles.map((a) {
            if (a.id == article.id) return a.copyWith(isRead: true);
            return a;
          }).toList();
          _allUnreadCount = (_allUnreadCount - 1).clamp(0, _allUnreadCount);
        });
      }
    } else {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      // App resume is handled by didChangeAppLifecycleState(resumed).
      if (wasUnread && mounted) {
        setState(() {
          _articles = _articles.map((a) {
            if (a.id == article.id) return a.copyWith(isRead: true);
            return a;
          }).toList();
          _allUnreadCount = (_allUnreadCount - 1).clamp(0, _allUnreadCount);
        });
      }
    }
  }

  /// HEAD request to check if a URL serves HTML. Returns true if it does or
  /// if the check itself fails (optimistic — let the extractor try).
  Future<bool> _preflightIsHtml(Uri uri) async {
    try {
      final response =
          await http.head(uri).timeout(const Duration(seconds: 5));
      final ct = response.headers['content-type'] ?? '';
      return ct.contains('text/html');
    } catch (_) {
      return true;
    }
  }

  Future<void> _markRead(Article article) async {
    if (article.id == null || article.isRead) return;
    await _articleRepo.markRead(article.id!);
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {
        _articles = _articles.map((a) {
          if (a.id == article.id) return a.copyWith(isRead: true);
          return a;
        }).toList();
        _allUnreadCount = (_allUnreadCount - 1).clamp(0, _allUnreadCount);
      });
    }
  }


  Future<void> _markUnread(Article article) async {
    if (article.id == null || !article.isRead) return;
    await _articleRepo.markUnread(article.id!);
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {
        _articles = _articles.map((a) {
          if (a.id == article.id) return a.copyWith(isRead: false);
          return a;
        }).toList();
        _allUnreadCount++;
      });
    }
  }

  Future<void> _toggleSaved(Article article) async {
    if (article.id == null) return;
    final nowSaved = !article.isSaved;
    await _articleRepo.setSaved(article.id!, saved: nowSaved);
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {
        _articles = _articles.map((a) {
          if (a.id == article.id) return a.copyWith(isSaved: nowSaved);
          return a;
        }).toList();
      });
    }
  }


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
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
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
        cacheExtent: 300,
        addAutomaticKeepAlives: false,
        itemCount: _articles.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
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
