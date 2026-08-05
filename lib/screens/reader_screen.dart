import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../services/article_extractor.dart';
import '../services/loading_controller.dart';
import '../utils/date_utils.dart';
import '../utils/reading_time.dart';

class ReaderScreen extends StatefulWidget {
  final Article article;
  final String fontSize;
  final VoidCallback? onExtractionSucceeded;
  final VoidCallback? onExtractionFailed;

  const ReaderScreen({
    super.key,
    required this.article,
    this.fontSize = 'medium',
    this.onExtractionSucceeded,
    this.onExtractionFailed,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  List<ContentBlock>? _blocks;
  bool _loading = true;
  // Flag set in dispose() so async callbacks know not to touch the widget tree.
  bool _cancelled = false;

  double get _fs => switch (widget.fontSize) {
    'small' => 14.0,
    'large' => 19.0,
    _ => 16.0,
  };

  @override
  void initState() {
    super.initState();
    _loadArticle();
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _loadArticle() async {
    await LoadingController.instance.run(() async {
      try {
        final blocks = await ArticleExtractor().extract(widget.article.url);
        if (_cancelled || !mounted) return;
        if (blocks == null || blocks.isEmpty) {
          _fallbackToBrowser();
          return;
        }
        setState(() { _blocks = blocks; _loading = false; });
        widget.onExtractionSucceeded?.call();
      } catch (_) {
        if (_cancelled || !mounted) return;
        _fallbackToBrowser();
      }
    }, label: 'Extracting article');
  }

  /// Pop this screen, show a brief notice, and open the article in the browser.
  void _fallbackToBrowser() {
    if (!mounted) return;
    widget.onExtractionFailed?.call();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.extractionFailed)),
    );
    Navigator.pop(context);
    _launchBrowser();
  }

  Future<void> _launchBrowser() async {
    final uri = Uri.tryParse(widget.article.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.article.feedTitle ?? '',
          style: theme.textTheme.labelLarge,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded),
            tooltip: l10n.readOnWebsite,
            onPressed: _launchBrowser,
          ),
        ],
      ),
      body: _buildBody(l10n, theme),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ThemeData theme) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.loadingArticle),
          ],
        ),
      );
    }

    // If blocks is still null here the fallback already fired; show nothing.
    if (_blocks == null) return const SizedBox.shrink();

    final rt = readingTime(widget.article.description);
    final meta = [
      formatRelativeTimestamp(widget.article.publishedAt, AppLocalizations.of(context)!),
      if (rt.isNotEmpty) rt,
    ].where((s) => s.isNotEmpty).join(' · ');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.article.title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              height: 1.3,
              fontSize: _fs + 4,
            ),
          ),
          const SizedBox(height: 8),
          if (meta.isNotEmpty)
            Text(
              meta,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 20),
          ..._blocks!.map(_buildBlock),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _launchBrowser,
              icon: const Icon(Icons.open_in_browser_rounded),
              label: Text(AppLocalizations.of(context)!.readOnWebsite),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlock(ContentBlock block) {
    final theme = Theme.of(context);

    if (block is HeadingBlock) {
      final isLarge = block.level <= 2;
      return Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          block.text,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isLarge ? _fs + 6 : _fs + 3,
            color: theme.colorScheme.onSurface,
            height: 1.3,
          ),
        ),
      );
    }

    if (block is ParagraphBlock) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SelectableText(
          block.text,
          style: TextStyle(fontSize: _fs, height: 1.7),
        ),
      );
    }

    if (block is QuoteBlock) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: theme.colorScheme.primary,
                width: 4,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            block.text,
            style: TextStyle(
              fontSize: _fs,
              fontStyle: FontStyle.italic,
              height: 1.6,
            ),
          ),
        ),
      );
    }

    if (block is ListBlock) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: block.items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final prefix = block.ordered ? '${i + 1}. ' : '• ';
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$prefix$item',
                style: TextStyle(fontSize: _fs, height: 1.6),
              ),
            );
          }).toList(),
        ),
      );
    }

    if (block is ImageBlock) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: block.src,
                fit: BoxFit.cover,
                width: double.infinity,
                maxHeightDiskCache: 300,
                placeholder: (_, __) => Container(
                  height: 200,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            if (block.caption != null && block.caption!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  block.caption!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
