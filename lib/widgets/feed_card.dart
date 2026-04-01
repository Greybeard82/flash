import 'dart:io';
import 'package:flutter/material.dart';
import '../models/feed.dart';

class FeedCard extends StatelessWidget {
  final Feed feed;
  final int unreadCount;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const FeedCard({
    super.key,
    required this.feed,
    this.unreadCount = 0,
    this.onTap,
    this.onDelete,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: _FeedAvatar(feed: feed),
      title: Text(
        feed.title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        feed.domain,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!feed.isHealthy)
            Icon(Icons.warning_amber_rounded,
                size: 18, color: theme.colorScheme.error),
          if (unreadCount > 0) ...[
            const SizedBox(width: 6),
            Text(
              unreadCount > 999 ? '999+' : '$unreadCount',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.more_vert),
            iconSize: 20,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _FeedAvatar extends StatelessWidget {
  final Feed feed;

  const _FeedAvatar({required this.feed});

  @override
  Widget build(BuildContext context) {
    if (feed.faviconPath != null) {
      final file = File(feed.faviconPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
          ),
        );
      }
    }

    // Monogram fallback
    final letter =
        feed.title.isNotEmpty ? feed.title[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 18,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        letter,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}
