import 'dart:collection';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../models/content_block.dart';
import '../repositories/article_repository.dart';
import '../repositories/settings_repository.dart';
import '../services/ad_blocklist.dart';
import '../services/clean_reader.dart';
import '../services/saved_state_notifier.dart';
import '../services/share_service.dart';
import '../utils/date_utils.dart';
import 'clean_article_view.dart';
import 'notification_banner.dart';
import 'spinning_refresh_icon.dart';
import '../theme/app_theme.dart';

/// Overrides `Notification.requestPermission` before the page's own scripts
/// run, so a site that asks for notification permission on load is answered
/// "denied" without a system prompt ever appearing.
///
/// Injected at document *start*, which is the whole point — at document end
/// the page has already asked.
const String _kDenyNotificationsJs = '''
(function () {
  try {
    if (typeof Notification === 'undefined') return;
    Notification.requestPermission = function (cb) {
      if (typeof cb === 'function') { try { cb('denied'); } catch (e) {} }
      return Promise.resolve('denied');
    };
    try {
      Object.defineProperty(Notification, 'permission', {
        get: function () { return 'denied'; },
        configurable: true
      });
    } catch (e) {}
  } catch (e) {}
})();
''';

/// Hides the consent banners of the handful of CMP vendors most sites use,
/// plus a deliberately small generic fallback.
///
/// Hiding only — nothing here clicks Accept or Reject. Driving a CMP's own
/// buttons needs per-vendor logic and breaks whenever a vendor reshuffles
/// its DOM; a banner that is merely hidden leaves the site in its default
/// state, which is the one that hasn't been granted tracking consent.
const String _kHideConsentBannersCss = '''
#onetrust-banner-sdk, #onetrust-consent-sdk,
#CybotCookiebotDialog, #CybotCookiebotDialogBodyUnderlay,
.qc-cmp2-container, .qc-cmp2-summary-buttons,
#truste-consent-track, #trustarc-banner-overlay,
#didomi-host, .didomi-consent-popup-container,
[class*="cookie-consent"], [class*="cookie-banner"],
[id*="cookie-consent"], [id*="cookie-banner"]
{ display: none !important; }
''';

/// document.head does not necessarily exist yet at document-start, so this
/// falls back to documentElement rather than silently doing nothing.
final String _kHideConsentBannersJs = '''
(function () {
  try {
    var style = document.createElement('style');
    style.textContent = ${_jsStringLiteral(_kHideConsentBannersCss)};
    (document.head || document.documentElement).appendChild(style);
  } catch (e) {}
})();
''';

String _jsStringLiteral(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n');
  return '"$escaped"';
}

/// The article reader: one configured [InAppWebView] plus its chrome.
///
/// This is the *only* place a webview gets configured. Both the phone's
/// full-screen route and the three-column right-hand pane render this widget,
/// so the blocking rules, the injected scripts and the pop-up policy cannot
/// drift apart between the two.
class ArticleDetailPane extends StatefulWidget {
  final Article article;

  /// Shown as a close affordance when non-null. The full-screen route passes
  /// a pop; the three-column pane passes a controller clear.
  final VoidCallback? onClose;

  /// Test-only seam: supplies the clean-mode setting instead of reading it
  /// from the database. Widget tests can't combine testWidgets() with real
  /// sqflite I/O — the FFI Future never resolves inside flutter_test's
  /// FakeAsync zone, so the read below would hang rather than fail, and the
  /// clean load would never start. Same reasoning, and same shape, as
  /// `ArticleSummarySheet.summaryLengthForTesting`. Unused in production.
  @visibleForTesting
  final bool? cleanModeEnabledForTesting;

  /// Test-only seam: replaces the real [InAppWebView], which cannot be built
  /// without a platform view. Same shape as `FlashApp.homeOverrideForTesting`.
  /// Unused in production.
  @visibleForTesting
  final WidgetBuilder? webViewOverrideForTesting;

  const ArticleDetailPane({
    super.key,
    required this.article,
    this.onClose,
    this.cleanModeEnabledForTesting,
    this.webViewOverrideForTesting,
  });

  @override
  State<ArticleDetailPane> createState() => _ArticleDetailPaneState();
}

class _ArticleDetailPaneState extends State<ArticleDetailPane> {
  bool _loading = true;

  /// The extracted article, once one is available. Non-null is exactly the
  /// condition for offering the toggle.
  List<ContentBlock>? _cleanBlocks;

  /// Whether the clean view is the one currently on screen. Always starts
  /// false: the publisher's own page is the default view for every article.
  bool _cleanMode = false;

  final _bannerKey = GlobalKey<NotificationBannerState>();

  /// **The pane owns the bookmark rather than receiving a callback, and the
  /// precedent is three lines up.**
  ///
  /// `openArticle()` is a free function with two positional parameters and no
  /// repository access, and it is one of five call sites. Threading a callback
  /// would mean editing all five plus both `ArticleDetailPane` constructions,
  /// and two of those five — the search screen and the keyword group panel
  /// — render plain `ListTile`s with no saved-state code at all, so they
  /// would each have to invent a bookmark implementation to pass down.
  ///
  /// This pane already constructs `SettingsRepository()` inline twice and calls
  /// `launchUrl` directly, so owning one more repository is the established
  /// shape here, not a new one. `ArticleCard` taking `onBookmark` is the
  /// counter-precedent and it is a different case: the card lives inside a
  /// screen that already owns the list and its repository.
  final _articleRepo = ArticleRepository();

  /// Mirrors the article's saved state so the glyph can change without a new
  /// `Article` arriving. The widget's own `article.isSaved` is a snapshot from
  /// whenever the list last loaded.
  late bool _isSaved;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.article.isSaved;
    // A bookmark button that lies about state is worse than no bookmark
    // button: the same article can be unsaved from the card's rail or the
    // radial menu while this pane is open behind them.
    SavedStateNotifier.instance.addListener(_onExternalSavedStateChanged);
    _loadCleanVersion();
  }

  @override
  void dispose() {
    SavedStateNotifier.instance.removeListener(_onExternalSavedStateChanged);
    super.dispose();
  }

  /// Someone else changed this article's saved state.
  ///
  /// The payload is read synchronously, which is required rather than tidy:
  /// the notifier holds only the last change and the next broadcast overwrites
  /// it, so deferring across an await would act on a different article.
  void _onExternalSavedStateChanged() {
    if (!mounted) return;
    final id = SavedStateNotifier.instance.articleId;
    final saved = SavedStateNotifier.instance.saved;
    // The guard is what makes this self-cancelling: this pane's own write
    // broadcasts too, and by then `_isSaved` already agrees.
    if (id == null || id != widget.article.id || saved == _isSaved) return;
    setState(() => _isSaved = saved);
  }

  /// Writes, then tells everyone else.
  ///
  /// **Silently does nothing when the article has no id**, which is not a
  /// defensive flourish: an article opened from the Alerts tab is built by
  /// `AlertEntry.toArticle()` and deliberately carries a null id, because its
  /// identity there is (feedId, guid). `feed_screen._toggleSaved` guards the
  /// same way. The button is hidden in that case rather than left to do
  /// nothing when pressed — see `_PaneTopBar`.
  Future<void> _toggleSaved() async {
    final id = widget.article.id;
    if (id == null) return;

    final nowSaved = !_isSaved;
    await _articleRepo.setSaved(id, saved: nowSaved);
    HapticFeedback.lightImpact();
    if (mounted) setState(() => _isSaved = nowSaved);

    // After the local patch, so this pane's own listener sees a value that
    // already agrees and does nothing.
    SavedStateNotifier.instance.articleSavedStateChanged(id, saved: nowSaved);
  }

  Future<void> _share() => ShareService().shareArticle(widget.article);

  /// "Publisher · date", falling back to the URL's host.
  ///
  /// Both halves are nullable on `Article`, so the join really can come out
  /// empty — and with the title line gone that would leave the bar with no
  /// text at all. The host is the fallback because it is always there (it is
  /// the thing that was opened), it is true, and it is what Chrome puts in the
  /// same position.
  ///
  /// `www.` is stripped for the same reason Chrome strips it: it is four
  /// characters of nothing, and a bar this narrow has none to spare.
  String _sourceFor(BuildContext context) {
    final publisher = widget.article.feedTitle?.trim() ?? '';
    if (publisher.isNotEmpty) return publisher;

    // `feedTitle` is nullable, and this is the bar's headline text now, so it
    // cannot be allowed to come out empty. The host is always available — it
    // is what was opened — it is true, and it is what Chrome shows in the same
    // position. `www.` is stripped for the same reason Chrome strips it: four
    // characters of nothing in a line that has about 160dp.
    final host = Uri.tryParse(widget.article.url)?.host ?? '';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  String _dateFor(BuildContext context) => formatPublishedDate(
        widget.article.publishedAt,
        Localizations.localeOf(context).toLanguageTag(),
      );

  @override
  void didUpdateWidget(ArticleDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new article in the same pane starts a fresh load. Without this the
    // spinner state would be left wherever the previous article finished.
    if (oldWidget.article.url != widget.article.url) {
      // The previous article's banner must not linger over this one for the
      // remainder of its four seconds.
      _bannerKey.currentState?.dismiss();
      setState(() {
        _loading = true;
        _cleanBlocks = null;
        _cleanMode = false;
        // The incoming article carries its own saved state, and it is fresher
        // than whatever the previous one left here.
        _isSaved = widget.article.isSaved;
      });
      _loadCleanVersion();
    }
  }

  /// Extracts in the background, in parallel with the WebView's own load.
  ///
  /// Deliberately an independent HTTP GET rather than a read of the WebView's
  /// DOM: most publishers serve the article text in the initial server-rendered
  /// HTML, which is what [ArticleExtractor] was tuned against, so a plain fetch
  /// usually finishes before the page has finished pulling in its ads.
  ///
  /// Costs one extra GET per opened article, including on mobile data, for the
  /// majority of articles where the button is never tapped. That is the price
  /// of the offer being ready the moment the reader wants it, and it is what
  /// the setting exists to turn off.
  Future<void> _loadCleanVersion() async {
    final requestedUrl = widget.article.url;

    // The setting is checked before the cache, not after. It is a master
    // switch, not part of the cache key — checked after, a reader who turned
    // it off mid-session would keep seeing the button on every article opened
    // earlier until the app was relaunched. That is verbatim the bug
    // SummaryCache's own doc comment describes.
    //
    // Read fresh on every load rather than once per State, so flipping the
    // toggle takes effect on the very next article. Nothing listens to
    // SettingsNotifier to retract the button from the article already open:
    // no other reading surface does, and it would buy a listener lifecycle
    // for a case nobody hits.
    final enabled = widget.cleanModeEnabledForTesting ??
        (await SettingsRepository().get(kCleanModeEnabledSettingKey) ??
                'true') ==
            'true';
    if (!enabled) return;
    if (!mounted || widget.article.url != requestedUrl) return;

    final result = await CleanReader().load(requestedUrl);

    // The pane may have moved on to a different article while that was in
    // flight — the tablet layout swaps `article` in place. A result, or a
    // failure, for a URL that is no longer on screen must not touch this
    // State at all: without this guard, opening a slow-failing article, then
    // tapping another, shows "no clean version" over the second one, whose
    // clean version may be sitting right there behind the button.
    if (!mounted || widget.article.url != requestedUrl) return;

    switch (result.outcome) {
      case CleanReadOutcome.ready:
        setState(() => _cleanBlocks = result.blocks);
      case CleanReadOutcome.unavailable:
        // First verdict for this URL this session, so say so once.
        final l10n = AppLocalizations.of(context)!;
        _bannerKey.currentState?.show(l10n.cleanModeUnavailable);
      case CleanReadOutcome.alreadyUnavailable:
        // Already judged and already reported. Reopening an article that has
        // no clean version should be quiet, not a recurring error.
        break;
    }
  }

  void _toggleCleanMode() => setState(() => _cleanMode = !_cleanMode);

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.article.url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing useful to say if the platform refuses; the article is still
      // on screen in the pane behind this.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        _PaneTopBar(
          // Play policy: a news app must name the source of every article and
          // show its publication date. The reading pane is where an article is
          // read in full, so it is the last place either should be missing.
          // Resolved here rather than inside the bar so that stays a
          // StatelessWidget with no context-dependent work of its own.
          //
          // With the title line gone this is the bar's only text, so it can no
          // longer be allowed to come out empty — `feedTitle` and
          // `publishedAt` are both nullable, and an article with neither would
          // leave a bar with four buttons and nothing saying where you are.
          // The host is the fallback: truthful, always available since the URL
          // is what was opened, and what Chrome shows in the same position.
          source: _sourceFor(context),
          date: _dateFor(context),
          onClose: widget.onClose,
          onOpenInBrowser: _openInBrowser,
          openInBrowserTooltip: l10n.openInBrowser,
          onBookmark: widget.article.id == null ? null : _toggleSaved,
          isSaved: _isSaved,
          bookmarkTooltip: _isSaved ? l10n.saved : l10n.bookmark,
          onShare: _share,
          shareTooltip: l10n.share,
        ),
        Expanded(
          child: Stack(
            children: [
              // IndexedStack, not a swap: the WebView stays mounted so that
              // toggling to the clean view and back does not reload the page,
              // lose the reader's scroll position, or restart embedded media.
              //
              // IndexedStack rather than Offstage because RenderIndexedStack
              // lays every child out at the full stack size unconditionally,
              // while RenderOffstage reports constraints.smallest to its
              // parent. Both are correct under today's tight constraints, but
              // only one stays correct if this pane is ever nested in
              // something unbounded — and a resized platform view means the
              // page reflows and the scroll position is gone. This is also
              // already the app's idiom for "keep these alive, show one"
              // (see app.dart's screen stack).
              //
              // Note the article swap is a different matter: the WebView is
              // keyed by URL, so a new article tears the platform view down
              // and rebuilds it regardless. Only the toggle preserves state.
              IndexedStack(
                index: _cleanMode ? 1 : 0,
                sizing: StackFit.expand,
                children: [
                  Stack(
                    children: [
                      widget.webViewOverrideForTesting?.call(context) ??
                          InAppWebView(
                            // Keyed by URL so switching articles rebuilds the platform
                            // view rather than reusing one pointed at the old page.
                            key: ValueKey(widget.article.url),
                            initialUrlRequest:
                                URLRequest(url: WebUri(widget.article.url)),
                            initialSettings: InAppWebViewSettings(
                              // Without this the resource-level callback below is never
                              // invoked at all — sub-resource blocking is opt-in.
                              useShouldInterceptRequest: true,
                              // Pop-ups: refused at the settings layer, and refused again
                              // in onCreateWindow for the ones that get past it.
                              javaScriptCanOpenWindowsAutomatically: false,
                              supportMultipleWindows: false,
                              transparentBackground: true,
                              // A reader, not a browser: no long-press context menus over
                              // links or images.
                              disableContextMenu: true,
                            ),
                            initialUserScripts:
                                UnmodifiableListView<UserScript>([
                              UserScript(
                                source: _kDenyNotificationsJs,
                                injectionTime:
                                    UserScriptInjectionTime.AT_DOCUMENT_START,
                              ),
                              UserScript(
                                source: _kHideConsentBannersJs,
                                injectionTime:
                                    UserScriptInjectionTime.AT_DOCUMENT_START,
                              ),
                            ]),
                            shouldInterceptRequest:
                                (controller, request) async {
                              if (AdBlocklist.instance.blocks(request.url)) {
                                if (kDebugMode) {
                                  debugPrint(
                                      '[adblock] BLOCKED ${request.url.host}');
                                }
                                // An empty 200 rather than an error: a blocked script that
                                // errors can take a page's own error handling down with it.
                                return WebResourceResponse(
                                  contentType: 'text/plain',
                                  contentEncoding: 'utf-8',
                                  data: Uint8List(0),
                                );
                              }
                              if (kDebugMode) {
                                debugPrint(
                                    '[adblock] allowed ${request.url.host}');
                              }
                              // null means "load it as usual".
                              return null;
                            },
                            onCreateWindow: (controller, action) async {
                              // false = do not open the requested window. Returning true
                              // here would oblige us to actually create a second webview.
                              return false;
                            },
                            onLoadStop: (controller, url) {
                              if (mounted) setState(() => _loading = false);
                            },
                            onReceivedError: (controller, request, error) {
                              if (mounted && request.isForMainFrame == true) {
                                setState(() => _loading = false);
                              }
                            },
                          ),
                      // Inside child 0, so it is hidden along with the page it
                      // belongs to. Left outside, the WebView's own spinner
                      // would sit on top of the clean text whenever extraction
                      // finished before the page did.
                      if (_loading)
                        Container(
                          color: theme.colorScheme.surface,
                          child: Center(
                            child: SpinningRefreshIcon(
                              size: 36,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  // IndexedStack needs both children to exist; only one is
                  // ever shown, and index 1 is unreachable until there are
                  // blocks to put in it.
                  _cleanBlocks != null
                      ? CleanArticleView(blocks: _cleanBlocks!)
                      : const SizedBox.shrink(),
                ],
              ),
              // Positioned, not a row in the Column above: as a row it would
              // shorten the Expanded when it appeared, resizing the platform
              // view mid-read and reflowing the page under the reader.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: NotificationBanner(key: _bannerKey),
              ),
              if (_cleanBlocks != null)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    key: const ValueKey('cleanModeToggle'),
                    // Explicit and unique: on the tablet the middle column's
                    // screens and this pane share one Navigator, and
                    // 'refresh', 'search' and 'mark_all_read' are taken.
                    heroTag: 'clean_mode_toggle',
                    onPressed: _toggleCleanMode,
                    icon: Icon(_cleanMode
                        ? Icons.public_rounded
                        : Icons.auto_stories_rounded),
                    label: Text(_cleanMode
                        ? l10n.cleanModeBackToWeb
                        : l10n.cleanModeReady),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The reader's chrome: where you are, and four ways to act on it.
///
/// **The article title line is gone, and that is a decision rather than a
/// cut.** Four 48dp buttons leave a title roughly 26 characters at 360dp,
/// which is a stub and not a title — and the user has just tapped the article,
/// with the headline in front of them on the page itself. What a reader's bar
/// is for is saying where you are and how to leave; Chrome's custom tabs show
/// the domain for the same reason.
///
/// So the source is promoted to `titleSmall` in the full ink, and the date
/// keeps the `labelSmall` second line it always had — publisher **and** date,
/// which Play policy requires a news app to show for every article.
///
/// **The two were briefly one line, and that is why the second one is back.**
/// Joined as `publisher · date` on a 360dp phone with four buttons, the text
/// has about 160dp: enough for "Sky Sports · Sep 15, 2026 9:44 …" and no more,
/// so the date was cut on every article. Dropping the *title* was right for a
/// different reason — 160dp of headline is a stub — and 160dp of source name
/// is a whole name. The second line was never the thing short of room.
///
/// **The bar's height does not change, and that is load-bearing.** The four
/// `IconButton`s set a 48dp floor and the 4dp vertical padding takes it to 56,
/// which is what the column measured with a title and a date, then with a
/// source alone, and now with a source and a date. A bar that shrank would
/// resize the platform view mid-read on the tablet, reflowing the page and
/// losing the scroll position. Pinned as a number in
/// `reader_action_bar_test.dart`.
class _PaneTopBar extends StatelessWidget {
  /// The publisher, or the URL's host when the article carries no feed title.
  ///
  /// **Never empty** — this is the bar's headline text now, so the fallback is
  /// not optional. It is resolved at the construction site rather than here,
  /// keeping this widget free of context-dependent work.
  final String source;

  /// The published date, already localised. Empty when the article carries no
  /// timestamp, in which case no second line is drawn and the source sits on
  /// its own.
  final String date;

  final VoidCallback? onClose;
  final VoidCallback onOpenInBrowser;
  final String openInBrowserTooltip;

  /// Null when the article has no id, which is how an article opened from the
  /// Alerts tab arrives: `AlertEntry.toArticle()` leaves the id null on
  /// purpose, since identity there is (feedId, guid). A bookmark cannot be
  /// written without one, so the button is **absent** rather than present and
  /// inert — a control that does nothing when pressed is a worse answer than
  /// one that is not offered.
  final VoidCallback? onBookmark;
  final bool isSaved;
  final String bookmarkTooltip;

  final VoidCallback onShare;
  final String shareTooltip;

  const _PaneTopBar({
    required this.source,
    required this.date,
    required this.onClose,
    required this.onOpenInBrowser,
    required this.openInBrowserTooltip,
    required this.onBookmark,
    required this.isSaved,
    required this.bookmarkTooltip,
    required this.onShare,
    required this.shareTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              if (onClose != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: onClose,
                  tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                )
              else
                const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Line 1. Promoted to `titleSmall` in the full ink when
                    // the article title left: this is what the bar is for,
                    // saying where you are.
                    //
                    // Ellipsised, and the truncation falls in the right place
                    // because the date is no longer joined on the end of it.
                    // The longest starter-pack source, "The New York Times
                    // (World)", loses its qualifier and keeps the masthead.
                    Text(
                      source,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.onSurface),
                    ),
                    // Line 2. Its own line rather than joined with a separator,
                    // which is the whole of this fix: joined, it was the half
                    // that got cut, on every article.
                    if (date.isNotEmpty)
                      Text(
                        date,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.flashColors.onSurfaceMuted),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                onPressed: onOpenInBrowser,
                tooltip: openInBrowserTooltip,
              ),
              // Absent, not disabled, when the article has no id. See the
              // field's doc.
              if (onBookmark != null)
                IconButton(
                  // The action rail's treatment exactly, so a bookmark means
                  // the same thing in the list and in the reader: filled in
                  // `secondary` when saved, outline when not. 1.6 is canonical
                  // on the saved half.
                  //
                  // Unsaved passes no colour, which lands on M3's
                  // `onSurfaceVariant` default — the same ink the close and
                  // open-in-browser glyphs beside it already take, so an
                  // unsaved bookmark sits level with its neighbours and a
                  // saved one is the only warm thing in the bar.
                  icon: Icon(
                    isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 20,
                    color: isSaved ? theme.colorScheme.secondary : null,
                  ),
                  onPressed: onBookmark,
                  tooltip: bookmarkTooltip,
                ),
              IconButton(
                icon: const Icon(Icons.share_rounded, size: 20),
                onPressed: onShare,
                tooltip: shareTooltip,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the right-hand column shows before anything has been picked.
class ArticleDetailPlaceholder extends StatelessWidget {
  const ArticleDetailPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    // **Not an empty state, and deliberately exempt from their roles.**
    //
    // Pass 8's rule is that empty-state copy takes `onSurfaceVariant`, because
    // when a screen is empty that copy is the only content on it. This pane is
    // the exception the rule's own reasoning excludes: nothing here is empty.
    // The middle column is full of articles and this is the right-hand column
    // waiting to be told which one — genuinely secondary to the list beside
    // it, and the one place in the app where recessive is correct.
    //
    // Pass 2 decided this and `ink_roles_test.dart` has pinned it since, in
    // both brightnesses, for the glyph as well as the text. Swept into the
    // rule during this pass and reverted when that test said so, which is the
    // test doing exactly what it was written for.
    final muted = theme.flashColors.onSurfaceMuted;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined, size: 44, color: muted),
            const SizedBox(height: 12),
            Text(
              l10n.selectAnArticle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
