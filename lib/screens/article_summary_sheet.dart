import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/notification_banner.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../repositories/settings_repository.dart';
import '../services/article_extractor.dart';
import '../services/gemini_cloud_service.dart';
import '../services/gemini_nano_service.dart';
import '../services/loading_controller.dart';
import '../services/summary_cache.dart';
import '../services/summary_formatter.dart';
import '../services/summary_source.dart';
import '../utils/date_utils.dart';

class ArticleSummarySheet extends StatefulWidget {
  final Article article;

  /// Test-only seam: supplies the summary-length tier instead of reading it
  /// from the database. Widget tests can't combine testWidgets() with real
  /// sqflite I/O — the FFI Future never resolves inside flutter_test's
  /// FakeAsync zone, so the read below would hang rather than fail, and the
  /// summary would never start. Same reasoning, and same shape, as
  /// `FlashApp.initialSettingsForTesting`. Unused in production.
  @visibleForTesting
  final String? summaryLengthForTesting;

  const ArticleSummarySheet({
    super.key,
    required this.article,
    this.summaryLengthForTesting,
  });

  @override
  State<ArticleSummarySheet> createState() => _ArticleSummarySheetState();
}

class _ArticleSummarySheetState extends State<ArticleSummarySheet> {
  final _bannerKey = GlobalKey<NotificationBannerState>();
  String? _summary;
  String _pending = ''; // chunks buffered here silently; never rendered
  bool _done = false;
  bool _writing = false; // extraction finished, streaming has started
  bool _teaserOnly = false;
  String? _errorMessage;

  /// Whether the failure came from the cloud fallback rather than from the
  /// device having no Nano. Only the sentence above [_errorMessage] differs;
  /// it is resolved in `build`, where the localisations are in hand, rather
  /// than reaching for context from an async generation.
  bool _cloudFailed = false;

  /// Whether this summary came from the network rather than from Nano.
  /// Drives the footer, which is a claim about where the article text
  /// went as much as about accuracy.
  bool _fromCloud = false;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    LoadingController.instance.run(_generate, label: 'Summarising');
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    final url = widget.article.url;

    // Read before the cache is consulted, not after: the tier is half the
    // cache key, so without it here a summary generated at one length would
    // be served back after the reader picked another.
    //
    // Fresh each time rather than from a snapshot — this setting lives in
    // Quick Settings and can change between one summary and the next — and
    // the same value goes on to the prompt and the formatter's backstop, so
    // all three agree on which tier this is.
    final tier = widget.summaryLengthForTesting ??
        (await SettingsRepository().getAll()).summaryLength;
    if (!mounted) return;

    // Decided before the cache is consulted so a cached summary is labelled
    // with the backend that produced it. `isAvailable` is memoised after its
    // first call, so asking here costs nothing.
    final nano = GeminiNanoService.instance;
    final available = await nano.isAvailable;
    if (!mounted) return;

    // Nano first, always: free, private, offline, and the thing this feature
    // was built around. The cloud is only for devices that have no Nano at
    // all -- never a way to override it where it works.
    final cloud = GeminiCloudService();
    final useCloud = shouldUseCloud(
        nanoAvailable: available, cloudConfigured: cloud.configured);
    if (useCloud) _fromCloud = true;

    final cached = SummaryCache.instance.get(url, tier);
    if (cached != null) {
      if (mounted) {
        setState(() {
          _summary = cached;
          _done = true;
        });
      }
      return;
    }

    if (!available && !useCloud) {
      if (mounted) {
        setState(() {
          _errorMessage = nano.unavailableReason;
          _done = true;
        });
      }
      return;
    }

    final locale = Platform.localeName.split('_').first;
    final description = widget.article.description;

    String content;
    var teaserOnly = false;
    try {
      final blocks = await ArticleExtractor().extract(widget.article.url);
      final extracted = SummarySource.fromBlocks(blocks, fallback: description);
      if (SummarySource.isSubstantial(extracted)) {
        content = extracted;
      } else {
        content = description ?? widget.article.title;
        teaserOnly = true;
      }
    } catch (_) {
      content = description ?? widget.article.title;
      teaserOnly = true;
    }

    if (!mounted) return;
    setState(() {
      _writing = true;
      _teaserOnly = teaserOnly;
    });

    // Same title, same extracted content, same tier either way -- and the
    // same prompt underneath, since both build it with buildSummaryPrompt.
    final stream = useCloud
        ? await cloud.summarizeStream(widget.article.title, content,
            locale: locale, lengthTier: tier)
        : await nano.summarizeStream(widget.article.title, content,
            locale: locale, lengthTier: tier);

    if (stream == null) {
      if (mounted) {
        setState(() {
          _cloudFailed = useCloud;
          _errorMessage = nano.unavailableReason;
          _done = true;
        });
      }
      return;
    }

    _sub = stream.listen(
      // Buffer only. No setState per chunk, so partial text is never rendered.
      (text) => _pending = text,
      onDone: () {
        if (mounted) {
          setState(() {
            _done = true;
            // A stream that errors also closes, so onError and onDone both
            // run. Without this the generic "empty" message overwrote the
            // real reason a moment after it arrived -- which is how a 404
            // naming the exact problem reached the sheet as "Empty summary
            // returned".
            if (_errorMessage != null) return;
            final result = SummaryFormatter.clamp(_pending, tier: tier);
            if (result.isEmpty) {
              _errorMessage = 'Empty summary returned';
            } else {
              _summary = result;
              SummaryCache.instance.put(url, tier, result);
            }
          });
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            // The raw thing -- an HTTP status, a quota name, an exception --
            // goes behind "Show details", exactly as Nano's platform code
            // does. What is visible by default is a sentence.
            _cloudFailed = useCloud;
            _errorMessage = e.toString();
            _done = true;
          });
        }
      },
    );
  }

  /// "Publisher · 12 Mar 2026 3:09 PM", with either half dropped when it
  /// is missing.
  String _attribution(BuildContext context) {
    final publisher = widget.article.feedTitle?.trim() ?? '';
    final date = formatPublishedDate(
      widget.article.publishedAt,
      Localizations.localeOf(context).toLanguageTag(),
    );
    return [publisher, date].where((part) => part.isNotEmpty).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final attribution = _attribution(context);

    // useSafeArea: true on the enclosing showModalBottomSheet (radial_menu.dart)
    // already insets for the safe area, so subtracting padding.top here would
    // double-count it. 90% of the screen height keeps this reading as a sheet
    // rather than a full-screen page.
    final maxSheetHeight = MediaQuery.of(context).size.height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NotificationBanner(key: _bannerKey),
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(l10n.aiSummary,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),

            // Article title (dimmed)
            Text(
              widget.article.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),

            // Publisher and publication date.
            //
            // Both are Play policy requirements for a news app: the source of
            // every article must be named, and its publication date shown. A
            // summary sheet is the one place a reader can be furthest from
            // either — the AI text is not the publisher's words, and nothing
            // else on this sheet says whose article is being summarised.
            //
            // feedTitle is nullable because it arrives from a join that not
            // every query performs, so each half is omitted independently
            // rather than rendering a stray separator.
            if (attribution.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                attribution,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // Content area. The summary scrolls only when it exceeds the
            // sheet; length is governed by the generation prompt, with
            // SummaryFormatter as a backstop.
            Flexible(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: !_done
                    ? Column(
                        key: const ValueKey('summaryLoading'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _LoadingDots(),
                          Text(
                            _writing
                                ? l10n.aiSummaryWriting
                                : l10n.aiSummaryReading,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      )
                    : _errorMessage != null
                        ? _UnavailableMessage(
                            key: const ValueKey('summaryUnavailable'),
                            l10n: l10n,
                            theme: theme,
                            message: _cloudFailed
                                ? l10n.aiSummaryFailed
                                : l10n.aiSummaryUnavailable,
                            debugReason: _errorMessage)
                        : _SummaryText(
                            key: const ValueKey('summaryText'),
                            summary: _summary!,
                            theme: theme,
                            l10n: l10n,
                            done: _done,
                            teaserOnly: _teaserOnly,
                            fromCloud: _fromCloud,
                            onCopied: () => _bannerKey.currentState
                                ?.show(l10n.summaryCopied)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  const _LoadingDots();

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final t = ((_controller.value - i / 3) % 1.0).abs();
            final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.2, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: theme.colorScheme.primary, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Why no summary appeared, in the user's terms.
///
/// The plain-language sentence is the whole message for almost everyone. The
/// raw platform reason underneath it -- `NANO_UNAVAILABLE: Feature status: 0`
/// and friends -- is what makes a bug report actionable, so it is kept, but it
/// is not something to hand an ordinary reader unprompted: it was rendering in
/// error red directly beneath the explanation, which read as a second, worse
/// problem rather than a detail.
class _UnavailableMessage extends StatefulWidget {
  final AppLocalizations l10n;
  final ThemeData theme;
  final String? debugReason;

  /// The plain-language sentence. Two of them reach here: "this device has
  /// no on-device AI", and "the summary could not be generated right now"
  /// when the cloud fallback fails. Same treatment either way -- the reason
  /// differs, what the reader needs from it does not.
  final String message;

  const _UnavailableMessage(
      {super.key,
      required this.l10n,
      required this.theme,
      required this.message,
      this.debugReason});

  @override
  State<_UnavailableMessage> createState() => _UnavailableMessageState();
}

class _UnavailableMessageState extends State<_UnavailableMessage> {
  bool _showDetails = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final l10n = widget.l10n;
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.5);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.message,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              ),
            ],
          ),
          if (widget.debugReason != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => setState(() => _showDetails = !_showDetails),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  // Indented to the width of the icon and its gap, so the
                  // control lines up under the sentence it belongs to.
                  padding: const EdgeInsets.fromLTRB(28, 6, 8, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showDetails
                            ? l10n.aiSummaryHideDetails
                            : l10n.aiSummaryShowDetails,
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: muted, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 2),
                      AnimatedRotation(
                        turns: _showDetails ? 0.5 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(Icons.expand_more_rounded,
                            size: 18, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(
                padding: const EdgeInsets.only(left: 28, top: 2),
                child: SelectableText(
                  widget.debugReason!,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontFamily: 'monospace'),
                ),
              ),
              crossFadeState: _showDetails
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 150),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryText extends StatelessWidget {
  final String summary;
  final ThemeData theme;
  final AppLocalizations l10n;
  final bool done;
  final bool teaserOnly;

  /// Which backend wrote this. The footer says where a summary came from,
  /// and on a device with no Nano that is now the network -- the article
  /// text left the device to be summarised. Saying "on-device" there would
  /// be a privacy claim that is not true.
  final bool fromCloud;

  /// Fired after the summary is copied. The confirmation belongs to the sheet
  /// (a banner at its top), not to this leaf widget.
  final VoidCallback onCopied;

  const _SummaryText(
      {super.key,
      required this.summary,
      required this.theme,
      required this.l10n,
      required this.done,
      required this.onCopied,
      this.teaserOnly = false,
      this.fromCloud = false});

  @override
  Widget build(BuildContext context) {
    final bodyStyle =
        theme.textTheme.bodyMedium?.copyWith(fontSize: 16, height: 1.8);
    final lines = summary.split('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: EdgeInsets.only(bottom: line.trim().isEmpty ? 0 : 6),
            child: line.trim().startsWith('- ')
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: bodyStyle),
                      Expanded(
                          child:
                              Text(line.trim().substring(2), style: bodyStyle)),
                    ],
                  )
                : Text(line, style: bodyStyle),
          ),
        if (done) ...[
          if (teaserOnly) ...[
            const SizedBox(height: 8),
            Text(l10n.aiSummaryTeaserOnly,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                    fromCloud
                        ? l10n.aiSummaryDisclaimerCloud
                        : l10n.aiSummaryDisclaimer,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.35),
                        fontStyle: FontStyle.italic)),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: l10n.copySummary,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: summary));
                  onCopied();
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}
