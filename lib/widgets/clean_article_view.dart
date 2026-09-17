import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/content_block.dart';
import '../theme/app_theme.dart';

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

  /// The reading face, at the measure this surface is tuned for.
  ///
  /// **The family comes from `titleLarge`, and that is deliberate rather than
  /// convenient.** Both themes put their reading serif there — Literata in
  /// Quiet Ink, PT Serif in Newspaper — while `bodyLarge` is the *operating*
  /// face in Quiet Ink and happens to be the serif in Newspaper. Hardcoding
  /// `kSerifFamily` would put Literata into Newspaper, which has its own type
  /// system and did not ask for ours.
  ///
  /// Size and line height come from the theme file. They apply in both themes:
  /// the clean view is one widget with one job, and giving it two different
  /// reading measures would be the odd choice, not the consistent one. The
  /// pre-existing code applied its `height: 1.5` to both for the same reason.
  static TextStyle _reading(ThemeData theme) =>
      (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontFamily: theme.textTheme.titleLarge?.fontFamily,
        fontSize: kCleanBodySize,
        height: kCleanBodyHeight,
      );

  /// Exhaustive over the sealed [ContentBlock]; no `default:` on purpose, so a
  /// sixth block type becomes a compile error here rather than a silently
  /// dropped paragraph. Same reasoning as `SummarySource.fromBlocks`.
  Widget _buildBlock(ThemeData theme, ContentBlock block) {
    final reading = _reading(theme);

    switch (block) {
      case HeadingBlock():
        // h1 and h2 were already the serif — `headlineSmall` and `titleLarge`
        // are both serif entries in Quiet Ink — so only h3 moves. It was
        // `titleMedium`, which is the *operating* face: a sans subhead inside
        // a serif article, at a weight that made it look deliberate.
        //
        // h3 lands at the body size rather than above it. A third-level
        // heading inside a web article is usually a paragraph label, and
        // w700 at the reading size separates it without starting a new
        // hierarchy under the two that already exist.
        final style = switch (block.level) {
          1 => theme.textTheme.headlineSmall,
          2 => theme.textTheme.titleLarge,
          _ => reading,
        };
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(block.text,
              style: style?.copyWith(fontWeight: FontWeight.w700)),
        );

      case ParagraphBlock():
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(block.text, style: reading),
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
            style: reading.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
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
                          // The marker takes the reading face too: a sans
                          // bullet beside a serif line is the kind of seam
                          // nobody names but everybody sees.
                          style: reading,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          block.items[i],
                          style: reading,
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
