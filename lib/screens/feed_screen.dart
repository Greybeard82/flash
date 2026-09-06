import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_entry.dart';
import '../models/article.dart';
import '../models/folder.dart';
import '../models/settings.dart';
import '../models/unread_counts.dart';
import '../repositories/alert_match_repository.dart';
import '../repositories/article_repository.dart';
import '../repositories/feed_repository.dart';
import '../repositories/folder_repository.dart';
import '../repositories/keyword_alert_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/alert_navigation_intent.dart';
import '../services/feeds_changed_notifier.dart';
import '../services/loading_controller.dart';
import '../services/read_state_notifier.dart';
import '../services/refresh_service.dart';
import '../services/saved_state_notifier.dart';
import '../services/settings_notifier.dart';
import '../services/share_service.dart';
import '../utils/day_grouping.dart';
import '../utils/mark_read_gate.dart';
import '../utils/constants.dart';
import '../utils/resume_refresh_policy.dart';
import '../reading/read_gate.dart';
import '../reading/scroll_anchor.dart';
import '../utils/diag_log.dart';
import '../widgets/alert_keyword_strip.dart';
import '../widgets/article_card.dart';
import '../widgets/bubble_panel.dart';
import '../widgets/day_header.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_bubble.dart';
import '../widgets/keyword_alerts_panel.dart';
import '../widgets/keyword_blocklist_panel.dart';
import '../widgets/quick_settings_bubble.dart';
import '../widgets/scroll_fade.dart';
import '../widgets/fetching_indicator.dart';
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
  final _keywordAlertRepo = KeywordAlertRepository();
  final _feedRepo = FeedRepository();
  final _folderRepo = FolderRepository();
  final _settingsRepo = SettingsRepository();
  final _shareService = ShareService();

  // ── Scroll ─────────────────────────────────────────────────────────────────
  final ScrollController _scrollController = ScrollController();

  /// The Alerts list scrolls on its own controller, which is the mechanism —
  /// not merely a tidiness — behind mark-read-on-scroll being off there:
  /// [_onScroll] listens to [_scrollController] alone, so it never sees this
  /// list move. See [_buildAlertsContent].
  final ScrollController _alertsScrollController = ScrollController();
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

  // ── Alerts tab ─────────────────────────────────────────────────────────────

  /// Whether the Alerts pill is offered at all.
  ///
  /// Driven by whether any alert keyword is configured, not by whether
  /// anything has matched: a keyword that has caught nothing yet is exactly
  /// the case where the user wants somewhere to go and check. Recomputed
  /// whenever the keyword panel closes, since it can add or delete the last
  /// one while it is open.
  bool _alertsTabVisible = false;

  /// Alerts is always appended after the folders, so folder index i keeps
  /// meaning `_folders[i - 1]` and nothing downstream has to renumber.
  int get _alertsTabIndex => _folders.length + 1;

  /// Whether the Alerts tab is the selected one.
  ///
  /// `>` rather than `==` on purpose: a `_selectedTabIndex` left pointing past
  /// the end by a folder deletion must not fall through to
  /// `_folders[index - 1]` and throw.
  bool get _isAlertsTab =>
      _alertsTabVisible && _selectedTabIndex > _folders.length;

  /// The tab whose *article* list the ordinary machinery should work with.
  ///
  /// Alerts is not one of them — it has no entry in [_tabArticlesCache], no
  /// display filters and no anchor — so every path that re-queries or probes
  /// "the current tab" falls back to All rather than indexing [_folders] one
  /// past its end.
  int get _articleTabIndex => _isAlertsTab ? 0 : _selectedTabIndex;

  /// Cards on the Alerts tab: **total entries, read or unread**.
  ///
  /// Deliberately not part of [UnreadCounts] and deliberately absent from
  /// [AppBadgePlus.updateBadge], both of which mean "left to read". Alerts is
  /// a permanent record, so a count that drained to zero as the user worked
  /// through it would read as "your alerts were deleted".
  int _alertsCount = 0;

  /// The cards currently on the Alerts tab, already narrowed by
  /// [_alertKeywordFilter].
  List<AlertEntry> _alertEntries = const [];

  /// The keyword chip the user has selected, or null for All.
  ///
  /// Transient by design: it narrows one list rather than choosing a mode, so
  /// leaving the tab resets it.
  String? _alertKeywordFilter;

  /// Entry count per keyword for the filter strip. Includes configured
  /// keywords that have matched nothing — see
  /// [AlertMatchRepository.countsByKeyword].
  Map<String, int> _alertKeywordCounts = const {};

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
  ///
  /// Alerts gets [kAlertsScope] rather than being folded into [kAllScope]: it
  /// keeps no anchor and can never be zeroed — nothing on that tab is an
  /// unread count — and sharing All's scope id would let it overwrite All's
  /// remembered position. The index bound is checked before [_folders] is
  /// touched, since the Alerts index sits one past the last folder.
  int get _currentScope {
    if (_isAlertsTab) return kAlertsScope;
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
    // The Alerts tab answers to neither slider — an alert is permanent, so the
    // age cutoff and the per-feed cap are not its business — but the list
    // sitting behind it still is, so the re-query runs against All rather than
    // being skipped.
    final refreshed = await _articlesForTab(_articleTabIndex, _folders);
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
    // A tapped keyword-alert notification asks for the Alerts pill. The
    // request latches, so this covers both the cold start — where it was set
    // in main() long before this screen existed, and is consumed by _boot —
    // and a tap while the app is already running.
    AlertNavigationIntent.instance.addListener(_onAlertNavigationRequested);
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
      // The Alerts tab too. A backup restore comes through here, and it
      // re-keys alert_matches onto the ids the feeds came back under — so the
      // _alertEntries held in memory are addressing feed ids that no longer
      // exist, and every bin, bookmark and read on those cards would quietly
      // match nothing. Deleting a feed lands here as well, and its snapshots
      // survive by design and have to keep rendering.
      await _refreshAlertsState();
      _resetScrollToTop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ReadStateNotifier.instance.removeListener(_onExternalReadStateChanged);
    SettingsNotifier.instance.removeListener(_onSettingsChanged);
    SavedStateNotifier.instance.removeListener(_onExternalSavedStateChanged);
    AlertNavigationIntent.instance.removeListener(_onAlertNavigationRequested);
    _scrollDebounce?.cancel();
    _pageController.dispose();
    _fabFade.dispose();
    if (_openBubble?.mounted ?? false) _openBubble!.remove();
    _scrollController.dispose();
    _alertsScrollController.dispose();
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
    // The Alerts list has no read bookkeeping to drive, but the floating
    // buttons still have to get out of the way while it moves.
    _alertsScrollController.addListener(_fabFade.onScroll);

    // 3. Whether the Alerts pill exists at all, and what it says. Also where a
    //    tapped notification's latched request is finally acted on — it needs
    //    to know the tab exists before it can select it.
    await _refreshAlertsState();

    // 4. Fetch in the background.
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
    // Unconditional, and before the "did anything move" question below: a
    // fetch writes alert matches whatever tab is on screen, and the pill's
    // count is the only place the user sees that from another tab.
    await _refreshAlertsState();
    if (!mounted) return;
    final folders = await _folderRepo.getAll();
    if (!mounted) return;
    final probe = await _articlesForTab(_articleTabIndex, folders);
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

    // The clamp used to end at folders.length, which is one short of the
    // Alerts index: every reload would have quietly dragged the user off the
    // Alerts tab and back to All. The extra slot exists only while the pill
    // does, so a keyword deleted elsewhere still clamps them back.
    final safeTab =
        _selectedTabIndex.clamp(0, folders.length + (_alertsTabVisible ? 1 : 0));
    // Alerts is fed by alert_matches, not by this query; it is the All list
    // that keeps loading behind it.
    final articleTab = safeTab > folders.length ? 0 : safeTab;

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
    AppBadgePlus.updateBadge(allCount);
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
    AppBadgePlus.updateBadge(suppressed.all);
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
  /// Never called with the Alerts index. `tab - 1` would run off the end of
  /// [folders], and the answer would be wrong even if it didn't: the Alerts
  /// tab is built from `alert_matches` and deliberately skips both display
  /// filters. Callers go through [_articleTabIndex] rather than
  /// `_selectedTabIndex` for exactly this reason.
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
    // Filed under [_articleTabIndex], not the selected index: while Alerts is
    // selected the list being assigned is All's, and caching it under the
    // Alerts index would hand that page a set of ordinary articles the moment
    // it was swiped past.
    _tabArticlesCache[_articleTabIndex] = articles;
  }

  /// Loads every tab's articles into [_tabArticlesCache]. Cheap for a
  /// personal reader's folder count, and it is what lets a swipe land on real
  /// content instead of a placeholder.
  ///
  /// The bound stops at the last folder, so the Alerts index is never warmed:
  /// it has no article list to warm, and [_buildAlertsContent] draws it from
  /// [_alertEntries] whether or not it is the selected page.
  Future<void> _warmTabCache(List<Folder> folders) async {
    for (var i = 0; i <= folders.length; i++) {
      if (!mounted) return;
      final articles = await _articlesForTab(i, folders);
      if (!mounted) return;
      // Never overwrite the live tab from a stale read — which, on the Alerts
      // tab, is the All list rather than the selected index.
      if (i == _articleTabIndex) continue;
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

    if (_isAlertsTab) {
      // No flush and no cleanup. Both are article-lifecycle work, and the
      // Alerts list is a permanent record that a fetch can only ever add to —
      // running a deletion pass here would be the old behaviour creeping back
      // in through the one gesture that looks harmless.
      await _refreshAlertsFetch();
      if (mounted) setState(() => _refreshing = false);
      return;
    }

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

        // A fetch can have written alert matches; the pill has to say so.
        await _refreshAlertsState();

        // Same conditional rule as _fetchAndApply: nothing arrived, nothing
        // moves. The user pulled to check, not to be relocated.
        if (!mounted) return;
        final probe = await _articlesForTab(_articleTabIndex, _folders);
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
    final leavingAlerts = _isAlertsTab;
    final enteringAlerts = _alertsTabVisible && index == _alertsTabIndex;
    // The page the user just landed on was already showing this tab's cached
    // rows. Make them the live list now rather than dropping to a shimmer
    // while the flush and re-query below run — that shimmer was the flash.
    final cached = _tabArticlesCache[index];
    setState(() {
      _selectedTabIndex = index;
      // The keyword chips narrow one list; they are not a mode. Coming back to
      // Alerts with the last selection still applied would look like matches
      // had gone missing.
      if (leavingAlerts) _alertKeywordFilter = null;
      if (enteringAlerts) {
        // Nothing to do to _articles: the list behind Alerts stays exactly as
        // it was, and _buildAlertsContent never reads it.
      } else if (cached != null) {
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

    if (enteringAlerts) {
      // Rebuilt from alert_matches on every arrival rather than cached, which
      // is also what picks up whatever a background fetch matched while
      // another tab was on screen. No anchor restore: Alerts keeps none.
      await _refreshAlertsState();
      return;
    }

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
        AppBadgePlus.updateBadge(_counts.all);
      }
    }

    if (!mounted) return;
    final uri = Uri.tryParse(article.url);
    if (uri == null) return;

    _captureAnchor();
    _returningFromArticleOpen = true;
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    // A launch that did not happen will not background the app, so there is
    // no resume coming to consume the flag. Disarm it here, and only here —
    // a successful launch leaves it armed for the resume the browser return
    // will cause.
    if (!launched) _returningFromArticleOpen = false;

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
    AppBadgePlus.updateBadge(_counts.all);
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
    AppBadgePlus.updateBadge(_counts.all);
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
    final settings = await _settingsRepo.getAll();
    final cleanupDays = settings.cleanupAgeDays;

    if (_isAlertsTab) {
      // Marks the record read and nothing else: no retire, no cleanup, no
      // fetch. Every one of those is a deletion or a refetch of *articles*,
      // and the Alerts tab is the one list in the app that no deletion path is
      // allowed to touch — running them here would put back, through the FAB,
      // exactly the loss `alert_matches` exists to prevent.
      await _alertMatchRepo.setAllRead();
      // Mirrored onto whichever articles rows are still there, so an entry the
      // user just cleared here is not still bold in the ordinary feed. Read
      // unfiltered rather than from _alertEntries: setAllRead covered every
      // row, including the ones the keyword chips are currently hiding.
      for (final entry in await _alertMatchRepo.getEntries()) {
        final row = await _articleRepo.findByGuid(entry.feedId, entry.guid);
        if (row?.id != null && !row!.isRead) {
          await _articleRepo.markAsRead(row.id!);
        }
      }

      await _refreshAlertsState();
      await _refreshCountsFromDb();
      ReadStateNotifier.instance.articleReadStateChanged();
      if (!mounted) return;
      _bannerKey.currentState
          ?.show(AppLocalizations.of(context)!.alertsMarkAllReadBanner);
      return;
    }

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
      AppBadgePlus.updateBadge(0);
      try {
        await RefreshService(_settingsRepo).refreshAll(coldStart: false);
        _lastFetchAt = DateTime.now();
      } catch (_) {
        _reportRefreshFailure();
      }
      await _loadArticles();
      await _refreshAlertsState();
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
      AppBadgePlus.updateBadge(allCount);
      await _refreshAlertsState();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      // The mark-all-read itself succeeded either way; say so, but don't
      // claim the feeds refreshed when they didn't.
      _bannerKey.currentState
          ?.show(refreshFailed ? l10n.refreshFailed : l10n.allMarkedRead);
    }
  }

  // ── Alerts tab ─────────────────────────────────────────────────────────────

  /// Re-reads everything the Alerts tab and its pill are drawn from.
  ///
  /// One call rather than four, because the four answers have to agree: the
  /// pill's total, the strip's per-keyword counts, the visible cards and
  /// whether the tab exists at all are the same query result seen from
  /// different angles, and refreshing them separately is how a strip ends up
  /// promising "zelda (3)" above an empty list.
  ///
  /// Visibility follows the *configured keywords*, not the matches. A keyword
  /// that has caught nothing yet is exactly when the user wants somewhere to
  /// go and check, and hiding the tab until the first match would make a
  /// freshly added alert look like it had not saved.
  Future<void> _refreshAlertsState() async {
    final (keywords, counts, total) = await (
      _keywordAlertRepo.getAll(),
      _alertMatchRepo.countsByKeyword(),
      _alertMatchRepo.totalEntryCount(),
    ).wait;

    // A filter the strip no longer offers cannot stay selected. Deleting or
    // renaming the keyword whose chip is active leaves _alertKeywordFilter
    // pointing at a name with no rows and no chip, and the query below would
    // then draw the empty state over a tab that is not empty — with no chip
    // lit up to explain why. countsByKeyword() enumerates the keyword table,
    // so a keyword missing from it is a keyword that no longer exists.
    final filter =
        (_alertKeywordFilter != null && !counts.containsKey(_alertKeywordFilter))
            ? null
            : _alertKeywordFilter;
    final entries = await _alertMatchRepo.getEntries(keyword: filter);
    if (!mounted) return;

    final visible = keywords.isNotEmpty;
    // The panel can delete the last keyword while the user is standing on the
    // tab it belongs to. The pill goes, the PageView loses a page, and a
    // _selectedTabIndex one past the last folder would then address nothing.
    final fellBack = !visible && _selectedTabIndex > _folders.length;

    setState(() {
      _alertsTabVisible = visible;
      _alertKeywordCounts = counts;
      _alertsCount = total;
      _alertEntries = entries;
      _alertKeywordFilter = filter;
      if (fellBack) {
        _selectedTabIndex = 0;
        _alertKeywordFilter = null;
      }
    });

    if (fellBack) {
      // jumpToPage fires onPageChanged, which early-returns because
      // _selectedTabIndex already agrees; the reload is what actually puts All
      // back on screen.
      if (_pageController.hasClients) _pageController.jumpToPage(0);
      await _loadArticles();
      return;
    }

    await _consumeAlertNavigation();
  }

  /// Reloads only the cards, for the paths that already know the counts are
  /// current — a keyword chip changing which subset is shown.
  Future<void> _reloadAlertEntries() async {
    final entries = await _alertMatchRepo.getEntries(keyword: _alertKeywordFilter);
    if (!mounted) return;
    setState(() => _alertEntries = entries);
  }

  /// Pull-to-refresh and the refresh FAB on the Alerts tab.
  ///
  /// A plain fetch and a reload. Deliberately none of [_refreshCurrentTab]'s
  /// article bookkeeping: no read flush, no probe for "did anything new
  /// arrive", no scroll reset. New matches are appended by the fetch itself
  /// and the list is ordered newest-matched-first, so they arrive at the top
  /// without the position having to be thrown away.
  Future<void> _refreshAlertsFetch() async {
    try {
      await RefreshService(_settingsRepo).refreshAll();
      _lastFetchAt = DateTime.now();
    } catch (_) {
      _reportRefreshFailure();
    }
    if (!mounted) return;
    await _refreshAlertsState();
    await _refreshCountsFromDb();
  }

  /// The pull gesture, which owns the `_refreshing` flag the FAB also uses so
  /// the two cannot run a fetch at once.
  Future<void> _onAlertsPullToRefresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _refreshAlertsFetch();
    if (mounted) setState(() => _refreshing = false);
  }

  void _onAlertKeywordSelected(String? keyword) {
    setState(() => _alertKeywordFilter = keyword);
    unawaited(_reloadAlertEntries());
  }

  /// A tapped keyword-alert notification.
  ///
  /// The request is only consumed once there is a tab to honour it with. A
  /// user who tapped a notification and then deleted every keyword before the
  /// app came up has nowhere to be sent, and clearing the flag on the way past
  /// would silently swallow the request instead of leaving it latched for the
  /// moment a keyword exists again.
  void _onAlertNavigationRequested() {
    if (!mounted) return;
    unawaited(_consumeAlertNavigation());
  }

  Future<void> _consumeAlertNavigation() async {
    if (!mounted || !_alertsTabVisible) return;
    if (!AlertNavigationIntent.instance.consumePending()) return;
    if (_selectedTabIndex == _alertsTabIndex) return;
    _onTabSelected(_alertsTabIndex);
  }

  /// Opens an entry, then launches exactly as [_openArticle] does.
  ///
  /// The read is written to both tables, in that order and independently: the
  /// snapshot always, the articles row only if it is still there. It usually
  /// is not — retirement, cleanup and the tombstone all take it, which is the
  /// whole reason `alert_matches.is_read` is a column rather than something
  /// read through a join.
  ///
  /// The entry stays in the list. It dims, and that is all: the tab is a
  /// permanent record of what the keywords caught, so an entry that vanished
  /// on being read would empty the tab out as the user worked through it.
  Future<void> _openAlertEntry(Article snapshot) async {
    await _alertMatchRepo.setRead(snapshot.feedId, snapshot.guid, isRead: true);
    final row = await _articleRepo.findByGuid(snapshot.feedId, snapshot.guid);
    if (row?.id != null && !row!.isRead) {
      await _articleRepo.markAsRead(row.id!);
      ReadStateNotifier.instance.articleReadStateChanged();
    }
    if (!mounted) return;
    await _reloadAlertEntries();
    unawaited(_refreshCountsFromDb());

    if (!mounted) return;
    final uri = Uri.tryParse(snapshot.url);
    if (uri == null) return;

    // No anchor capture: the Alerts list keeps none, because ScrollAnchor is
    // keyed on article.id and an entry has none.
    _returningFromArticleOpen = true;
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched) _returningFromArticleOpen = false;
  }

  /// The radial menu's read/unread arms on the Alerts tab.
  ///
  /// Both sides again, and the articles row only when it survives.
  Future<void> _setAlertEntryRead(Article snapshot,
      {required bool isRead}) async {
    await _alertMatchRepo.setRead(snapshot.feedId, snapshot.guid,
        isRead: isRead);
    final row = await _articleRepo.findByGuid(snapshot.feedId, snapshot.guid);
    if (row?.id != null && row!.isRead != isRead) {
      if (isRead) {
        await _articleRepo.markAsRead(row.id!);
      } else {
        await _articleRepo.markAsUnread(row.id!);
      }
      ReadStateNotifier.instance.articleReadStateChanged();
    }
    HapticFeedback.lightImpact();
    if (!mounted) return;
    await _reloadAlertEntries();
    unawaited(_refreshCountsFromDb());
  }

  /// Bookmarking from the Alerts tab.
  ///
  /// The button is shown on every card and says so afterwards when there is
  /// nothing to bookmark, rather than being hidden when the articles row has
  /// gone. Hiding it would reflow the radial menu from four buttons to three
  /// on exactly the cards whose article has been cleaned up — moving Share and
  /// Summary under the user's thumb for reasons they cannot see. This is the
  /// accepted simple behaviour, not an oversight.
  ///
  /// The icon the menu draws comes from the snapshot, which carries no saved
  /// flag, so it always reads as un-bookmarked here. Mirroring `is_saved` into
  /// `alert_matches` would be a second copy of state to keep honest for the
  /// sake of one icon, and the bolted-on `is_saved` is precisely what this
  /// rework removed.
  Future<void> _toggleSavedFromAlerts(Article snapshot) async {
    final row = await _articleRepo.findByGuid(snapshot.feedId, snapshot.guid);
    if (!mounted) return;
    if (row?.id == null) {
      _bannerKey.currentState
          ?.show(AppLocalizations.of(context)!.alertsArticleGone);
      return;
    }
    await _toggleSaved(row!);
  }

  /// Dismisses one card, from the radial menu's bin.
  ///
  /// No confirmation and no undo, matching mark-all-read's existing stance.
  /// Every keyword row behind the card goes with it — a leftover row would
  /// rebuild the same card at the next read. The haptic and the menu's own
  /// dismissal happen in [RadialMenu] before this is called, which is why
  /// there is neither here.
  Future<void> _deleteAlertEntry(Article snapshot) async {
    await _alertMatchRepo.deleteEntry(snapshot.feedId, snapshot.guid);
    if (!mounted) return;

    // Removed from the list first, so the card goes the moment the menu
    // closes rather than after the counts have come back from the database.
    setState(() {
      _alertEntries = [
        for (final e in _alertEntries)
          if (e.feedId != snapshot.feedId || e.guid != snapshot.guid) e,
      ];
    });

    final (counts, total) = await (
      _alertMatchRepo.countsByKeyword(),
      _alertMatchRepo.totalEntryCount(),
    ).wait;
    if (!mounted) return;
    setState(() {
      _alertKeywordCounts = counts;
      _alertsCount = total;
    });
    _bannerKey.currentState
        ?.show(AppLocalizations.of(context)!.alertsRemovedBanner);
  }

  /// The keyword panel, wrapped so the pill and the strip find out what the
  /// user did in it. See [_AlertPanelHost].
  Widget _alertKeywordsPanel() =>
      _AlertPanelHost(onClosed: () => unawaited(_refreshAlertsState()));

  /// The strip's "Manage keywords" chip. Grows out of the Filter button, the
  /// same anchor the Filter bubble's own route into the panel uses, so the
  /// panel appears in one place however it was reached.
  void _openAlertKeywordsPanel() {
    if (_openBubble?.mounted ?? false) return;
    _reopenAsKeywordPanel(_alertKeywordsPanel());
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
        // The pill row used to be hidden below two folders, which for a
        // one-folder library would have made the Alerts tab exist and be
        // unreachable. It now also appears for the Alerts pill alone.
        bottom: (_hasFeeds || _alertsTabVisible) &&
                (_folders.length > 1 || _alertsTabVisible)
            ? FolderTabBar(
                folders: _folders,
                selectedIndex: _selectedTabIndex,
                folderUnreadCounts: _counts.byFolder,
                allUnreadCount: _counts.all,
                onTabSelected: _onTabSelected,
                onMarkAllRead: _markAllRead,
                alertsVisible: _alertsTabVisible,
                alertsCount: _alertsCount,
              )
            : null,
        actions: [
          // Background fetch lives here rather than over the content.
          AnimatedOpacity(
            opacity: _backgroundFetching ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: FetchingIndicator()),
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
              // layout down and back up again as the user swiped past Alerts.
              if (_isAlertsTab)
                AlertKeywordStrip(
                  countsByKeyword: _alertKeywordCounts,
                  totalEntryCount: _alertsCount,
                  selectedKeyword: _alertKeywordFilter,
                  onSelected: _onAlertKeywordSelected,
                  onManageKeywords: _openAlertKeywordsPanel,
                ),
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
                    // With a single tab there is nothing to page to — but the
                    // Alerts pill is a second tab in its own right, so it has
                    // to widen this the same way it widens the pill row.
                    // Gated on `_hasFeeds || _alertsTabVisible`, not on
                    // _hasFeeds alone. An alert snapshot deliberately outlives
                    // the feed it arrived on — that is the entire point of
                    // alert_matches — so a user who deletes their last feed
                    // still has an alert history, and gating on feeds alone
                    // left it in the database with no route to it: no pill, a
                    // one-page PageView, and swiping switched off.
                    physics: (_hasFeeds || _alertsTabVisible) &&
                            (_folders.length > 1 || _alertsTabVisible)
                        ? const PageScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    onPageChanged: _onPageChanged,
                    itemCount: _hasFeeds || _alertsTabVisible
                        ? 1 + _folders.length + (_alertsTabVisible ? 1 : 0)
                        : 1,
                    itemBuilder: (_, i) {
                      // Checked before the selected-page branch: Alerts draws
                      // itself from _alertEntries whether or not it is the
                      // selected page, so it is never a cached article list
                      // and never goes through _buildContent.
                      if (_alertsTabVisible && i == _alertsTabIndex) {
                        return _buildAlertsContent();
                      }
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

  /// The Alerts list as day-headered rows.
  ///
  /// [groupByDay] keys on `published_at`, and an alert has to be filed under
  /// the day it *matched*: adding a keyword backfills it against everything
  /// already on the device, so a brand-new alert routinely lands on a
  /// month-old article and grouping it by its publication date would bury the
  /// newest thing on the tab under an "older" header. The proxies exist only
  /// to choose the headers; the rows themselves carry the real article, so the
  /// card still shows the publication date it always did.
  List<FeedRow> _alertRows(List<AlertEntry> entries) {
    final articles = [for (final e in entries) e.toArticle()];
    final proxies = [
      for (var i = 0; i < entries.length; i++)
        articles[i].copyWith(publishedAt: entries[i].matchedAt),
    ];
    final rows = groupByDay(proxies, now: DateTime.now());
    var next = 0;
    return [
      for (final row in rows)
        if (row is ArticleRow) ArticleRow(articles[next++]) else row,
    ];
  }

  /// Every entry's full keyword set, by (feedId, guid).
  ///
  /// The rows carry [Article]s, which have no idea what matched them, and the
  /// pair is the only identity a snapshot still shares with one. Joined on
  /// NUL for the same reason the repository does it: no guid can contain one,
  /// so two pairs cannot flatten onto the same string.
  Map<String, List<String>> _alertKeywordsByPair() => {
        for (final e in _alertEntries) '${e.feedId}\u0000${e.guid}': e.keywords,
      };

  /// The Alerts tab.
  ///
  /// A separate build path, and every one of the things it does not use is
  /// load-bearing rather than an omission:
  ///
  /// [_applyDisplayFilters] imposes the Article age cutoff and the per-feed
  /// cap. An alert is permanent — the entire point of `alert_matches` is that
  /// it survives every rule that removes an article — so a display filter here
  /// would reintroduce the disappearing-alert bug at the very last step, in
  /// the one place nothing else guards against it.
  ///
  /// [_flushRead], [_onScrollEnd] and the retirement bookkeeping are
  /// article-lifecycle machinery, and an entry has no lifecycle: it arrives
  /// when a keyword matches and leaves only when the user dismisses it.
  ///
  /// [_cardKeys], [_measuredHeights] and [ScrollAnchor] all key on
  /// `article.id`, which is null for an [AlertEntry] by design — a snapshot
  /// has no `articles` identity, and inventing one would point every id-keyed
  /// operation at whatever article happens to hold that rowid now.
  ///
  /// Mark-read-on-scroll is off for a reason of its own. Alerts is a review
  /// surface the user returns to deliberately, and auto-dimming everything on
  /// the first scroll-through would destroy the only signal separating "seen"
  /// from "not yet seen". The tab's own [_alertsScrollController] is what
  /// enforces it: [_onScroll] listens to [_scrollController] alone.
  Widget _buildAlertsContent() {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    if (_alertEntries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onAlertsPullToRefresh,
        backgroundColor: scheme.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.35),
            Text(
              l10n.alertsTabEmpty,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
            ),
          ],
        ),
      );
    }

    final rows = _alertRows(_alertEntries);
    final keywordsByPair = _alertKeywordsByPair();

    return RefreshIndicator(
      onRefresh: _onAlertsPullToRefresh,
      backgroundColor: scheme.surface,
      child: ListView.builder(
        controller: _alertsScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
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
                // Mandatory, not a style choice: the Dismissible keys on
                // ValueKey('article_${article.id}') and an entry's id is null,
                // so a swipe-enabled card here is a crash rather than a
                // gesture. Horizontal drags page between tabs anyway.
                enableSwipeActions: false,
                alertKeywords:
                    keywordsByPair['${article.feedId}\u0000${article.guid}'] ??
                        const [],
                onTap: () => _openAlertEntry(article),
                onMarkRead: () => _setAlertEntryRead(article, isRead: true),
                onMarkUnread: () => _setAlertEntryRead(article, isRead: false),
                onShare: () => _shareService.shareArticle(article),
                onBookmark: () => _toggleSavedFromAlerts(article),
                // The bin is offered here and nowhere else. An alert match
                // outlives every path that deletes an article, so dismissing
                // it by hand is the only way one ever leaves the list.
                onDelete: () => _deleteAlertEntry(article),
              ),
            ],
          );
        },
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

/// Hosts [KeywordAlertsPanel] so the Alerts pill can find out what the user
/// did in it.
///
/// The panel adds, edits and deletes keywords, and the first or last of those
/// makes the pill appear or disappear — but the panel is a const widget with
/// nothing to report through, and it is shown in an overlay rather than pushed
/// as a route, so there is no pop result to await either. Something whose
/// disposal is observable is the smallest honest signal available: the pill
/// row sits behind the bubble while the panel is open, so recomputing when it
/// closes is soon enough for anything the user can actually see.
class _AlertPanelHost extends StatefulWidget {
  final VoidCallback onClosed;

  const _AlertPanelHost({required this.onClosed});

  @override
  State<_AlertPanelHost> createState() => _AlertPanelHostState();
}

class _AlertPanelHostState extends State<_AlertPanelHost> {
  @override
  void dispose() {
    widget.onClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const KeywordAlertsPanel();
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
