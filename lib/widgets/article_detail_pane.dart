import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../services/ad_blocklist.dart';
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

  const ArticleDetailPane({super.key, required this.article, this.onClose});

  @override
  State<ArticleDetailPane> createState() => _ArticleDetailPaneState();
}

class _ArticleDetailPaneState extends State<ArticleDetailPane> {
  bool _loading = true;

  @override
  void didUpdateWidget(ArticleDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new article in the same pane starts a fresh load. Without this the
    // spinner state would be left wherever the previous article finished.
    if (oldWidget.article.url != widget.article.url) {
      setState(() => _loading = true);
    }
  }

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
                initialUserScripts: UnmodifiableListView<UserScript>([
                  UserScript(
                    source: _kDenyNotificationsJs,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                  UserScript(
                    source: _kHideConsentBannersJs,
                    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                  ),
                ]),
                shouldInterceptRequest: (controller, request) async {
                  if (AdBlocklist.instance.blocks(request.url)) {
                    if (kDebugMode) {
                      debugPrint('[adblock] BLOCKED ${request.url.host}');
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
                    debugPrint('[adblock] allowed ${request.url.host}');
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
