import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
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
import '../services/feeds_changed_notifier.dart';
import '../services/loading_controller.dart';
import '../services/read_state_notifier.dart';
import '../services/refresh_service.dart';
import '../services/saved_state_notifier.dart';
import '../services/settings_notifier.dart';
import '../services/share_service.dart';
import '../utils/bottom_dwell_timer.dart';
import '../utils/day_grouping.dart';
import '../utils/mark_read_gate.dart';
import '../utils/retirement_frontier.dart';
import '../utils/constants.dart';
import '../utils/resume_refresh_policy.dart';
import '../reading/read_gate.dart';
import '../reading/retirement_queue.dart';
import '../reading/scroll_anchor.dart';
import '../utils/diag_log.dart';
import '../widgets/article_card.dart';
import '../widgets/bubble_panel.dart';
import '../widgets/day_header.dart';
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

  /// Whether this screen is the one the IndexedStack is currently showing.
  /// The stack keeps all four screens alive, so this is the only signal that
  /// the user has arrived back here.
  final bool isVisible;

  const FeedScreen({
    super.key,
    required this.onNavigateToFeeds,
    this.refreshTrigger = 0,
    this.isVisible = true,
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
  /// Where each tab was, remembered as *an article* rather than a pixel
  /// offset.
  ///
  /// Keyed by scope id — the folder id, or kAllScope for the All tab — so
  /// reordering or adding a folder cannot hand a tab someone else's position.
  /// The map it replaced was keyed by tab index and had exactly that bug.
  ///
  /// A pixel offset is only meaningful against the list that produced it, and
  /// by restore time that list has usually lost its read rows, lost retired
  /// rows, and gained fetched ones. See [ScrollAnchor].
  final Map<int, ScrollAnchor> _tabAnchors = {};

  /// When the app last reached `resumed`, for [ReadGate]'s grace window.
  ///
  /// Starts at the epoch so a cold start is never inside the window — there
  /// is nothing to protect against before the first background/foreground
  /// cycle, and a fresh launch that blocked reads would be its own bug.
  DateTime _lastResumeAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Rows that have scrolled past the frontier and are waiting to be
  /// deleted. Nothing here is removed from the list or the database until one
  /// of the four flush points runs. See [RetirementQueue].
  final RetirementQueue _retirementQueue = RetirementQueue();

  // ── Banner ─────────────────────────────────────────────────────────────────
  final _bannerKey = GlobalKey<NotificationBannerState>();

  // ── UI state ───────────────────────────────────────────────────────────────
  List<Folder> _folders = [];
  List<Article> _articles = [];

  /// The rendered list: [_articles] with day headers interleaved.
  List<FeedRow> _rows = const [];
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

  /// Guards the mark-as-read pass against programmatic scrolling. See
  /// [MarkReadGate] — this is what stops a refresh from reading the articles
  /// it just fetched.
  final _markReadGate = MarkReadGate();

  /// Last known rendered height per article id.
  ///
  /// ListView.builder disposes rows beyond cacheExtent, so a row that has
  /// scrolled well above the viewport has no context and cannot be measured —
  /// which is exactly the row whose height the frontier arithmetic depends on.
  /// Every row was measurable while it was on screen, so remember it.
  ///
  /// Pruned alongside _cardKeys in _syncCardKeys; an unbounded map on a
  /// scrolling list is its own bug.
  final Map<int, double> _measuredHeights = {};

  // -- Pass 10 instrumentation (debug only) --
  /// Best available answer to "why did the offset just change", maintained
  /// from the notification stream. A ScrollController listener cannot tell
  /// you this, which is the whole reason this investigation needs it.
  String _scrollSource = 'unknown';

  /// Set around every programmatic jump so _onScroll can attribute the
  /// resulting callback honestly rather than guessing from the delta.
  bool _programmaticScroll = false;

  /// Previous offset, for the delta column.
  double _lastLoggedOffset = 0.0;

  /// Runs [jump] with the scroll source pinned for the duration, including
  /// the synchronous _onScroll callbacks it triggers.
  void _asProgrammatic(String label, void Function() jump) {
    _programmaticScroll = true;
    _scrollSource = label;
    try {
      jump();
    } finally {
      _programmaticScroll = false;
    }
  }

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

  /// Whether read articles stay in the list until the next refresh, rather
  /// than being retired as they scroll past. See AppSettings.showRead.
  bool _showRead = true;

  /// Scopes whose badge is forced to zero because the user reached the bottom.
  /// Folder id, or [kAllScope] for the All tab.
  ///
  /// Display-only: the articles stay unread in the database until something
  /// actually marks them. Cleared when new articles arrive for the scope, or
  /// on cold start — a scope with genuinely new unread content has to show it.
  final Set<int> _zeroedScopes = {};

  /// The scope the selected tab represents, for [_zeroedScopes].
  int get _currentScope => _selectedTabIndex == 0
      ? kAllScope
      : (_folders[_selectedTabIndex - 1].id ?? kAllScope);

  void _clearZeroedScopes() => _zeroedScopes.clear();

  /// Applies the Filter bubble's two limits to a newest-first list.
  ///
  /// Age first, then the count cap **per feed** — matching the setting's own
  /// name and keeping the All tab the union of every feed's allowance rather
  /// than a single pool that one busy feed could fill on its own.
  List<Article> _applyDisplayFilters(List<Article> newestFirst) {
    // Shared with the unread counts so the badge and the list cannot drift.
    final cutoffMs = displayCutoffMs(_displayAgeDays);

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
    _showRead = settings.showRead;
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
    final visibilityChanged = settings.showRead != _showRead;
    final filtersChanged = settings.articleLimit != _displayLimit ||
        settings.cleanupAgeDays != _displayAgeDays ||
        visibilityChanged;

    setState(() {
      _applyReadingSettings(settings);
      _newspaperMode = settings.newspaperMode;
      // Flip the list already on screen rather than waiting for the next
      // reload — the user changed the order to see it change.
      if (orderChanged && !filtersChanged) {
        _setArticles(_articles.reversed.toList());
      }
    });

    if (!filtersChanged) return;
    final refreshed = await _articlesForTab(_selectedTabIndex, _folders);
    if (!mounted) return;
    setState(() {
      _setArticles(refreshed);
    });
    // The list just changed length substantially; leaving the offset where it
    // was would land the user somewhere arbitrary.
    if (visibilityChanged) _resetScrollToTop();
    // The counts are windowed by the same setting the list is, so moving the
    // Article age slider changes both. Without this the list re-queries and
    // the badge keeps its old number — the two disagreeing again, which is
    // the whole thing this pass set out to stop.
    unawaited(_refreshCountsFromDb());
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
    // Bookmarks toggles the saved flag on articles this list may be holding,
    // and it is kept alive alongside this screen, so the change would
    // otherwise never reach here. (Feed/folder structure changes use
    // FeedsChangedNotifier instead — see _consumeFeedsChange.)
    SavedStateNotifier.instance.addListener(_onExternalSavedStateChanged);
    _boot();
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) {
      _fetchAndReload();
      return;
    }
    // Arrived back on the Flash tab. Apply anything the Categories or
    // Settings screens changed while this one was hidden.
    if (widget.isVisible && !oldWidget.isVisible) {
      unawaited(_consumeFeedsChange());
    }
  }

  /// Acts on a feed or folder change made on another tab.
  ///
  /// Nothing is consumed while a boot or refresh is already in flight — the
  /// change stays queued and is picked up on the next visit, rather than
  /// racing a fetch that is already running.
  Future<void> _consumeFeedsChange() async {
    if (!mounted || _booting || _refreshing || _backgroundFetching) return;
    final change = FeedsChangedNotifier.instance.consume();
    if (change == null) return;

    if (change == FeedsChange.needsFetch) {
      // A new feed has no articles yet. _backgroundRefresh reloads and
      // resets to top on its own.
      await _backgroundRefresh();
    } else {
      // Removed, moved or renamed — everything needed is already local.
      await _loadArticles();
      _resetScrollToTop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReadStateNotifier.instance.removeListener(_onExternalReadStateChanged);
    SettingsNotifier.instance.removeListener(_onSettingsChanged);
    SavedStateNotifier.instance.removeListener(_onExternalSavedStateChanged);
    _scrollDebounce?.cancel();
    _bottomDwellTimer.cancel();
    _fabFade.dispose();
    if (_openBubble?.mounted ?? false) _openBubble!.remove();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    DiagLog.lifecycleState = state.name;
    DiagLog.lifecycle(
      state: state.name,
      restoredOffset:
          _scrollController.hasClients ? _scrollController.offset : null,
      anchorId: null,
    );
    if (state == AppLifecycleState.resumed) {
      _lastResumeAt = DateTime.now();
      DiagLog.lastResumeAt = _lastResumeAt;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Captured on the way out, while the list is still laid out and every
      // visible row can be measured. `inactive` is included because it is the
      // first transition of both the lock and the app-switch sequences, and
      // it is the last moment the position is definitely trustworthy.
      _captureAnchor();
    }
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

  /// Resume from background with a fetch. Same indicator as cold start, so
  /// the two read as one behaviour.
  Future<void> _fetchOnResume() => _backgroundRefresh();

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
    _clearZeroedScopes();
    await _loadArticles();
    if (mounted) setState(() => _booting = false);
    _scrollController.addListener(_onScroll);

    // 3. Fetch in the background.
    unawaited(_backgroundRefresh());
  }

  /// Network fetch that never covers the content. Shared by cold start and
  /// resume so the two look the same.
  Future<void> _backgroundRefresh() async {
    if (!mounted || _backgroundFetching) return;
    setState(() => _backgroundFetching = true);
    await _fetchAndApply();
    if (mounted) setState(() => _backgroundFetching = false);
  }

  /// Fetches, then decides whether anything actually arrived before touching
  /// the list.
  ///
  /// Retirement happens *after* the decision, not before. Retiring first would
  /// delete read rows even in the case where the user is meant to see nothing
  /// change at all — and they would then vanish at the next unrelated rebuild,
  /// which reads as a random glitch.
  ///
  /// "Visible" not "inserted": an article can be inserted and then hidden by
  /// the age filter, the per-feed cap or a blocklist match. Triggering on
  /// inserts would jump the user to the top to see nothing new.
  ///
  /// The list is either left completely alone or rebuilt from scratch and
  /// reset to the top, so this never removes a row from a list the user is
  /// looking at mid-position.
  Future<void> _fetchAndApply() async {
    final beforeIds = _articles.map((a) => a.id).toSet();

    try {
      await RefreshService(_settingsRepo).refreshAll();
      _lastFetchAt = DateTime.now();
    } catch (_) {
      _reportRefreshFailure();
    }

    if (!mounted) return;
    final folders = await _folderRepo.getAll();
    if (!mounted) return;
    final probe = await _articlesForTab(_selectedTabIndex, folders);
    final hasNew = probe.any((a) => !beforeIds.contains(a.id));

    if (!hasNew) {
      await _refreshCountsFromDb();
      return; // nothing moves
    }

    await _articleRepo.retireAllRead();
    await _loadArticles();
    _resetScrollToTop();
    _clearZeroedScopes();
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
      _articleRepo.getAllFolderUnreadCounts(windowDays: _displayAgeDays),
      _articleRepo.getTotalUnreadCount(windowDays: _displayAgeDays),
    ).wait;

    if (!mounted) return;
    setState(() {
      _folders = folders;
      _hasFeeds = feeds.isNotEmpty;
      _selectedTabIndex = safeTab;
      _setArticles(articles);
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

  /// Patches the one article in place rather than re-querying — the saved
  /// flag only drives the radial menu's icon, and a reload here would rebuild
  /// the list and move the scroll position under the user.
  ///
  /// Bails out when the list already agrees, which is exactly the case when
  /// this screen made the change itself and [_toggleSaved] has already
  /// applied it.
  void _onExternalSavedStateChanged() {
    if (!mounted) return;
    final id = SavedStateNotifier.instance.articleId;
    if (id == null) return;
    final saved = SavedStateNotifier.instance.saved;

    // Bookmarked from another screen: same exemption as _toggleSaved.
    if (saved) _retirementQueue.release(id);

    final current = _articles.indexWhere((a) => a.id == id);
    if (current < 0 || _articles[current].isSaved == saved) return;

    setState(() {
      _setArticles([
        for (final a in _articles)
          a.id == id ? a.copyWith(isSaved: saved) : a,
      ]);
    });
  }

  /// Re-reads the counts, then applies the reached-the-bottom suppression.
  ///
  /// Suppression is display-only and is applied *after* the read, never
  /// written back: the articles are still unread, and the moment new content
  /// arrives for the scope the set is cleared and the true count returns.
  Future<void> _refreshCountsFromDb() async {
    final (folderCounts, allCount) = await (
      _articleRepo.getAllFolderUnreadCounts(windowDays: _displayAgeDays),
      _articleRepo.getTotalUnreadCount(windowDays: _displayAgeDays),
    ).wait;
    if (!mounted) return;
    final suppressed =
        UnreadCounts.fromRepository(total: allCount, byFolder: folderCounts)
            .withZeroedScopes(_zeroedScopes);
    setState(() => _counts = suppressed);
    AppBadgePlus.updateBadge(suppressed.all);
  }

  Future<void> _reloadArticles() async {
    await LoadingController.instance.run(() async {
      // Pick up anything changed in Settings while we were away.
      final settings = await _settingsRepo.getAll();
      if (mounted) {
        setState(() {
          _applyReadingSettings(settings);
          _newspaperMode = settings.newspaperMode;
        });
      }
      await _loadArticles();
      // Anchor, not `offset`: _loadArticles has just re-queried, so read rows
      // are gone and fetched rows may have been inserted above. The pixel
      // number that was correct a moment ago now points somewhere else.
      _restoreAnchor();
    }, label: 'Loading');
  }

  /// The one place articles enter this screen, so ordering is applied here and
  /// every path — boot, reload, tab switch, refresh — gets it for free.
  Future<List<Article>> _articlesForTab(int tab, List<Folder> folders) async {
    final articles = tab == 0
        ? await _articleRepo.getAllArticles(showRead: _showRead)
        : await _articleRepo.getArticlesByFolder(
            folders[tab - 1].id!,
            showRead: _showRead,
          );
    // Filters run on the newest-first result, so the cap keeps the newest N
    // per feed; ordering is applied last.
    return _applySortOrder(_applyDisplayFilters(articles));
  }

  /// Assigns `_articles` and keeps `_rows` and the card keys in step with it.
  /// A dozen sites change the list, and any one of them forgetting to regroup
  /// would show stale headers or throw off `_onScroll`'s height accounting.
  ///
  /// Since pass 12 there is no exception: retirement no longer mutates the
  /// list in place, it queues ids and lets the next rebuild drop them.
  ///
  /// Safe to call inside a `setState` closure; it only assigns fields.
  void _setArticles(List<Article> articles) {
    _articles = articles;
    _rows = groupByDay(articles, now: DateTime.now());
    _syncCardKeys(articles);
  }

  void _syncCardKeys(List<Article> articles) {
    final activeIds = {for (final a in articles) if (a.id != null) a.id!};
    _cardKeys.removeWhere((id, _) => !activeIds.contains(id));
    _measuredHeights.removeWhere((id, _) => !activeIds.contains(id));
    for (final a in articles) {
      if (a.id != null) _cardKeys.putIfAbsent(a.id!, GlobalKey.new);
    }
  }

  /// Puts the list back at the top. Every path that hits the network calls
  /// this.
  ///
  /// Preserving the offset across a refresh was actively harmful: with
  /// newest-first ordering, new articles are inserted *above* the viewport,
  /// so the same offset now points at different content and everything above
  /// it — including everything just fetched — reads as "already scrolled
  /// past". This replaces the scroll-restoration half of PRD §4.3 for
  /// refresh paths only; returning from the browser and switching tabs both
  /// still restore position.
  /// Records the article at the viewport top, so the position can be found
  /// again in a list that has changed underneath it.
  ///
  /// Stores the two articles below it as fallbacks: the anchor itself is the
  /// most likely row to disappear, because it is exactly the row the user was
  /// looking at when they opened something.
  void _captureAnchor() {
    if (!_scrollController.hasClients || _rows.isEmpty) return;
    final offset = _scrollController.offset;

    var cumulative = 0.0;
    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final h = _rowHeight(row);
      if (cumulative + h > offset && row is ArticleRow) {
        final id = row.article.id;
        if (id == null) return;
        final fallbacks = <int>[];
        for (var j = i + 1; j < _rows.length && fallbacks.length < 3; j++) {
          final r = _rows[j];
          if (r is ArticleRow && r.article.id != null) {
            fallbacks.add(r.article.id!);
          }
        }
        _tabAnchors[_currentScope] = ScrollAnchor(
          articleId: id,
          fallbackIds: fallbacks,
          pixelsIntoItem: offset - cumulative,
        );
        DiagLog.lifecycle(
            state: 'anchorCaptured', restoredOffset: offset, anchorId: id);
        return;
      }
      cumulative += h;
    }
  }

  /// One row's height, from the same three-tier source the read walk and the
  /// retirement planner use, so all three agree by construction.
  double _rowHeight(FeedRow row) {
    if (row is DayHeaderRow) return kDayHeaderHeight;
    final id = (row as ArticleRow).article.id;
    final ctx = id != null ? _cardKeys[id]?.currentContext : null;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        if (id != null) _measuredHeights[id] = box.size.height;
        return box.size.height;
      }
    }
    return (id != null ? _measuredHeights[id] : null) ?? 120.0;
  }

  /// Puts the anchored article back at the viewport top.
  ///
  /// Runs as a programmatic scroll, so [ReadGate] sees `userInitiated: false`
  /// and nothing this moves past can be marked read. That single relationship
  /// is what makes restoration incapable of corrupting read state.
  void _restoreAnchor() {
    final anchor = _tabAnchors[_currentScope];
    if (anchor == null) return _resetScrollToTop();

    _markReadGate.close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _rows.isEmpty) return;

      final ids = <int>[];
      for (final row in _rows) {
        if (row is ArticleRow && row.article.id != null) {
          ids.add(row.article.id!);
        }
      }
      final target = ScrollAnchorResolver.resolve(anchor, ids);
      if (ids.isEmpty) return;
      final targetId = ids[target.index.clamp(0, ids.length - 1)];

      // Sum the rows above the target. Every row above a position the user
      // was just looking at has been on screen, so its height is in
      // _measuredHeights — this is measurement, not estimation.
      var offset = 0.0;
      for (final row in _rows) {
        if (row is ArticleRow && row.article.id == targetId) break;
        offset += _rowHeight(row);
      }
      offset += target.pixelsIntoItem;

      final max = _scrollController.position.maxScrollExtent;
      DiagLog.lifecycle(
          state: target.exact ? 'anchorRestoreExact' : 'anchorRestoreFallback',
          restoredOffset: offset,
          anchorId: targetId);
      _asProgrammatic('programmatic:anchorRestore',
          () => _scrollController.jumpTo(offset.clamp(0.0, max)));
    });
  }

  void _resetScrollToTop() {
    _markReadGate.close();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _asProgrammatic(
          'programmatic:resetTop', () => _scrollController.jumpTo(0));
    });
  }

  // ── Network refresh ────────────────────────────────────────────────────────

  // Re-tap of Flash tab: fetch without cleanup.
  Future<void> _fetchAndReload() async {
    if (!mounted || _refreshing) return;
    setState(() => _refreshing = true);
    await LoadingController.instance.run(() async {
      try {
        await _fetchAndApply();
      } finally {
        if (mounted) setState(() => _refreshing = false);
      }
    }, label: 'Refreshing');
  }

  /// Fetch without cleanup, for both pull-to-refresh and the refresh button.
  ///
  /// The button used to additionally drop already-read rows from the list,
  /// because there was no way to say "never show me read articles". There is
  /// now — the Show read toggle — it is persistent, and it is one tap away,
  /// so the two gestures are the same operation again.
  Future<void> _refreshCurrentTab() async {
    if (_refreshing) return;
    HapticFeedback.lightImpact();
    setState(() => _refreshing = true);

    // Flush points 2 and 3 of 4. The refresh FAB and pull-to-refresh are
    // separate gestures but the same code path, so one flush serves both.
    await _flushRetirementQueue('refresh');

    await LoadingController.instance.run(() async {
      try {
        final beforeIds = _articles.map((a) => a.id).toSet();
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

        // Same conditional rule as _fetchAndApply: nothing arrived, nothing
        // moves. The user pulled to check, not to be relocated.
        if (!mounted) return;
        final probe = await _articlesForTab(_selectedTabIndex, _folders);
        final hasNew = probe.any((a) => !beforeIds.contains(a.id));
        if (!hasNew) {
          await _refreshCountsFromDb();
          return;
        }

        await _articleRepo.retireAllRead();
        await _loadArticles();
        _resetScrollToTop();
        _clearZeroedScopes();
      } catch (_) {
        _reportRefreshFailure();
      } finally {
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
    _captureAnchor();
    // Flush point 4 of 4. Before the articles for the new tab are queried, so
    // the rows retired here never reach the list being built.
    await _flushRetirementQueue('tabSwitch');

    final gen = ++_tabGeneration;
    setState(() {
      _selectedTabIndex = index;
      _loading = true;
    });
    final articles = await _articlesForTab(index, _folders);
    if (!mounted || gen != _tabGeneration) return;
    setState(() {
      _setArticles(articles);
      _loading = false;
    });

    // Programmatic like any other restore, so ReadGate blocks the mark-read
    // pass until the user actually scrolls in the tab they arrived at.
    _restoreAnchor();
  }

  // ── Mark as read on scroll ─────────────────────────────────────────────────

  /// Everything that must wait for the list to stop moving.
  ///
  /// Both jobs here need an idle position: retirement corrects the scroll
  /// offset, which `jumpTo` can only do without cancelling a gesture once the
  /// activity is already idle; and "reached the bottom" is only meaningful
  /// once the fling has settled.
  void _onScrollEnd() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent && position.atEdge) {
      if (_zeroedScopes.add(_currentScope)) {
        unawaited(_refreshCountsFromDb());
      }
    }

    _enqueueScrolledPast();
  }

  /// Queues rows that have scrolled past the retirement frontier.
  ///
  /// Phase one of two, and the half that must never move anything. It adds
  /// ids to [_retirementQueue] and stops: no deletion, no tombstone, no row
  /// leaves the list, and the scroll offset is not touched. Because it cannot
  /// move the list it needs no quiescence guard and is safe to run while a
  /// gesture is live.
  ///
  /// The deletion happens in [_flushRetirementQueue], at moments when the
  /// scroll position is being rebuilt anyway.
  void _enqueueScrolledPast() {
    if (!kEnableScrollRetirement) return;
    if (!_markReadOnScroll || _showRead) return;
    if (!_scrollController.hasClients) return;
    if (_booting || _refreshing || _backgroundFetching) return;
    // Same evidence-of-a-person rule as the mark-read pass: a programmatic
    // jump is not the user scrolling past anything.
    if (!_markReadGate.isOpen) return;

    final plan = planRetirement(
      rows: _rowMetrics(),
      scrollOffset: _scrollController.offset,
      bufferCards: kRetirementBufferCards,
    );
    if (plan.isEmpty) return;

    _retirementQueue.enqueue(plan.articleIds);
  }

  /// Phase two: delete everything the queue has collected.
  ///
  /// Called from exactly four places — mark all as read, the refresh FAB,
  /// pull-to-refresh and a category tab switch. Each is a moment where the
  /// scroll position is already being reset or the user is already at the top,
  /// so removing rows produces no visible movement and there is no offset
  /// arithmetic left to get wrong.
  ///
  /// Awaited before the caller rebuilds, so the list is built once from the
  /// post-flush state rather than built and then rebuilt.
  Future<void> _flushRetirementQueue(String trigger) async {
    if (_retirementQueue.isEmpty) return;
    final ids = _retirementQueue.drain();
    DiagLog.retire(ids: ids.length, trigger: trigger);
    try {
      await _articleRepo.retireArticles(ids);
      await _refreshCountsFromDb();
      ReadStateNotifier.instance.articleReadStateChanged();
    } catch (_) {
      // Self-healing: a failed write leaves the rows in place, and they are
      // re-queued the next time the user scrolls past them.
    }
  }

  /// Measures the current rows for the frontier calculation.
  ///
  /// Height comes from three places, in order: the live render box while the
  /// row is built, the remembered height from when it last was, and only then
  /// the constant. The constant is the one that caused this regression — real
  /// cards measure 96.8dp and 121.9dp on a Pixel 11 Pro against a hardcoded
  /// 120, so guessing was wrong in both directions and the error accumulated
  /// down the list.
  List<RowMetric> _rowMetrics() {
    return [
      for (final row in _rows)
        if (row is DayHeaderRow)
          // Fixed by construction and enforced by a SizedBox, so this one is
          // not a guess.
          const RowMetric(height: kDayHeaderHeight)
        else
          () {
            final article = (row as ArticleRow).article;
            final id = article.id;
            final key = id != null ? _cardKeys[id] : null;
            final context = key?.currentContext;

            double? measured;
            if (context != null) {
              final box = context.findRenderObject() as RenderBox?;
              if (box != null && box.hasSize) {
                measured = box.size.height;
                if (id != null) _measuredHeights[id] = measured;
              }
            }

            return RowMetric(
              height: measured ?? (id != null ? _measuredHeights[id] : null) ?? 120.0,
              articleId: id,
              isSaved: article.isSaved,
            );
          }(),
    ];
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final o = _scrollController.offset;
      DiagLog.scroll(
        offset: o,
        delta: o - _lastLoggedOffset,
        maxExtent: _scrollController.position.maxScrollExtent,
        source: _scrollSource,
      );
      _lastLoggedOffset = o;
    }
    // Before the early return below: the fade has to work whether or not
    // mark-read-on-scroll is switched on.
    _fabFade.onScroll();
    _updateBottomDwellTimer();
    if (!_markReadOnScroll || _articles.isEmpty) return;
    final offset = _scrollController.offset;
    double cumulative = 0.0;
    final toWrite = <int>[];
    final readFolderIds = <int?>[];
    // Set false the moment the walk has to guess a height. A guessed row puts
    // the viewport top at the wrong article, which marks the wrong set read.
    var extentsStable = true;
    for (final row in _rows) {
      // Headers contribute height but never decide the break — an article is
      // what marks read, and a header sitting just above the cutoff must not
      // stop the walk before it.
      if (row is DayHeaderRow) {
        cumulative += kDayHeaderHeight;
        continue;
      }
      final article = (row as ArticleRow).article;
      final id = article.id;
      final ctx = id != null ? _cardKeys[id]?.currentContext : null;
      double? measured;
      if (ctx != null) {
        final box = ctx.findRenderObject() as RenderBox?;
        if (box != null && box.hasSize) {
          measured = box.size.height;
          if (id != null) _measuredHeights[id] = measured;
        }
      }
      measured ??= id != null ? _measuredHeights[id] : null;
      if (measured == null) extentsStable = false;
      final h = measured ?? 120.0;
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

    // One gate in front of the write, evaluated once with everything the walk
    // learned. `pastMidpoint` is the walk's own result: it collected exactly
    // the articles whose midpoint cleared the viewport top, so an empty list
    // means nothing earned a read.
    //
    // This replaces the bare `_markReadGate.isOpen` check that used to sit
    // above the walk. The gate is still the source of `userInitiated`; what
    // is new is that a settling layout or a just-resumed app can no longer
    // ride in behind a legitimately open gate.
    final allowed = ReadGate.allows(ReadGateInput(
      userInitiated: _markReadGate.isOpen,
      extentsStable: extentsStable,
      sinceResume: DateTime.now().difference(_lastResumeAt),
      pastMidpoint: toWrite.isNotEmpty,
      resumeGrace: kResumeReadGrace,
    ));
    if (!allowed) {
      _pendingMarkReadUI.removeAll(toWrite);
      return;
    }

    // DB write is immediate.
    if (toWrite.isNotEmpty) {
      for (final id in toWrite) {
        DiagLog.read(id: id, trigger: 'scroll', offset: offset);
      }
      _articleRepo.markManyRead(toWrite);
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
      _setArticles([
        for (final a in _articles)
          ids.contains(a.id) ? a.copyWith(isRead: true) : a,
      ]);
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
    // Marks read only. Retirement is deliberately NOT triggered here: the
    // user is parked at the bottom with the whole feed above them, and
    // removing rows would collapse the list while they watch. The next
    // refresh retires them.
    DiagLog.read(
      id: -1,
      trigger: 'bottomDwell',
      offset: _scrollController.hasClients ? _scrollController.offset : -1,
    );
    if (_selectedTabIndex == 0) {
      await _articleRepo.markAllAsRead();
    } else {
      await _articleRepo.markAllAsReadByFolder(
        _folders[_selectedTabIndex - 1].id!,
      );
    }

    if (!mounted) return;
    setState(() {
      _setArticles([for (final a in _articles) a.copyWith(isRead: true)]);
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
      DiagLog.read(id: article.id!, trigger: 'tap', offset: scrollOffset);
      await _articleRepo.markAsRead(article.id!);

      if (mounted) {
        setState(() {
          _setArticles([
            for (final a in _articles)
              a.id == article.id ? a.copyWith(isRead: true) : a,
          ]);
          _counts = _counts.applyRead(_folderOf(article));
        });
        AppBadgePlus.updateBadge(_counts.all);
      }
    }

    if (!mounted) return;
    final uri = Uri.tryParse(article.url);
    if (uri == null) return;

    _captureAnchor();
    await launchUrl(uri, mode: LaunchMode.externalApplication);

    // Restore by anchor. The list is *not* unchanged: with Show read off the
    // article just opened has been filtered out of it, so every row below it
    // has shifted up by that card's height.
    if (mounted) _restoreAnchor();
  }

  Future<void> _markRead(Article article) async {
    if (article.id == null || article.isRead) return;
    DiagLog.read(
      id: article.id!,
      trigger: 'swipe',
      offset: _scrollController.hasClients ? _scrollController.offset : -1,
    );
    await _articleRepo.markAsRead(article.id!);

    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _setArticles([
        for (final a in _articles)
          a.id == article.id ? a.copyWith(isRead: true) : a,
      ]);
      _counts = _counts.applyRead(_folderOf(article));
    });
    AppBadgePlus.updateBadge(_counts.all);
  }

  Future<void> _markUnread(Article article) async {
    if (article.id == null || !article.isRead) return;
    // Unread means the user has not finished with it, so it must not be
    // retired at the next flush.
    _retirementQueue.release(article.id!);
    await _articleRepo.markAsUnread(article.id!);
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _setArticles([
        for (final a in _articles)
          a.id == article.id ? a.copyWith(isRead: false) : a,
      ]);
      _counts = _counts.applyUnread(_folderOf(article));
    });
    AppBadgePlus.updateBadge(_counts.all);
  }

  Future<void> _toggleSaved(Article article) async {
    if (article.id == null) return;
    final nowSaved = !article.isSaved;
    // PRD 4.9: a saved article is never deleted, whatever its read state or
    // age. Releasing here is belt and braces — retireArticles also scopes its
    // delete to is_saved = 0 — but it keeps the queue honest about what it
    // will actually retire.
    if (nowSaved) _retirementQueue.release(article.id!);
    await _articleRepo.setSaved(article.id!, saved: nowSaved);
    HapticFeedback.lightImpact();
    if (mounted) {
      setState(() {
        _setArticles([
          for (final a in _articles)
            a.id == article.id ? a.copyWith(isSaved: nowSaved) : a,
        ]);
      });
    }
    // After the local patch, so this screen's own listener sees a list that
    // already agrees and does nothing. Bookmarks is kept alive and loads only
    // in initState, so without this the bookmark doesn't appear there until a
    // pull-to-refresh.
    SavedStateNotifier.instance
        .articleSavedStateChanged(article.id!, saved: nowSaved);
  }

  // ── Mark all read ──────────────────────────────────────────────────────────

  /// Confirms before running: this cannot be undone, and [_markAllReadBody]
  /// follows the write with a cleanup pass that deletes read articles
  /// outright. Both entry points — the FAB and the folder tab bar — call
  /// this, so the guard covers both.
  Future<void> _markAllRead() async {
    final settings = await _settingsRepo.getAll();
    if (!mounted) return;

    if (settings.markAllReadConfirm) {
      final l10n = AppLocalizations.of(context)!;
      var dontAsk = false;
      final confirmed = await showDialog<bool>(
        context: context,
        // StatefulBuilder so ticking the checkbox rebuilds the dialog alone,
        // not the feed screen behind it.
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Text(l10n.markAllReadWarningTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.markAllReadWarningBody),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: dontAsk,
                  title: Text(l10n.dontShowAgain,
                      style: Theme.of(ctx).textTheme.bodyMedium),
                  onChanged: (v) => setDialogState(() => dontAsk = v ?? false),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                child: Text(l10n.markAllReadConfirm),
              ),
            ],
          ),
        ),
      );
      if (confirmed != true || !mounted) return;

      // Only on confirm. Ticking the box and then backing out must not
      // disable the warning.
      if (dontAsk) {
        await _settingsRepo.set('mark_all_read_confirm', 'false');
        SettingsNotifier.instance.settingsChanged();
      }
      if (!mounted) return;
    }

    HapticFeedback.mediumImpact();
    await LoadingController.instance.run(_markAllReadBody, label: 'Marking all read');
  }

  Future<void> _markAllReadBody() async {
    // Flush point 1 of 4. Before the rebuild below, so the list is built once.
    await _flushRetirementQueue('markAllRead');
    final settings = await _settingsRepo.getAll();
    final cleanupDays = settings.cleanupAgeDays;

    if (_selectedTabIndex == 0) {
      // All tab: mark all read, retire them outright, run cleanup, then a
      // cold-start fetch. This path rebuilds the list from scratch behind
      // _booting, so retiring here cannot move anything on screen.
      await _articleRepo.markAllAsRead();
      await _articleRepo.retireAllRead();
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

      if (mounted) setState(() => _counts = _counts.clearedFolder(folderId));

      await _articleRepo.markAllAsReadByFolder(folderId);
      await _articleRepo.retireAllRead(folderId: folderId);
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
        _articleRepo.getAllFolderUnreadCounts(windowDays: _displayAgeDays),
        _articleRepo.getTotalUnreadCount(windowDays: _displayAgeDays),
      ).wait;

      if (!mounted) return;
      final freshArticles = await _articlesForTab(_selectedTabIndex, _folders);
      if (!mounted) return;
      setState(() {
        _setArticles(freshArticles);
        _counts = UnreadCounts.fromRepository(total: allCount, byFolder: folderCounts);
      });
      _resetScrollToTop();
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
                          : () => _refreshCurrentTab(),
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
      child: NotificationListener<ScrollNotification>(
        // Two jobs, one listener.
        //
        // UserScrollNotification with a non-idle direction means a person
        // moved the list — touch, wheel or trackpad. `jumpTo` goes idle
        // first, so it can never open the gate.
        //
        // ScrollEndNotification is the *only* place retirement runs: the
        // position is idle there, so the offset correction cannot cancel a
        // gesture or destroy a ballistic simulation.
        //
        // Returns false either way so the notification keeps bubbling: the
        // RefreshIndicator above is an ancestor and depends on seeing it.
        onNotification: (notification) {
          if (!_programmaticScroll) {
            if (notification is ScrollStartNotification) {
              _scrollSource =
                  notification.dragDetails != null ? 'drag' : 'programmatic';
            } else if (notification is ScrollUpdateNotification) {
              _scrollSource =
                  notification.dragDetails != null ? 'drag' : 'fling';
            } else if (notification is ScrollEndNotification) {
              _scrollSource = 'idle';
            }
          }
          if (notification is UserScrollNotification &&
              notification.direction != ScrollDirection.idle) {
            _markReadGate.open();
          }
          if (notification is ScrollEndNotification) {
            _onScrollEnd();
          }
          return false;
        },
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            // Pure scroll-performance tuning again. It used to double as the
            // retirement distance, because retirement was confined to rows
            // this ListView had disposed — that coupling went with the
            // built-row ceiling in pass 12. kRetirementBufferCards alone now
            // decides how far above the viewport a row is queued.
            cacheExtent: 500,
            itemCount: _rows.length,
            itemBuilder: (context, i) {
              final row = _rows[i];
              if (row is DayHeaderRow) return DayHeader(row: row);

              final article = (row as ArticleRow).article;
              // The separator that ListView.separated used to draw, minus the
              // ones that would have landed either side of a header.
              final needsDivider = i > 0 && _rows[i - 1] is ArticleRow;
              return KeyedSubtree(
                // The key moves from the card to this wrapper so the height
                // _onScroll measures includes the divider above it. On a
                // fifty-card list, a per-card 1px error is a whole card's
                // worth of drift by the bottom.
                key: article.id != null ? _cardKeys[article.id!] : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (needsDivider)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                    ArticleCard(
                      article: article,
                      onTap: () => _openArticle(article),
                      onMarkRead: () => _markRead(article),
                      onMarkUnread: () => _markUnread(article),
                      onShare: () => _shareService.shareArticle(article),
                      onBookmark: () => _toggleSaved(article),
                    ),
                  ],
                ),
              );
            },
          ),
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
