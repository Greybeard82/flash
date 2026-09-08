import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/content_block.dart';

/// Renders extracted [ContentBlock]s as a plain, styled reading view — the
/// clean-mode counterpart to the raw page in the WebView.
///
/// Every style comes from the theme rather than a literal. The app ships five
/// colour palettes plus newspaper mode, so a hardcoded colour or font size here
/// would be wrong in most of them.
///
/// There is no font-size setting to key off: the old PRD had one, but it is not
/// in the live settings model, and inventing a second typography scale for one
/// screen is not the way to reintroduce it.
class CleanArticleView extends StatelessWidget {
  final List<ContentBlock> blocks;

  const CleanArticleView({super.key, required this.blocks});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectionArea(
      child: Center(
        // The tablet pane is wide enough to produce a 100-character measure,
        // which is precisely the thing a reading view exists to avoid.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView.builder(
            key: const ValueKey('cleanArticleView'),
            // The bottom inset clears the floating toggle, so the last
            // paragraph is not permanently parked under it.
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            itemCount: blocks.length,
            itemBuilder: (context, i) => KeyedSubtree(
              key: ValueKey('cleanBlock_$i'),
              child: _buildBlock(theme, blocks[i]),
            ),
          ),
        ),
      ),
    );
  }

  /// Exhaustive over the sealed [ContentBlock]; no `default:` on purpose, so a
  /// sixth block type becomes a compile error here rather than a silently
  /// dropped paragraph. Same reasoning as `SummarySource.fromBlocks`.
  Widget _buildBlock(ThemeData theme, ContentBlock block) {
    switch (block) {
      case HeadingBlock():
        final style = switch (block.level) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          _ => theme.textTheme.titleMedium,
        };
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(block.text,
              style: style?.copyWith(fontWeight: FontWeight.w700)),
        );

      case ParagraphBlock():
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            block.text,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        );

      case QuoteBlock():
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.only(left: 14),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 3),
            ),
          ),
          child: Text(
            block.text,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        );

      case ListBlock():
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < block.items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          block.ordered ? '${i + 1}.' : '•',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          block.items[i],
                          style:
                              theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

      case ImageBlock():
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: block.src,
                  fit: BoxFit.fitWidth,
                  // The list thumbnail has often already fetched this exact
                  // file, so going through the shared cache rather than
                  // Image.network makes this a hit rather than a download.
                  placeholder: (_, __) => const SizedBox.shrink(),
                  // A dead image leaves no hole rather than a broken-image box.
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              if (block.caption != null && block.caption!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    block.caption!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
    }
  }
}
