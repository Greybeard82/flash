import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../utils/date_utils.dart';
import '../utils/form_factor.dart';
import '../utils/reading_time.dart';
import 'radial_menu.dart';

class ArticleCard extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;
  final VoidCallback? onMarkUnread;
  final VoidCallback onShare;
  final VoidCallback onBookmark;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    required this.onMarkRead,
    this.onMarkUnread,
    required this.onShare,
    required this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRead = article.isRead;
    final isTV = FormFactor.isTV;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source + timestamp row
                Row(
                  children: [
                    _FaviconWidget(
                      faviconPath: article.feedFaviconPath,
                      feedTitle: article.feedTitle ?? '',
                      dimmed: isRead,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        article.feedTitle ?? '',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: isRead ? 0.33 : 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatRelativeTimestamp(article.publishedAt, AppLocalizations.of(context)!),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: isRead ? 0.25 : 0.45),
                      ),
                    ),
                    Builder(builder: (context) {
                      final rt = readingTime(article.description);
                      if (rt.isEmpty) return const SizedBox.shrink();
                      return Row(children: [
                        const SizedBox(width: 6),
                        Text('· $rt',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: isRead ? 0.2 : 0.38),
                            )),
                      ]);
                    }),
                  ],
                ),
                const SizedBox(height: 6),
                // Title
                Text(
                  article.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: isRead ? 0.45 : 1.0),
                    height: 1.35,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Thumbnail
          _ThumbnailWidget(
            article: article,
            feedTitle: article.feedTitle ?? '',
            dimmed: isRead,
          ),
        ],
      ),
    );

    // On TV: no touchscreen, so skip Dismissible swipe and long-press radial menu.
    // D-pad OK fires onTap; share/bookmark are reachable inside the preview sheet.
    if (isTV) {
      return InkWell(onTap: onTap, child: content);
    }

    return Dismissible(
      key: ValueKey('article_${article.id}'),
      background: _swipeBackground(
        context,
        alignment: Alignment.centerLeft,
        color: theme.colorScheme.primary.withValues(alpha: 0.15),
        icon: Icons.mark_email_read_rounded,
        iconColor: theme.colorScheme.primary,
      ),
      secondaryBackground: _swipeBackground(
        context,
        alignment: Alignment.centerRight,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        icon: Icons.mark_email_unread_rounded,
        iconColor: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onMarkRead();
        } else {
          onMarkUnread?.call();
        }
        return false;
      },
      child: GestureDetector(
        onLongPress: () => showRadialMenu(
          context: context,
          onShare: onShare,
          onBookmark: onBookmark,
          article: article,
        ),
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }

  Widget _swipeBackground(
    BuildContext context, {
    required AlignmentGeometry alignment,
    required Color color,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(icon, color: iconColor, size: 28),
    );
  }
}

class _FaviconWidget extends StatelessWidget {
  final String? faviconPath;
  final String feedTitle;
  final bool dimmed;

  const _FaviconWidget({required this.faviconPath, required this.feedTitle, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final letter = feedTitle.isNotEmpty ? feedTitle[0].toUpperCase() : '?';
    final placeholder = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700),
        ),
      ),
    );

    final widget = faviconPath == null
        ? placeholder
        : ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              File(faviconPath!),
              width: 14,
              height: 14,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            ),
          );

    if (!dimmed) return widget;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.saturation),
      child: Opacity(opacity: 0.4, child: widget),
    );
  }
}

class _ThumbnailWidget extends StatelessWidget {
  final Article article;
  final String feedTitle;
  final bool dimmed;

  const _ThumbnailWidget({required this.article, required this.feedTitle, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Local cache first — no existsSync(), Image.file handles missing files via errorBuilder
    if (article.thumbnailPath != null) {
      return _thumb(Image.file(
        File(article.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(theme),
      ));
    }

    // Remote URL
    if (article.thumbnailUrl != null && article.thumbnailUrl!.isNotEmpty) {
      return _thumb(
        CachedNetworkImage(
          imageUrl: article.thumbnailUrl!,
          fit: BoxFit.cover,
          memCacheWidth: 144,
          maxWidthDiskCache: 144,
          placeholder: (_, __) => ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (_, __, ___) => _placeholder(theme),
        ),
      );
    }

    return _placeholder(theme);
  }

  Widget _thumb(Widget child) {
    Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 72, height: 72, child: child),
    );
    if (!dimmed) return clipped;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.saturation),
      child: Opacity(opacity: 0.4, child: clipped),
    );
  }

  Widget _placeholder(ThemeData theme) {
    final letter = feedTitle.isNotEmpty ? feedTitle[0].toUpperCase() : '?';
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }
}
