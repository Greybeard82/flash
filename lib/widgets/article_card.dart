import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/article.dart';
import '../utils/date_utils.dart';
import 'radial_menu.dart';

class ArticleCard extends StatelessWidget {
  final Article article;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onShare;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRead = article.isRead;

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
        color: Colors.orange.withValues(alpha: 0.15),
        icon: Icons.mark_email_unread_rounded,
        iconColor: Colors.orange,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onMarkRead();
        } else {
          onMarkUnread();
        }
        return false; // Don't remove from list
      },
      child: GestureDetector(
        onLongPress: () {
          showRadialMenu(context: context, onShare: onShare);
        },
        child: InkWell(
          onTap: onTap,
          child: Opacity(
            opacity: isRead ? 0.55 : 1.0,
            child: Padding(
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
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                article.feedTitle ?? '',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatRelativeTimestamp(article.publishedAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.45),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Title
                        Text(
                          article.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                isRead ? FontWeight.w400 : FontWeight.w600,
                            color: theme.colorScheme.onSurface,
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
                  ),
                ],
              ),
            ),
          ),
        ),
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

  const _FaviconWidget({required this.faviconPath, required this.feedTitle});

  @override
  Widget build(BuildContext context) {
    if (faviconPath != null) {
      final file = File(faviconPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(file, width: 14, height: 14, fit: BoxFit.cover),
        );
      }
    }
    final letter = feedTitle.isNotEmpty ? feedTitle[0].toUpperCase() : '?';
    return Container(
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
  }
}

class _ThumbnailWidget extends StatelessWidget {
  final Article article;
  final String feedTitle;

  const _ThumbnailWidget({required this.article, required this.feedTitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Local cache first
    if (article.thumbnailPath != null) {
      final file = File(article.thumbnailPath!);
      if (file.existsSync()) {
        return _thumb(Image.file(file, fit: BoxFit.cover));
      }
    }

    // Remote URL
    if (article.thumbnailUrl != null && article.thumbnailUrl!.isNotEmpty) {
      return _thumb(
        CachedNetworkImage(
          imageUrl: article.thumbnailUrl!,
          fit: BoxFit.cover,
          placeholder: (_, __) => const SizedBox.shrink(),
          errorWidget: (_, __, ___) => _placeholder(theme),
        ),
      );
    }

    return _placeholder(theme);
  }

  Widget _thumb(Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 72, height: 72, child: child),
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
