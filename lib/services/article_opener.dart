import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/article.dart';
import '../repositories/settings_repository.dart';
import '../widgets/article_detail_pane.dart';
import 'article_detail_controller.dart';

/// How an article ended up being opened.
///
/// Callers need to tell these apart: only [external] backgrounds the app, and
/// the feed's scroll-anchor restore is armed on exactly that assumption — an
/// article that opened in-app produces no resume to consume the flag.
enum ArticleOpenMode { embedded, external, failed }

/// The one place that decides where a tapped article goes.
///
/// Three outcomes, in order of precedence:
///  * the reader is on and a detail pane is mounted above us (three-column
///    tablet layout) — hand the article to the pane;
///  * the reader is on with no pane — push the same pane as a full-screen
///    route;
///  * the reader is off — hand the URL to the browser, exactly as before.
///
/// The setting is read per tap rather than cached. The tap is already doing
/// database work (marking read), one more indexed single-row read is not what
/// makes it slow, and a cache here would be one more thing to invalidate when
/// the toggle is flipped from a screen that isn't this one.
Future<ArticleOpenMode> openArticle(
  BuildContext context,
  Article article,
) async {
  final uri = Uri.tryParse(article.url);
  if (uri == null) return ArticleOpenMode.failed;

  final embedded =
      (await SettingsRepository().get(kEmbeddedWebViewSettingKey) ?? 'true') ==
          'true';

  if (!context.mounted) return ArticleOpenMode.failed;

  if (embedded) {
    final pane = ArticleDetailScope.maybeOf(context);
    if (pane != null) {
      pane.show(article);
      return ArticleOpenMode.embedded;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (routeContext) => Scaffold(
          body: ArticleDetailPane(
            article: article,
            onClose: () => Navigator.of(routeContext).pop(),
          ),
        ),
      ),
    );
    return ArticleOpenMode.embedded;
  }

  try {
    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    return launched ? ArticleOpenMode.external : ArticleOpenMode.failed;
  } catch (_) {
    return ArticleOpenMode.failed;
  }
}

/// Settings key for the built-in reader. Defaults on wherever it is read.
const String kEmbeddedWebViewSettingKey = 'use_embedded_webview';
