import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../models/content_block.dart';
import '../repositories/settings_repository.dart';
import '../services/ad_blocklist.dart';
import '../services/clean_reader.dart';
import 'clean_article_view.dart';
import 'notification_banner.dart';
import 'spinning_refresh_icon.dart';

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

  @override
  void initState() {
    super.initState();
    _loadCleanVersion();
  }

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
          title: widget.article.title,
          onClose: widget.onClose,
          onOpenInBrowser: _openInBrowser,
          openInBrowserTooltip: l10n.openInBrowser,
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

class _PaneTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onClose;
  final VoidCallback onOpenInBrowser;
  final String openInBrowserTooltip;

  const _PaneTopBar({
    required this.title,
    required this.onClose,
    required this.onOpenInBrowser,
    required this.openInBrowserTooltip,
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
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                onPressed: onOpenInBrowser,
                tooltip: openInBrowserTooltip,
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
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.35);
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
