import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../models/folder.dart';
import '../models/settings.dart';
import '../models/unread_counts.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/loading_controller.dart';
import '../services/read_state_notifier.dart';
import '../services/refresh_service.dart';
import '../services/session_read_tracker.dart';
import '../services/settings_notifier.dart';
import '../services/share_service.dart';
import '../utils/bottom_dwell_timer.dart';
import '../utils/constants.dart';
import '../utils/resume_refresh_policy.dart';
import '../widgets/article_card.dart';
import '../widgets/bubble_panel.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_bubble.dart';
import '../widgets/quick_settings_bubble.dart';
import '../widgets/scroll_fade.dart';
import '../widgets/fetching_indicator.dart';
import '../widgets/folder_tab_bar.dart';
import '../widgets/notification_banner.dart';
import '../widgets/shimmer_card.dart';
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
    with WidgetsBindingObserver {
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

  // ── UI state ───────────────────────────────────────────────────────────────
  List<Folder> _folders = [];
  List<Article> _articles = [];
  UnreadCounts _counts = const UnreadCounts.empty();
  Map<int, int?> _feedFolderId = {};
  int _selectedTabIndex = 0;
  bool _booting = true;

  /// A background feed fetch is in flight — drives the small app-bar bolt.
  bool _backgroundFetching = false;
  bool _loading = false;
  bool _refreshing = false;
  bool _hasFeeds = false;
  bool _markReadOnScroll = true;
  bool _newspaperMode = false;

  final Map<int, GlobalKey> _cardKeys = {};
  int _tabGeneration = 0;

  Timer? _scrollDebounce;
  final Set<int> _pendingMarkReadUI = {};

  /// Drives the fade on every floating button while the list is moving. One
  /// controller for the whole cluster — a sixth button is a `ScrollFade`
  /// wrapper, not another copy of this.
  final _fabFade = ScrollFadeController();

  /// Anchors for the two top buttons, so their bubbles can grow out of them.
  final _filterFabKey = GlobalKey();
  final _quickSettingsFabKey = GlobalKey();
  OverlayEntry? _openBubble;
  late final BottomDwellTimer _bottomDwellTimer =
      BottomDwellTimer(onComplete: _onBottomDwellComplete);

  /// Feed ordering. Applied to the loaded list rather than in SQL, so the
  /// repository queries — which several other screens share — stay untouched.
  String _sortOrder = kSortNewestFirst;

  /// The repository always returns newest-first; reverse when the user has
  /// asked for oldest-first. List order is also visual order, which is what
  /// the scroll-to-mark-read pass walks, so it stays consistent either way.
  List<Article> _applySortOrder(List<Article> articles) =>
      _sortOrder == kSortOldestFirst ? articles.reversed.toList() : articles;

  /// Filter-bubble values, applied to what the feed *shows*.
  ///
  /// These are the same two settings the Settings screen edits, but that
  /// screen frames them as storage rules — `article_limit` caps what a fetch
  /// accepts, `cleanup_age_days` drives the purge of old read articles. Both
  /// are invisible from the feed: the fetch cap changes nothing already
  /// stored, and cleanup only ever removes articles you have already read,
  /// on a cold start. Moving either slider therefore appeared to do nothing.
  ///
  /// The Filter bubble means what it says, so the same values now also filter
  /// the visible list, immediately.
  int _displayLimit = kFetchArticleLimit;
  int _displayAgeDays = 7;

  /// Applies the Filter bubble's two limits to a newest-first list.
  ///
  /// Age first, then the count cap **per feed** — matching the setting's own
  /// name and keeping the All tab the union of every feed's allowance rather
  /// than a single pool that one busy feed could fill on its own.
  List<Article> _applyDisplayFilters(List<Article> newestFirst) {
    final cutoffMs = DateTime.now()
        .subtract(Duration(days: _displayAgeDays))
        .millisecondsSinceEpoch;

    final perFeed = <int, int>{};
    final kept = <Article>[];
    for (final a in newestFirst) {
      // A null published date shouldn't reach the DB (applyFetchThresholds
      // drops those), but if one does, show it rather than silently hiding it.
      if (a.publishedAt != null && a.publishedAt! < cutoffMs) continue;
      final seen = perFeed[a.feedId] ?? 0;
      if (seen >= _displayLimit) continue;
      perFeed[a.feedId] = seen + 1;
      kept.add(a);
    }
    return kept;
  }

  /// Applies every setting the feed reacts to. Called at boot and again
  /// whenever Settings or a bubble reports a change — this screen is never
  /// rebuilt on a plain tab switch, so without the listener a change wouldn't
  /// take effect until the app restarted.
  void _applyReadingSettings(AppSettings settings) {
    _markReadOnScroll = settings.markReadOnScroll;
    _sortOrder = settings.articleSortOrder;
    _displayLimit = settings.articleLimit;
    _displayAgeDays = settings.cleanupAgeDays;
    _bottomDwellTimer.configure(
      enabled: settings.autoMarkReadAtBottom,
      duration: Duration(seconds: settings.autoMarkReadAtBottomSeconds),
    );
  }

  Future<void> _onSettingsChanged() async {
    final settings = await _settingsRepo.getAll();
    if (!mounted) return;

    final orderChanged = settings.articleSortOrder != _sortOrder;
    // A widened filter needs rows the current list no longer holds, so it
    // can't be satisfied in memory — re-query instead.
    final filtersChanged = settings.articleLimit != _displayLimit ||
        settings.cleanupAgeDays != _displayAgeDays;

    setState(() {
      _applyReadingSettings(settings);
      _newspaperMode = settings.newspaperMode;
      // Flip the list already on screen rather than waiting for the next
      // reload — the user changed the order to see it change.
      if (orderChanged && !filtersChanged) {
        _articles = _articles.reversed.toList();
      }
    });

    if (!filtersChanged) return;
    final refreshed = await _articlesForTab(_selectedTabIndex, _folders);
    if (!mounted) return;
    setState(() {
      _articles = refreshed;
      _syncCardKeys(refreshed);
    });
  }

  static const _resumePolicy = ResumeRefreshPolicy();
  DateTime? _pausedAt;
  DateTime? _lastFetchAt;

  int? _folderOf(Article a) => _feedFolderId[a.feedId];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bookmarks and Search mutate read state without owning the counts —
    // re-query them from the DB when they do, so every badge (and the
    // launcher badge, updated inside _refreshCountsFromDb) stays truthful
    // without this screen being rebuilt or reloaded.
    ReadStateNotifier.instance.addListener(_onExternalReadStateChanged);
    SettingsNotifier.instance.addListener(_onSettingsChanged);
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
    ReadStateNotifier.instance.removeListener(_onExternalReadStateChanged);
    SettingsNotifier.instance.removeListener(_onSettingsChanged);
    _scrollDebounce?.cancel();
    _bottomDwellTimer.cancel();
    _fabFade.dispose();
    if (_openBubble?.mounted ?? false) _openBubble!.remove();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
      // Don't complete a bulk mark-as-read the user didn't witness while
      // the app sits in the background.
      _bottomDwellTimer.cancel();
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

  /// Resume from background. Same indicator as cold start, so the two read as
  /// one behaviour rather than two — and the user keeps their scroll position.
  Future<void> _fetchOnResume() => _backgroundRefresh(preserveScroll: true);

  /// A refresh threw. These were previously swallowed silently, so on a
  /// captive-portal wifi or an expired certificate the spinner simply
  /// finished and nothing changed, with no explanation. The banner this
  /// screen already owns is the natural place to say so.
  void _reportRefreshFailure() {
    if (!mounted) return;
    _bannerKey.currentState?.show(AppLocalizations.of(context)!.refreshFailed);
  }

  // ── Boot ───────────────────────────────────────────────────────────────────

  /// Cold start, in the order that gets readable content on screen soonest.
  ///
  /// This used to run cleanup *and* a full network fetch behind a full-screen
  /// pulse, so opening the app on a slow connection meant staring at an
  /// animation while a perfectly good cached list sat on disk. Now: clean,
  /// show what's already there, then fetch in the background behind a small
  /// app-bar indicator.
  Future<void> _boot() async {
    final settings = await _settingsRepo.getAll();
    _applyReadingSettings(settings);
    if (mounted) setState(() => _newspaperMode = settings.newspaperMode);

    // 1. Cleanup first, so the list we're about to show is already purged of
    //    stale read articles rather than shedding rows a moment later.
    try {
      await _articleRepo.runCleanup(days: settings.cleanupAgeDays);
    } catch (_) {
      // Cleanup is housekeeping; a failure must not hold up the feed.
    }

    // 2. Show the cached list immediately. No network in the way.
    await _loadArticles();
    if (mounted) setState(() => _booting = false);
    _scrollController.addListener(_onScroll);

    // 3. Fetch in the background.
    unawaited(_backgroundRefresh());
  }

  /// Network fetch that never covers the content. Shared by cold start and
  /// resume so the two look the same.
  Future<void> _backgroundRefresh({bool preserveScroll = false}) async {
    if (!mounted || _backgroundFetching) return;
    setState(() => _backgroundFetching = true);

    final offset = preserveScroll && _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    try {
      await RefreshService(_settingsRepo).refreshAll();
      _lastFetchAt = DateTime.now();
    } catch (_) {
      _reportRefreshFailure();
    }
    await _loadArticles();
    if (preserveScroll) _restoreScrollOffset(offset);
    if (mounted) setState(() => _backgroundFetching = false);
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

  /// An article was read/unread from Bookmarks or Search. Only the counts
  /// need re-querying — the visible article list is deliberately left alone,
  /// matching the existing rule that an article read outside the current tab
  /// is simply absent from it rather than dimmed in place (PRD §4.3).
  void _onExternalReadStateChanged() {
    if (!mounted || _booting) return;
    unawaited(_refreshCountsFromDb());
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
      // Pick up anything changed in Settings while we were away.
      final settings = await _settingsRepo.getAll();
      if (mounted) {
        setState(() {
          _applyReadingSettings(settings);
          _newspaperMode = settings.newspaperMode;
        });
      }
      await _loadArticles();
      _restoreScrollOffset(offset);
    }, label: 'Loading');
  }

  /// The one place articles enter this screen, so ordering is applied here and
  /// every path — boot, reload, tab switch, refresh — gets it for free.
  Future<List<Article>> _articlesForTab(int tab, List<Folder> folders) async {
    // Every tab passes the whole session set: an article read anywhere stays
    // visible, dimmed in place, in every tab for the rest of the session.
    final sessionIds = SessionReadTracker.instance.ids;
    final articles = tab == 0
        ? await _articleRepo.getAllArticles(sessionReadIds: sessionIds)
        : await _articleRepo.getArticlesByFolder(
            folders[tab - 1].id!,
            sessionReadIds: sessionIds,
          );
    // Filters run on the newest-first result, so the cap keeps the newest N
    // per feed; ordering is applied last.
    return _applySortOrder(_applyDisplayFilters(articles));
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
      } catch (_) {
        _reportRefreshFailure();
      } finally {
        await _loadArticles();
        if (mounted) setState(() => _refreshing = false);
      }
    }, label: 'Refreshing');
  }

  // Pull-to-refresh: fetch without cleanup.
  /// [dropReadArticles] clears the rows the user has already read out of the
  /// list, leaving only unread ones — the refresh *button*'s behaviour, so it
  /// reads as "tidy up and show me what's new".
  ///
  /// Pull-to-refresh deliberately does not do this: it is a "check for new
  /// content" gesture, and having the list collapse under the finger that
  /// just pulled it would be the same disorienting jump the session-read
  /// model exists to avoid.
  Future<void> _refreshCurrentTab({bool dropReadArticles = false}) async {
    if (_refreshing) return;
    HapticFeedback.lightImpact();
    setState(() => _refreshing = true);

    if (dropReadArticles) {
      // Forgetting them in the session set is all it takes — the union query
      // only keeps a read article visible because its id is in there.
      SessionReadTracker.instance.removeAll(
        [for (final a in _articles) if (a.isRead && a.id != null) a.id!],
      );
    }

    await LoadingController.instance.run(() async {
      try {
        final svc = RefreshService(_settingsRepo);
        if (_selectedTabIndex == 0) {
          await svc.refreshAll();
        } else {
          final feeds =
              await _feedRepo.getByFolder(_folders[_selectedTabIndex - 1].id!);
          // One pass for the whole folder: looping refreshFeed re-read the
          // keyword and alert tables per feed and serialised every fetch.
          await svc.refreshFeeds(feeds);
        }
        _lastFetchAt = DateTime.now();
      } catch (_) {
        _reportRefreshFailure();
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
    _bottomDwellTimer.cancel();
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
    // Before the early return below: the fade has to work whether or not
    // mark-read-on-scroll is switched on.
    _fabFade.onScroll();
    _updateBottomDwellTimer();
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
      SessionReadTracker.instance.addAll(toWrite);
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

  // ── Delayed mark-all-as-read on reaching the bottom of a feed ──────────────

  void _updateBottomDwellTimer() {
    if (_articles.isEmpty || !_scrollController.hasClients) {
      _bottomDwellTimer.cancel();
      return;
    }
    _bottomDwellTimer
        .updateAtBottom(_scrollController.position.extentAfter == 0);
  }

  Future<void> _onBottomDwellComplete() async {
    if (!mounted || _articles.isEmpty) return;

    // Reuse the exact same per-article read path used elsewhere (tap/swipe
    // to read) so unread-count propagation to every tab an article appears
    // in — its own category and "All" — stays consistent with the rest of
    // the app, rather than a bespoke bulk-update path.
    if (_selectedTabIndex == 0) {
      await _articleRepo.markAllAsRead();
    } else {
      await _articleRepo.markAllAsReadByFolder(_folders[_selectedTabIndex - 1].id!);
    }
    SessionReadTracker.instance
        .addAll([for (final a in _articles) if (a.id != null) a.id!]);

    if (!mounted) return;
    setState(() {
      _articles = [for (final a in _articles) a.copyWith(isRead: true)];
    });
    unawaited(_refreshCountsFromDb());
  }

  // ── Article actions ────────────────────────────────────────────────────────

  Future<void> _openArticle(Article article) async {
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    final wasUnread = article.id != null && !article.isRead;

    // Mark read immediately and dim in-place.
    if (wasUnread) {
      await _articleRepo.markAsRead(article.id!);
      SessionReadTracker.instance.add(article.id!);

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

    await launchUrl(uri, mode: LaunchMode.externalApplication);

    // Restore scroll — list is unchanged except the tapped card is grey.
    if (mounted) _restoreScrollOffset(scrollOffset);
  }

  Future<void> _markRead(Article article) async {
    if (article.id == null || article.isRead) return;
    await _articleRepo.markAsRead(article.id!);
    SessionReadTracker.instance.add(article.id!);

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
    SessionReadTracker.instance.remove(article.id!);
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
      } catch (_) {
        _reportRefreshFailure();
      }
      await _loadArticles();
      if (mounted) setState(() => _booting = false);
    } else {
      // Category tab: mark read, forget this tab's IDs, cleanup, refresh folder.
      final folderId = _folders[_selectedTabIndex - 1].id!;

      // Exactly the articles this tab was showing when the action ran. The
      // session set is global now, so clearing it wholesale would also forget
      // articles read in other tabs — un-dimming them and then hiding them on
      // the next query, in lists the user never touched.
      final dismissedIds = [
        for (final a in _articles) if (a.id != null) a.id!,
      ];

      if (mounted) setState(() => _counts = _counts.clearedFolder(folderId));

      await _articleRepo.markAllAsReadByFolder(folderId);
      SessionReadTracker.instance.removeAll(dismissedIds);
      await _articleRepo.runCleanup(folderId: folderId, days: cleanupDays);

      // Refresh feeds in this folder — one pass, not one call per feed.
      var refreshFailed = false;
      try {
        final feeds = await _feedRepo.getByFolder(folderId);
        await RefreshService(_settingsRepo).refreshFeeds(feeds);
      } catch (_) {
        refreshFailed = true;
      }

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
      final l10n = AppLocalizations.of(context)!;
      // The mark-all-read itself succeeded either way; say so, but don't
      // claim the feeds refreshed when they didn't.
      _bannerKey.currentState
          ?.show(refreshFailed ? l10n.refreshFailed : l10n.allMarkedRead);
    }
  }

  // ── Top bubbles ────────────────────────────────────────────────────────────

  /// Opens one bubble at a time, growing out of [anchorKey]'s button.
  Future<void> _openBubblePanel(
    GlobalKey anchorKey,
    Widget Function(AppSettings settings) contentBuilder,
  ) async {
    if (_openBubble?.mounted ?? false) return;
    // The panels edit live settings, so they open against a fresh read rather
    // than whatever this screen happened to cache at boot.
    final settings = await _settingsRepo.getAll();
    if (!mounted) return;

    _fabFade.settleNow();
    _openBubble = showBubblePanel(
      context: context,
      anchorKey: anchorKey,
      child: contentBuilder(settings),
    );
  }

  void _openFilterBubble() => _openBubblePanel(
        _filterFabKey,
        (settings) => FilterBubble(initial: settings),
      );

  void _openQuickSettingsBubble() => _openBubblePanel(
        _quickSettingsFabKey,
        (settings) => QuickSettingsBubble(initial: settings),
      );

  /// The two top buttons. Same mini-FAB styling and horizontal position as the
  /// bottom cluster, anchored to the top instead.
  Widget _topFabCluster(AppLocalizations l10n) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScrollFade(
              controller: _fabFade,
              child: FloatingActionButton(
                key: _quickSettingsFabKey,
                heroTag: 'quick_settings',
                onPressed: _openQuickSettingsBubble,
                tooltip: l10n.quickSettingsTooltip,
                mini: true,
                child: const Icon(Icons.tune_rounded),
              ),
            ),
            const SizedBox(height: 8),
            ScrollFade(
              controller: _fabFade,
              child: FloatingActionButton(
                key: _filterFabKey,
                heroTag: 'filter',
                onPressed: _openFilterBubble,
                tooltip: l10n.filterTooltip,
                mini: true,
                child: const Icon(Icons.filter_alt_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: _newspaperMode ? _NewspaperMasthead() : Text(l10n.appTitle),
        centerTitle: false,
        actions: [
          // Background fetch lives here rather than over the content.
          AnimatedOpacity(
            opacity: _backgroundFetching ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(child: FetchingIndicator()),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _hasFeeds && !_booting
          ? Padding(
              padding: EdgeInsets.only(
                  bottom: _folders.length > 1 ? FolderTabBar.barHeight : 0.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ScrollFade(
                    controller: _fabFade,
                    child: FloatingActionButton(
                      heroTag: 'refresh',
                      onPressed: _refreshing
                          ? null
                          : () => _refreshCurrentTab(dropReadArticles: true),
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
                  ),
                  const SizedBox(height: 8),
                  ScrollFade(
                    controller: _fabFade,
                    child: FloatingActionButton(
                      heroTag: 'search',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SearchScreen()),
                      ),
                      tooltip: l10n.searchArticles,
                      mini: true,
                      child: const Icon(Icons.search_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ScrollFade(
                    controller: _fabFade,
                    child: FloatingActionButton(
                      heroTag: 'mark_all_read',
                      onPressed: _markAllRead,
                      tooltip: l10n.markAllRead,
                      mini: true,
                      child: const Icon(Icons.done_all_rounded),
                    ),
                  ),
                ],
              ),
            )
          : null,
      body: Stack(
        children: [
          Column(
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
          // Top button cluster, aligned with the bottom one. In the body's
          // Stack rather than `floatingActionButton:`, which only supports a
          // single positioned child.
          if (_hasFeeds && !_booting)
            Align(
              alignment: Alignment.topRight,
              child: _topFabCluster(l10n),
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

    // Boot is now just the local DB read, which is quick — a skeleton covers
    // it without hiding the app the way the old full-screen pulse did.
    if (_booting || _loading) {
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
