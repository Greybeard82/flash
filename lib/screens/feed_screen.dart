import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../models/folder.dart';
import '../models/settings.dart';
import '../models/unread_counts.dart';
import '../repositories/alert_match_repository.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/article_opener.dart';
import '../services/feeds_changed_notifier.dart';
import '../services/loading_controller.dart';
import '../services/alerts_changed_notifier.dart';
import '../services/read_state_notifier.dart';
import '../services/refresh_service.dart';
import '../services/saved_state_notifier.dart';
import '../services/settings_notifier.dart';
import '../services/share_service.dart';
import '../services/unread_badge_service.dart';
import '../utils/day_grouping.dart';
import '../utils/mark_read_gate.dart';
import '../utils/constants.dart';
import '../utils/resume_refresh_policy.dart';
import '../reading/read_gate.dart';
import '../reading/scroll_anchor.dart';
import '../utils/diag_log.dart';
import '../widgets/article_card.dart';
import '../widgets/bubble_panel.dart';
import '../widgets/day_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_bubble.dart';
import '../widgets/keyword_alerts_panel.dart';
import '../widgets/mark_all_read_confirm.dart';
import '../widgets/keyword_blocklist_panel.dart';
import '../widgets/quick_settings_bubble.dart';
import '../widgets/scroll_fade.dart';
import '../widgets/folder_tab_bar.dart';
import '../widgets/notification_banner.dart';
import '../widgets/shimmer_card.dart';
import '../widgets/spinning_refresh_icon.dart';
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
  final _alertMatchRepo = AlertMatchRepository();
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

  /// True from just before our own `launchUrl` until the `resumed` that it
  /// causes has been handled.
  ///
  /// Opening an article in the external browser backgrounds Flutter, and the
  /// return fires `resumed` like any other. "Warm start" means the user came
  /// back after being away — not that their own tap-to-read bounced the app
  /// for a moment. Without this, the resume flush deleted the article the
  /// user had just tapped before they ever saw it dimmed (bug 2).
  ///
  /// Consumed by the resume handler. **Not** cleared after the `launchUrl`
  /// await: that future completes when the intent is dispatched, ~50ms after
  /// the tap and long before the user returns, so clearing there disarmed
  /// the flag before the resume it existed for (measured on device: cleared
  /// at t+51ms, resume at t+9.5s, article deleted). It is cleared when the
  /// launch fails — no backgrounding will follow — and treated as stale by
  /// the resume handler if no pause was ever observed.
  bool _returningFromArticleOpen = false;

  /// When the app last reached `resumed`, for [ReadGate]'s grace window.
  ///
  /// Starts at the epoch so a cold start is never inside the window — there
  /// is nothing to protect against before the first background/foreground
  /// cycle, and a fresh launch that blocked reads would be its own bug.
  DateTime _lastResumeAt = DateTime.fromMillisecondsSinceEpoch(0);

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


  /// One page per tab, in the tab strip's order. Only the selected page holds
  /// the live list (and the one shared _scrollController); every other page
  /// renders from [_tabArticlesCache] so a swipe shows real content at once.
  final PageController _pageController = PageController();

  /// True for the duration of a horizontal drag on the category PageView,
  /// including its post-release settle. The vertical list's own Scrollbar
  /// reads this to hide its thumb while the whole page — thumb included —
  /// is being carried sideways by the swipe, which otherwise reads as a
  /// stray bar drifting across the screen rather than a scrollbar.
  bool _isPageSwiping = false;

  /// Articles per tab index, warmed for every tab as soon as folders load and
  /// refreshed at every deletion boundary. Swiping used to show a shimmer on
  /// the incoming page until _onPageChanged had re-queried — for data that was
  /// already on disk. With a handful of folders the whole thing is cheap to
  /// keep hot. Keyed by tab index, so it is cleared whenever the folder list
  /// itself changes.
  final Map<int, List<Article>> _tabArticlesCache = {};

  /// Top padding shared by the live list and every cached page. Zero now
  /// that quick-settings/filter live in the app bar rather than overlaying
  /// the list — kept as a getter, not deleted outright, since both call
  /// sites read it and a future overlay would want the same single place to
  /// change.
  EdgeInsets get _listTopPadding => EdgeInsets.zero;
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

  /// READ -> DELETED, app-wide, at a lifecycle boundary. Returns how many
  /// rows went, so callers can rebuild the list when something actually
  /// changed rather than only when the fetch found new content — deleting
  /// rows and then leaving them on screen is exactly bug 1.
  ///
  /// Every deletion boundary goes through here so each one leaves a
  /// `[RETIRE]` line in the debug log with its trigger name.
  Future<int> _flushRead(String trigger, {int? folderId}) async {
    final deleted = await _articleRepo.retireAllRead(folderId: folderId);
    DiagLog.retire(ids: deleted, trigger: trigger);
    // Rows left every tab, not just the visible one; keep the pages honest.
    if (deleted > 0) unawaited(_warmTabCache(_folders));
    return deleted;
  }

  /// The scope the selected tab represents, for [_zeroedScopes] and
  /// [_tabAnchors].
  int get _currentScope {
    if (_selectedTabIndex == 0 || _selectedTabIndex > _folders.length) {
      return kAllScope;
    }
    return _folders[_selectedTabIndex - 1].id ?? kAllScope;
  }

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
      // AlertsScreen too. A backup restore comes through here and re-keys
      // alert_matches onto the ids the feeds came back under, so the entries
      // it holds are addressing feed ids that no longer exist.
      AlertsChangedNotifier.instance.alertsChanged();
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
    _pageController.dispose();
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
      return;
    }
    if (state == AppLifecycleState.resumed) {
      final resumedAt = DateTime.now();
      final wasPaused = _pausedAt != null;
      final shouldFetch = _resumePolicy.shouldFetch(
        pausedAt: _pausedAt,
        resumedAt: resumedAt,
        lastFetchAt: _lastFetchAt,
      );
      _pausedAt = null;
      // Our own launchUrl round-trip is not a warm start. The flag is honoured
      // only if we really went to background (a pause was seen); a flag with
      // no pause behind it is stale — the launch never left the app — and is
      // simply dropped so it cannot suppress the next genuine boundary.
      final ownLaunchReturn = _returningFromArticleOpen && wasPaused;
      _returningFromArticleOpen = false;
      if (_booting || _loading) return;
      if (shouldFetch) {
        _fetchOnResume(ownLaunchReturn: ownLaunchReturn);
      } else {
        _reloadArticles(ownLaunchReturn: ownLaunchReturn);
      }
    }
  }

  /// Resume from background with a fetch. Same indicator as cold start, so
  /// the two read as one behaviour.
  Future<void> _fetchOnResume({bool ownLaunchReturn = false}) =>
      _backgroundRefresh(ownLaunchReturn: ownLaunchReturn);

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

    // 1. Delete every read article, then age-based cleanup, so the list we
    //    are about to show is already purged rather than shedding rows a
    //    moment later. Unconditional: a cold start is a lifecycle boundary,
    //    and READ -> DELETED fires at every one of them whether or not the
    //    fetch that follows finds anything.
    try {
      await _flushRead('coldStart');
      await _articleRepo.runCleanup(days: settings.cleanupAgeDays);
    } catch (_) {
      // Housekeeping; a failure must not hold up the feed.
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
  Future<void> _backgroundRefresh({bool ownLaunchReturn = false}) async {
    if (!mounted || _backgroundFetching) return;
    setState(() => _backgroundFetching = true);
    await _fetchAndApply(ownLaunchReturn: ownLaunchReturn);
    if (mounted) setState(() => _backgroundFetching = false);
  }

  /// Fetches, deletes every read article, then decides whether anything
  /// actually arrived before touching the list.
  ///
  /// Deletion is unconditional. It used to sit behind the `hasNew` check
  /// below, which meant a cold start or a resume that found nothing new
  /// skipped it entirely — read rows accumulated across sessions and only
  /// went when a fetch happened to land. READ -> DELETED is a lifecycle rule,
  /// not a side effect of new content.
  ///
  /// The list rebuild is still conditional. "Visible" not "inserted": an
  /// article can be inserted and then hidden by the age filter, the per-feed
  /// cap or a blocklist match, and triggering on inserts would jump the user
  /// to the top to see nothing new. When nothing arrived the on-screen list
  /// is left alone — any dimmed rows it still shows are already gone from the
  /// database and drop out at the next rebuild.
  Future<void> _fetchAndApply({bool ownLaunchReturn = false}) async {
    final beforeIds = _articles.map((a) => a.id).toSet();

    try {
      await RefreshService(_settingsRepo).refreshAll();
      _lastFetchAt = DateTime.now();
    } catch (_) {
      _reportRefreshFailure();
    }

    if (!mounted) return;
    final deleted = ownLaunchReturn ? 0 : await _flushRead('resumeFetch');
    if (!mounted) return;
    // A fetch writes alert matches whatever screen is on top.
    AlertsChangedNotifier.instance.alertsChanged();
    if (!mounted) return;
    final folders = await _folderRepo.getAll();
    if (!mounted) return;
    final probe = await _articlesForTab(_selectedTabIndex, folders);
    final hasNew = probe.any((a) => !beforeIds.contains(a.id));

    // Two independent reasons to rebuild: something new arrived, or the
    // flush removed rows that are still on screen. Only when neither is true
    // does the list stay exactly where it is.
    //
    // Returning from our own browser launch never rebuilds, even if the fetch
    // found something: the user tapped one card and expects to find it where
    // it was, dimmed. With Show read off a re-query would hide it. What was
    // fetched is in the database and appears at the next real boundary.
    if (ownLaunchReturn || (!hasNew && deleted == 0)) {
      await _refreshCountsFromDb();
      return; // nothing moves
    }

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
    final articleTab = safeTab;

    final (articles, folderCounts, allCount) = await (
      _articlesForTab(articleTab, folders),
      _articleRepo.getAllFolderUnreadCounts(windowDays: _displayAgeDays),
      _articleRepo.getTotalUnreadCount(windowDays: _displayAgeDays),
    ).wait;

    if (!mounted) return;
    // Index-keyed, so a changed folder list invalidates every entry.
    _tabArticlesCache.clear();
    setState(() {
      _folders = folders;
      _hasFeeds = feeds.isNotEmpty;
      _selectedTabIndex = safeTab;
      _setArticles(articles);
      if (_pageController.hasClients &&
          _pageController.page?.round() != safeTab) {
        // jumpToPage fires onPageChanged, which early-returns because
        // _selectedTabIndex already equals safeTab.
        _pageController.jumpToPage(safeTab);
      }
      _feedFolderId = {for (final f in feeds) f.id!: f.folderId};
      _counts = UnreadCounts.fromRepository(total: allCount, byFolder: folderCounts);
      _loading = false;
    });
    UnreadBadgeService.instance.update(allCount);
    unawaited(_warmTabCache(folders));
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
    UnreadBadgeService.instance.update(suppressed.all);
  }

  Future<void> _reloadArticles({bool ownLaunchReturn = false}) async {
    if (ownLaunchReturn) {
      // The card was dimmed in place before we left. Re-querying would hide
      // it under Show read off, and deleting it is bug 2. Counts and the
      // anchor are all that need touching.
      await _refreshCountsFromDb();
      if (mounted) _restoreAnchor();
      return;
    }
    await LoadingController.instance.run(() async {
      // Pick up anything changed in Settings while we were away.
      final settings = await _settingsRepo.getAll();
      if (mounted) {
        setState(() {
          _applyReadingSettings(settings);
          _newspaperMode = settings.newspaperMode;
        });
      }
      // Warm start is a lifecycle boundary: READ -> DELETED, app-wide, before
      // the list is rebuilt from the post-delete state.
      await _flushRead('resume');
      await _loadArticles();
      // Anchor, not `offset`: _loadArticles has just re-queried, so read rows
      // are gone and fetched rows may have been inserted above. The pixel
      // number that was correct a moment ago now points somewhere else.
      _restoreAnchor();
    }, label: 'Loading');
  }

  /// The one place articles enter this screen, so ordering is applied here and
  /// every path — boot, reload, tab switch, refresh — gets it for free.
  ///
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
  /// There is no exception: deletion never mutates the list in place. Read
  /// rows are deleted from the database at lifecycle boundaries and the next
  /// rebuild simply does not find them.
  ///
  /// Safe to call inside a `setState` closure; it only assigns fields.
  void _setArticles(List<Article> articles) {
    _articles = articles;
    _rows = groupByDay(articles, now: DateTime.now());
    _syncCardKeys(articles);
    _tabArticlesCache[_selectedTabIndex] = articles;
  }

  /// Loads every tab's articles into [_tabArticlesCache]. Cheap for a
  /// personal reader's folder count, and it is what lets a swipe land on real
  /// content instead of a placeholder.
  ///
  Future<void> _warmTabCache(List<Folder> folders) async {
    for (var i = 0; i <= folders.length; i++) {
      if (!mounted) return;
      final articles = await _articlesForTab(i, folders);
      if (!mounted) return;
      // Never overwrite the live tab from a stale read.
      if (i == _selectedTabIndex) continue;
      _tabArticlesCache[i] = articles;
    }
    if (mounted) setState(() {});
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

    // The refresh FAB and pull-to-refresh are separate gestures but the same
    // code path, so one deletion serves both. App-wide and unconditional.
    final deleted = await _flushRead('refresh');

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

        AlertsChangedNotifier.instance.alertsChanged();

        // Same conditional rule as _fetchAndApply: nothing arrived, nothing
        // moves. The user pulled to check, not to be relocated.
        if (!mounted) return;
        final probe = await _articlesForTab(_selectedTabIndex, _folders);
        final hasNew = probe.any((a) => !beforeIds.contains(a.id));
        // The user pressed refresh expecting read articles to clear. Rebuild
        // if the flush removed anything, whether or not the fetch found new
        // content — those are unrelated conditions (bug 1).
        if (!hasNew && deleted == 0) {
          await _refreshCountsFromDb();
          return;
        }

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

  /// Chip tap. Moves the PageView; [_onPageChanged] does the actual switch,
  /// so a tap and a swipe run exactly the same code.
  void _onTabSelected(int index) {
    if (index == _selectedTabIndex) return;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _onPageChanged(index);
    }
  }

  /// Swipe landed on (or a tap animated to) a page. This is the tab-switch
  /// lifecycle boundary — including the app-wide read flush — for both input
  /// methods.
  Future<void> _onPageChanged(int index) async {
    if (index == _selectedTabIndex) return;
    await LoadingController.instance.run(() => _onTabSelectedBody(index), label: 'Loading');
  }

  Future<void> _onTabSelectedBody(int index) async {
    _captureAnchor();
    final gen = ++_tabGeneration;
    // The page the user just landed on was already showing this tab's cached
    // rows. Make them the live list now rather than dropping to a shimmer
    // while the flush and re-query below run — that shimmer was the flash.
    final cached = _tabArticlesCache[index];
    setState(() {
      _selectedTabIndex = index;
      if (cached != null) {
        _setArticles(cached);
      } else {
        _loading = true;
      }
    });

    // Before the fresh query, so deleted rows never reach the list being
    // built. App-wide, not folder-scoped: switching tabs is a lifecycle
    // boundary for the whole library, not just the destination.
    await _flushRead('tabSwitch');
    await _refreshCountsFromDb();
    ReadStateNotifier.instance.articleReadStateChanged();

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
      // Mirrored into the snapshots. Without this, scrolling past an alerted
      // article in a category tab marks it read everywhere except the Alerts
      // tab, which keeps showing it bold for good — the one list where the
      // difference between seen and unseen is the whole point.
      _alertMatchRepo.setReadForArticleIds(toWrite, isRead: true);
      _counts = _counts.applyManyRead(readFolderIds);
      UnreadBadgeService.instance.update(_counts.all);
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

  // ── Article actions ────────────────────────────────────────────────────────

  Future<void> _openArticle(Article article) async {
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    final wasUnread = article.id != null && !article.isRead;

    // Mark read immediately and dim in-place.
    if (wasUnread) {
      DiagLog.read(id: article.id!, trigger: 'tap', offset: scrollOffset);
      await _articleRepo.markAsRead(article.id!);
      // The two tables own their read flags separately — `alert_matches` has
      // to, because the articles row behind an entry is often already gone —
      // so the mirror is composed here rather than inside either repository.
      // A no-op for the overwhelming majority of articles, which matched no
      // keyword at all.
      await _alertMatchRepo.setRead(article.feedId, article.guid, isRead: true);

      if (mounted) {
        setState(() {
          _setArticles([
            for (final a in _articles)
              a.id == article.id ? a.copyWith(isRead: true) : a,
          ]);
          _counts = _counts.applyRead(_folderOf(article));
        });
        UnreadBadgeService.instance.update(_counts.all);
      }
    }

    if (!mounted) return;
    final uri = Uri.tryParse(article.url);
    if (uri == null) return;

    _captureAnchor();
    _returningFromArticleOpen = true;
    final mode = await openArticle(context, article);
    // Only an external launch backgrounds the app, so only that leaves a
    // resume coming to consume the flag. The built-in reader stays inside
    // the app — and a launch that did not happen never left it — so both of
    // those disarm here, and only here.
    if (mode != ArticleOpenMode.external) _returningFromArticleOpen = false;

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
    await _alertMatchRepo.setRead(article.feedId, article.guid, isRead: true);

    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _setArticles([
        for (final a in _articles)
          a.id == article.id ? a.copyWith(isRead: true) : a,
      ]);
      _counts = _counts.applyRead(_folderOf(article));
    });
    UnreadBadgeService.instance.update(_counts.all);
  }

  Future<void> _markUnread(Article article) async {
    if (article.id == null || !article.isRead) return;
    await _articleRepo.markAsUnread(article.id!);
    // Both directions, or an article deliberately put back to unread would
    // stay dimmed in the Alerts tab.
    await _alertMatchRepo.setRead(article.feedId, article.guid, isRead: false);
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _setArticles([
        for (final a in _articles)
          a.id == article.id ? a.copyWith(isRead: false) : a,
      ]);
      _counts = _counts.applyUnread(_folderOf(article));
    });
    UnreadBadgeService.instance.update(_counts.all);
  }

  Future<void> _toggleSaved(Article article) async {
    if (article.id == null) return;
    final nowSaved = !article.isSaved;
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
    if (!await confirmMarkAllRead(context)) return;
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    await LoadingController.instance
        .run(_markAllReadBody, label: 'Marking all read');
  }

  Future<void> _markAllReadBody() async {
    final settings = await _settingsRepo.getAll();
    final cleanupDays = settings.cleanupAgeDays;

    if (_selectedTabIndex == 0) {
      // All tab: mark all read, retire them outright, run cleanup, then a
      // cold-start fetch. This path rebuilds the list from scratch behind
      // _booting, so retiring here cannot move anything on screen.
      await _articleRepo.markAllAsRead();
      // The snapshots go with them. `alert_matches` owns its own flag, so
      // without this the Alerts tab would be the one place still claiming
      // there is something left to read.
      await _alertMatchRepo.setAllRead();
      await _flushRead('markAllRead:all');
      await _articleRepo.runCleanup(days: cleanupDays);

      if (!mounted) return;
      setState(() {
        _booting = true;
        _counts = _counts.clearedAll();
      });
      UnreadBadgeService.instance.update(0);
      try {
        await RefreshService(_settingsRepo).refreshAll(coldStart: false);
        _lastFetchAt = DateTime.now();
      } catch (_) {
        _reportRefreshFailure();
      }
      await _loadArticles();
      AlertsChangedNotifier.instance.alertsChanged();
      if (mounted) setState(() => _booting = false);
    } else {
      // Category tab: mark read, forget this tab's IDs, cleanup, refresh folder.
      final folderId = _folders[_selectedTabIndex - 1].id!;

      if (mounted) setState(() => _counts = _counts.clearedFolder(folderId));

      await _articleRepo.markAllAsReadByFolder(folderId);
      // Snapshots carry the folder they were taken from, so the same scoping
      // applies. A snapshot whose feed has since moved or been deleted holds
      // null there and is simply skipped rather than being swept up by a
      // folder it no longer belongs to.
      await _alertMatchRepo.setReadByFolder(folderId);
      await _flushRead('markAllRead:folder', folderId: folderId);
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
      UnreadBadgeService.instance.update(allCount);
      AlertsChangedNotifier.instance.alertsChanged();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      // The mark-all-read itself succeeded either way; say so, but don't
      // claim the feeds refreshed when they didn't.
      _bannerKey.currentState
          ?.show(refreshFailed ? l10n.refreshFailed : l10n.allMarkedRead);
    }
  }

  // ── Alert keyword management ───────────────────────────────────────────────

  /// The keyword panel, wrapped so AlertsScreen finds out what the user did
  /// in it — adding a keyword backfills matches, deleting one takes them away.
  /// See [_AlertPanelHost].
  Widget _alertKeywordsPanel() => AlertPanelHost(
      onClosed: () => AlertsChangedNotifier.instance.alertsChanged());


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
        (settings) => FilterBubble(
          initial: settings,
          onOpenBlocklist: () =>
              _reopenAsKeywordPanel(const KeywordBlocklistPanel()),
          onOpenAlerts: () => _reopenAsKeywordPanel(_alertKeywordsPanel()),
        ),
      );

  /// Hands the Filter bubble off to a keyword panel, growing from the same
  /// button. The row that triggers this already awaited its own dismiss
  /// (using its own, still-live context) before calling here — by the time
  /// this runs, FilterBubble's context may already be unmounted, so the
  /// reopen has to be this still-alive State's job, using its own context,
  /// not the row's.
  void _reopenAsKeywordPanel(Widget panel) {
    if (!mounted) return;
    _fabFade.settleNow();
    _openBubble = showBubblePanel(
      context: context,
      anchorKey: _filterFabKey,
      child: panel,
    );
  }

  void _openQuickSettingsBubble() => _openBubblePanel(
        _quickSettingsFabKey,
        (settings) => QuickSettingsBubble(initial: settings),
      );

  /// The two top buttons. Same mini-FAB styling and horizontal position as the
  /// bottom cluster, anchored to the top instead.
  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: _newspaperMode ? _NewspaperMasthead() : Text(l10n.appTitle),
        centerTitle: false,
        bottom: _hasFeeds && _folders.length > 1
            ? FolderTabBar(
                folders: _folders,
                selectedIndex: _selectedTabIndex,
                folderUnreadCounts: _counts.byFolder,
                allUnreadCount: _counts.all,
                onTabSelected: _onTabSelected,
                onMarkAllRead: _markAllRead,
              )
            : null,
        actions: [
          // Background fetch lives here rather than over the content.
          AnimatedOpacity(
            opacity: _backgroundFetching ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                  child: SpinningRefreshIcon(
                      size: 20,
                      color: Theme.of(context).colorScheme.primary)),
            ),
          ),
          // Quick settings and filter moved here from a floating cluster that
          // overlaid the top-right of the list. That overlay reserved its own
          // height out of the list's top padding, which is what produced the
          // empty band above the first article — an app-bar action reserves
          // nothing, because it isn't drawn over the content at all.
          if (_hasFeeds && !_booting) ...[
            IconButton(
              key: _quickSettingsFabKey,
              onPressed: _openQuickSettingsBubble,
              tooltip: l10n.quickSettingsTooltip,
              icon: const Icon(Icons.tune_rounded),
            ),
            IconButton(
              key: _filterFabKey,
              onPressed: _openFilterBubble,
              tooltip: l10n.filterTooltip,
              icon: const Icon(Icons.filter_alt_outlined),
            ),
          ],
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _hasFeeds && !_booting
          ? Padding(
              padding: EdgeInsets.zero,
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
                      // The same circular arrow either way — it just turns
                      // while the refresh is in flight. Swapping in the bolt
                      // replaced the control under the user's finger with a
                      // different glyph.
                      child: _refreshing
                          ? const SpinningRefreshIcon()
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
              // In the body rather than in AppBar.bottom, which would change
              // the bar's preferredSize on every tab switch and jolt the whole
              // layout down and back up again on every swipe.
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  // Notifications bubble up past this listener from the
                  // selected page's own vertical list too, so the axis check
                  // is load-bearing, not defensive: without it, an ordinary
                  // vertical scroll would be misread as a page swipe and hide
                  // the very thumb it belongs to.
                  onNotification: (notification) {
                    if (notification.metrics.axis != Axis.horizontal) {
                      return false;
                    }
                    if (notification is ScrollStartNotification &&
                        !_isPageSwiping) {
                      setState(() => _isPageSwiping = true);
                    } else if (notification is ScrollEndNotification &&
                        _isPageSwiping) {
                      setState(() => _isPageSwiping = false);
                    }
                    return false;
                  },
                  child: PageView.builder(
                    controller: _pageController,
                    // With a single tab there is nothing to page to.
                    physics: _hasFeeds && _folders.length > 1
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    itemCount: _hasFeeds ? 1 + _folders.length : 1,
                    itemBuilder: (_, i) {
                      if (i == _selectedTabIndex) return _buildContent();
                      final cached = _tabArticlesCache[i];
                      return cached == null
                          ? _pagePlaceholder()
                          : _cachedPage(cached);
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What a not-yet-selected page shows while it is being swiped into view.
  /// A skeleton rather than nothing, so the incoming page reads as content
  /// loading instead of a blank sheet.
  Widget _pagePlaceholder() {
    return ListView.builder(
      // Same top padding as the live list, or the rows jump the moment real
      // content replaces the placeholder.
      padding: _listTopPadding,
      itemCount: 6,
      itemBuilder: (_, __) => const ShimmerCard(),
    );
  }

  /// A tab's rows drawn from [_tabArticlesCache] — what a page shows while it
  /// is not the selected one. Read-mostly: no scroll controller, no card keys,
  /// none of the mark-read bookkeeping; taps still work so a page that has
  /// just been swiped to is not dead until _onPageChanged catches up.
  Widget _cachedPage(List<Article> articles) {
    final rows = groupByDay(articles, now: DateTime.now());
    return ListView.builder(
      padding: _listTopPadding,
      cacheExtent: 500,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is DayHeaderRow) return DayHeader(row: row);
        final article = (row as ArticleRow).article;
        final needsDivider = i > 0 && rows[i - 1] is ArticleRow;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (needsDivider)
              const Divider(height: 1, indent: 16, endIndent: 16),
            ArticleCard(
              article: article,
              enableSwipeActions: false,
              onTap: () => _openArticle(article),
              onMarkRead: () => _markRead(article),
              onMarkUnread: () => _markUnread(article),
              onShare: () => _shareService.shareArticle(article),
              onBookmark: () => _toggleSaved(article),
            ),
          ],
        );
      },
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
          // Suppressed for the duration of a category swipe: outside that,
          // behaviour is unchanged from the previous hardcoded true.
          thumbVisibility: !_isPageSwiping,
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            // The quick-settings/filter cluster floats over the top-right of
            // this list; reserve exactly its height so the first row starts
            // beneath it. Nothing more — the body already sits below the app
            // bar, so no inset belongs here.
            padding: _listTopPadding,
            // Pure scroll-performance tuning. Nothing about deletion depends
            // on which rows are built any more.
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
                      // Horizontal drags page between category tabs here.
                      enableSwipeActions: false,
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
