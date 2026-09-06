import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/alert_entry.dart';
import '../models/article.dart';
import '../repositories/alert_match_repository.dart';
import '../repositories/article_repository.dart';
import '../services/alert_navigation_intent.dart';
import '../services/alerts_changed_notifier.dart';
import '../services/read_state_notifier.dart';
import '../services/saved_state_notifier.dart';
import '../services/loading_controller.dart';
import '../services/share_service.dart';
import '../utils/day_grouping.dart';
import '../widgets/article_card.dart';
import '../widgets/day_header.dart';
import '../widgets/fetching_indicator.dart';
import '../widgets/notification_banner.dart';
import '../widgets/quick_settings_action.dart';

/// The Alerts tab: every article any alert keyword has ever caught.
///
/// ── The whole behaviour, in one place ──────────────────────────────────────
///
/// Written out together rather than discovered rule by rule, because these
/// rules only make sense against each other, and the last time this codebase
/// grew a multi-rule feature one clause at a time it shipped a regression per
/// clause (PRD §10).
///
/// **What it shows.** `alert_matches`, and nothing else. Those rows carry
/// their own snapshot of the article and its feed, so this list stays readable
/// after the article has been retired, cleaned up, tombstoned, aged out, or
/// had its whole feed deleted. That is the entire reason the table exists, so
/// this screen applies *none* of the article rules: no age cutoff, no per-feed
/// cap, no retirement, no cleanup. A display filter here would reintroduce the
/// disappearing-alert bug at the last possible step.
///
/// **Identity is `(feedId, guid)`, never an article id.** `AlertEntry
/// .toArticle()` deliberately leaves `id` null, so every operation below keys
/// off the pair. Two consequences that look like style choices and are not:
/// swipe actions stay off, because `ArticleCard`'s `Dismissible` keys on
/// `ValueKey('article_<id>')` and every card here would claim the same
/// `article_null`; and no scroll anchor is kept, because `ScrollAnchor` is
/// keyed on the id too.
///
/// **Read state lives in two tables and both are written.** The snapshot
/// always, the `articles` row only when it still exists — which it usually
/// does not, which is why `alert_matches.is_read` is a column rather than
/// something read through a join. Reading an entry dims it and nothing more:
/// an entry that vanished on being read would empty the list out as the user
/// worked through it, and this is a permanent record, not an inbox.
///
/// **Mark-read-on-scroll is off here**, whatever the setting says. This is a
/// surface the user returns to deliberately, and auto-dimming everything on
/// the first scroll-through would destroy the only signal separating seen from
/// unseen. Enforced structurally rather than by a flag: the listener that
/// implements it lives in FeedScreen, attached to FeedScreen's controller.
///
/// **Bookmarking needs the live article**, since `is_saved` is a column on
/// `articles`, and mirroring it into the snapshot would be exactly the second
/// copy of state this rework existed to remove. The button is shown on every
/// card regardless and says so when there is nothing to bookmark — hiding it
/// would reflow the radial menu from four buttons to three on precisely the
/// cards whose article has been cleaned up, moving Share and Summary under the
/// user's thumb for reasons they cannot see.
///
/// **Deleting is the only way an entry leaves.** No confirmation and no undo,
/// matching mark-all-read's existing stance, and every keyword row behind the
/// card goes with it — a leftover row would rebuild the same card on the next
/// read.
///
/// **The count on the nav destination** is `totalEntryCount()`: every entry,
/// read and unread alike, which is exactly what the Alerts pill showed before
/// this screen existed. It is not an unread count and must not quietly become
/// one.
///
/// **Staying current.** This screen is kept alive in the app's `IndexedStack`,
/// so `initState` runs once per launch. [AlertsChangedNotifier] is what keeps
/// it honest afterwards, when a refresh brings new matches in or the keyword
/// panel takes some away.
///
/// **Arriving from a notification.** The app shell moves the nav bar here; the
/// pending intent is consumed *here*, which reloads and scrolls to the top, so
/// the tap lands on the alert that caused it rather than wherever the list was
/// left. The flag is latched precisely so that a cold start — where this
/// screen does not exist yet at the moment the tap is recorded — takes the
/// same path as a tap on a running app.
///
/// **Pull-to-refresh re-queries the database and fetches nothing.** Matches
/// are written by the feed refresh elsewhere; there is no network call that
/// belongs to this screen.
class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final _alertMatchRepo = AlertMatchRepository();
  final _articleRepo = ArticleRepository();
  final _shareService = ShareService();
  final _bannerKey = GlobalKey<NotificationBannerState>();
  final _scrollController = ScrollController();

  List<AlertEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AlertsChangedNotifier.instance.addListener(_onAlertsChanged);
    AlertNavigationIntent.instance.addListener(_onAlertNavigationRequested);
    _load().then((_) => _consumeAlertNavigation());
  }

  @override
  void dispose() {
    AlertsChangedNotifier.instance.removeListener(_onAlertsChanged);
    AlertNavigationIntent.instance.removeListener(_onAlertNavigationRequested);
    _scrollController.dispose();
    super.dispose();
  }

  void _onAlertsChanged() {
    if (mounted) _load();
  }

  void _onAlertNavigationRequested() {
    if (mounted) _consumeAlertNavigation();
  }

  /// A tapped keyword-alert notification. The shell has already brought this
  /// screen forward; this reloads and goes to the top, because the alert that
  /// caused the tap is the newest one and the list is newest-matched-first.
  Future<void> _consumeAlertNavigation() async {
    if (!mounted) return;
    if (!AlertNavigationIntent.instance.consumePending()) return;
    await _load();
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  Future<void> _load() async {
    final entries = await _alertMatchRepo.getEntries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Writes the read flag to both tables, in that order and independently.
  Future<void> _setEntryRead(Article snapshot, {required bool isRead}) async {
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
    if (mounted) await _load();
  }

  Future<void> _openEntry(Article snapshot) async {
    await _alertMatchRepo.setRead(snapshot.feedId, snapshot.guid, isRead: true);
    final row = await _articleRepo.findByGuid(snapshot.feedId, snapshot.guid);
    if (row?.id != null && !row!.isRead) {
      await _articleRepo.markAsRead(row.id!);
      ReadStateNotifier.instance.articleReadStateChanged();
    }
    if (!mounted) return;
    await _load();

    if (!mounted) return;
    final uri = Uri.tryParse(snapshot.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // A URL the platform refuses to open is not worth a dialog. The entry
      // has already been marked read, which is what the tap asked for.
    }
  }

  /// The `articles` row is what carries `is_saved`, so this needs it alive.
  Future<void> _toggleSaved(Article snapshot) async {
    final row = await _articleRepo.findByGuid(snapshot.feedId, snapshot.guid);
    if (!mounted) return;
    if (row?.id == null) {
      _bannerKey.currentState
          ?.show(AppLocalizations.of(context)!.alertsArticleGone);
      return;
    }
    final nowSaved = !row!.isSaved;
    await _articleRepo.setSaved(row.id!, saved: nowSaved);
    HapticFeedback.lightImpact();
    // Bookmarks is kept alive and loads only in initState, so without this the
    // bookmark does not appear there until a pull-to-refresh.
    SavedStateNotifier.instance
        .articleSavedStateChanged(row.id!, saved: nowSaved);
  }

  /// Marks the record read and nothing else: no retire, no cleanup, no fetch.
  ///
  /// Every one of those is a deletion or a refetch of *articles*, and this is
  /// the one list in the app that no deletion path is allowed to touch —
  /// running them here would put back, through a toolbar button, exactly the
  /// loss `alert_matches` exists to prevent.
  Future<void> _markAllRead() async {
    HapticFeedback.mediumImpact();
    await LoadingController.instance.run(() async {
      await _alertMatchRepo.setAllRead();
      // Mirrored onto whichever articles rows are still there, so an entry
      // just cleared here is not still bold in the ordinary feed.
      for (final entry in await _alertMatchRepo.getEntries()) {
        final row = await _articleRepo.findByGuid(entry.feedId, entry.guid);
        if (row?.id != null && !row!.isRead) {
          await _articleRepo.markAsRead(row.id!);
        }
      }
      ReadStateNotifier.instance.articleReadStateChanged();
      if (mounted) await _load();
    }, label: 'Marking all read');
    if (!mounted) return;
    _bannerKey.currentState
        ?.show(AppLocalizations.of(context)!.alertsMarkAllReadBanner);
  }

  Future<void> _deleteEntry(Article snapshot) async {
    await _alertMatchRepo.deleteEntry(snapshot.feedId, snapshot.guid);
    if (!mounted) return;
    // Dropped locally first, so the card goes as the menu closes rather than
    // after the database has answered.
    setState(() {
      _entries = [
        for (final e in _entries)
          if (e.feedId != snapshot.feedId || e.guid != snapshot.guid) e,
      ];
    });
    AlertsChangedNotifier.instance.alertsChanged();
    _bannerKey.currentState
        ?.show(AppLocalizations.of(context)!.alertsRemovedBanner);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Grouped by the day the keyword *matched*, not the day the article was
  /// published: the list is a log of what the alerts caught, so an article
  /// published last month that matched this morning belongs under today.
  List<FeedRow> _rows() {
    final articles = [for (final e in _entries) e.toArticle()];
    final proxies = [
      for (var i = 0; i < _entries.length; i++)
        articles[i].copyWith(publishedAt: _entries[i].matchedAt),
    ];
    final rows = groupByDay(proxies, now: DateTime.now());
    var next = 0;
    return [
      for (final row in rows)
        if (row is ArticleRow) ArticleRow(articles[next++]) else row,
    ];
  }

  /// Keyed on the same NUL-joined pair the rest of the alerts code uses, so a
  /// guid containing a space cannot collide with its neighbour.
  Map<String, List<String>> _keywordsByPair() => {
        for (final e in _entries) '${e.feedId} ${e.guid}': e.keywords,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.alertsTab),
        centerTitle: false,
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              onPressed: _markAllRead,
              tooltip: l10n.markAllRead,
              icon: const Icon(Icons.done_all_rounded),
            ),
          const QuickSettingsAction(),
        ],
      ),
      body: Column(
        children: [
          NotificationBanner(key: _bannerKey),
          Expanded(
            child: _loading
                ? const Center(child: FetchingIndicator(size: 40))
                : _buildList(l10n, scheme),
          ),
        ],
      ),
    );
  }

  Widget _buildList(AppLocalizations l10n, ColorScheme scheme) {
    if (_entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        backgroundColor: scheme.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
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

    final rows = _rows();
    final keywordsByPair = _keywordsByPair();

    return RefreshIndicator(
      onRefresh: _load,
      backgroundColor: scheme.surface,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
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
                // Off, and not a style choice: the Dismissible keys on the
                // article id, which is null for every entry here, so a
                // swipe-enabled card is a duplicate-key crash rather than a
                // gesture.
                enableSwipeActions: false,
                alertKeywords:
                    keywordsByPair['${article.feedId} ${article.guid}'] ??
                        const [],
                onTap: () => _openEntry(article),
                onMarkRead: () => _setEntryRead(article, isRead: true),
                onMarkUnread: () => _setEntryRead(article, isRead: false),
                onShare: () => _shareService.shareArticle(article),
                onBookmark: () => _toggleSaved(article),
                // The bin is offered here and nowhere else. An alert match
                // outlives every path that deletes an article, so dismissing
                // it by hand is the only way one ever leaves the list.
                onDelete: () => _deleteEntry(article),
              ),
            ],
          );
        },
      ),
    );
  }
}
