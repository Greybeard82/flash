import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../services/gemini_nano_service.dart';

class ArticleSummarySheet extends StatefulWidget {
  final Article article;
  const ArticleSummarySheet({super.key, required this.article});

  @override
  State<ArticleSummarySheet> createState() => _ArticleSummarySheetState();
}

class _ArticleSummarySheetState extends State<ArticleSummarySheet> {
  String? _summary;
  bool _streaming = false; // true while receiving chunks
  bool _done = false;
  String? _errorMessage;
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    final nano = GeminiNanoService.instance;
    final available = await nano.isAvailable;

    if (!available) {
      if (mounted) {
        setState(() {
          _errorMessage = nano.unavailableReason;
          _done = true;
        });
      }
      return;
    }

    final locale = Platform.localeName.split('_').first;
    final content = widget.article.description ?? widget.article.title;
    final stream = await nano.summarizeStream(widget.article.title, content, locale: locale);

    if (stream == null) {
      if (mounted) {
        setState(() { _errorMessage = nano.unavailableReason; _done = true; });
      }
      return;
    }

    if (mounted) setState(() => _streaming = true);

    _sub = stream.listen(
      (text) {
        if (mounted) setState(() => _summary = text);
      },
      onDone: () {
        if (mounted) setState(() { _streaming = false; _done = true; });
      },
      onError: (e) {
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
            _streaming = false;
            _done = true;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final sheetHeight = MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.top;

    return SizedBox(
      height: sheetHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40, height: 4,
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
                Icon(Icons.auto_awesome_rounded, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(l10n.aiSummary,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (_streaming) ...[
                  const SizedBox(width: 8),
                  _LoadingDots(),
                ],
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
            const SizedBox(height: 16),

            // Scrollable content area (fills remaining space)
            Expanded(
              child: SingleChildScrollView(
                child: !_streaming && _summary == null && !_done
                    ? _LoadingDots()
                    : _errorMessage != null
                        ? _UnavailableMessage(l10n: l10n, theme: theme, debugReason: _errorMessage)
                        : _summary != null
                            ? _SummaryText(summary: _summary!, theme: theme, l10n: l10n, done: _done)
                            : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingDots extends StatefulWidget {
  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
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
                  width: 7, height: 7,
                  decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _UnavailableMessage extends StatelessWidget {
  final AppLocalizations l10n;
  final ThemeData theme;
  final String? debugReason;

  const _UnavailableMessage({required this.l10n, required this.theme, this.debugReason});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(l10n.aiSummaryUnavailable,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
              ),
            ],
          ),
          if (debugReason != null) ...[
            const SizedBox(height: 8),
            Text(debugReason!,
                style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error.withValues(alpha: 0.7))),
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

  const _SummaryText({required this.summary, required this.theme, required this.l10n, required this.done});

  @override
  Widget build(BuildContext context) {
    final bodyStyle = theme.textTheme.bodyMedium?.copyWith(fontSize: 16, height: 1.8);
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
                      Expanded(child: Text(line.trim().substring(2), style: bodyStyle)),
                    ],
                  )
                : Text(line, style: bodyStyle),
          ),
        if (done) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(l10n.aiSummaryDisclaimer,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
                        fontStyle: FontStyle.italic)),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: l10n.copySummary,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: summary));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.summaryCopied)),
                  );
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}
