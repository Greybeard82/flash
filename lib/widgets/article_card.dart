import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../utils/date_utils.dart';
import '../utils/form_factor.dart';
import '../utils/reading_time.dart';
import 'radial_menu.dart';

/// Pure per-pixel desaturation (Rec. 709 luma weights), used to grey out the
/// imagery of a read article.
///
/// Replaces `ColorFilter.mode(Colors.white, BlendMode.saturation)`, which was
/// the cause of the dark-mode scroll flicker: `saturation` is a non-separable
/// blend mode, so it mixes with the backdrop rather than acting on the child
/// alone. Wrapped around a partly-transparent Opacity layer with a
/// not-yet-decoded image inside, it resolved toward its hardcoded white source
/// and painted a flat light block — measured at #A6A6A6 against the dark
/// theme's #0D1B2A page while scrolling. On the light theme the same block was
/// invisible against white, which is why it went unnoticed. A matrix filter
/// has no backdrop term: an undecoded image stays transparent, and a decoded
/// one becomes true greyscale.
const ColorFilter kGreyscaleFilter = ColorFilter.matrix(kGreyscaleMatrix);

const List<double> kGreyscaleMatrix = <double>[
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0,      0,      0,      1, 0,
];

const List<double> _kIdentityMatrix = <double>[
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

/// How long a card takes to grey out once it's marked read.
const Duration kReadDimDuration = Duration(milliseconds: 180);

/// Opacity a read article's imagery settles at.
const double _kDimOpacity = 0.4;

/// Element-wise interpolation between full colour and [kGreyscaleMatrix].
///
/// Interpolating the matrix is what lets the transition animate without ever
/// swapping the image widget for a differently-filtered copy — see
/// [_DimTransition] for why that matters.
List<double> _lerpGreyscaleMatrix(double t) {
  if (t <= 0) return _kIdentityMatrix;
  if (t >= 1) return kGreyscaleMatrix;
  return <double>[
    for (var i = 0; i < kGreyscaleMatrix.length; i++)
      _kIdentityMatrix[i] + (kGreyscaleMatrix[i] - _kIdentityMatrix[i]) * t,
  ];
}

/// Fades imagery to greyscale-and-dimmed when an article becomes read.
///
/// The image is handed to [TweenAnimationBuilder] through `child:` and is
/// *never* rebuilt inside `builder:`. Flutter reuses that exact instance on
/// every animation frame, so the underlying `Image` element is never
/// unmounted and nothing redecodes mid-transition.
///
/// This matters more than it looks: commit 39bb6a6 fixed a bug where
/// thumbnails flashed a bright block while scrolling in dark mode, and the
/// fix depends on the image sitting on a stable, solid themed base with a
/// backdrop-independent `ColorFilter.matrix`. Animating by crossfading two
/// separately-filtered subtrees — a keyed AnimatedSwitcher, say — would force
/// exactly the redecode that produced that flash. The wrapper layers are also
/// kept in the tree at every value of `t`, including 0, so the image's
/// position in the element tree never changes as the animation starts or ends.
class _DimTransition extends StatelessWidget {
  final bool dimmed;
  final Widget child;

  const _DimTransition({required this.dimmed, required this.child});

  @override
  Widget build(BuildContext context) {
    final target = dimmed ? 1.0 : 0.0;
    return TweenAnimationBuilder<double>(
      // begin == end so a card that is already read when it scrolls into view
      // renders dimmed on its first frame instead of animating into it.
      tween: Tween<double>(begin: target, end: target),
      duration: kReadDimDuration,
      curve: Curves.easeOut,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: 1.0 - (1.0 - _kDimOpacity) * t,
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(_lerpGreyscaleMatrix(t)),
          child: child,
        ),
      ),
    );
  }
}

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
                      // Each Text below deliberately sets no style of its own:
                      // Text merges its style *over* the inherited default, so
                      // specifying one here would override the animated colour
                      // and the fade would never be visible.
                      child: AnimatedDefaultTextStyle(
                        duration: kReadDimDuration,
                        curve: Curves.easeOut,
                        style: (theme.textTheme.labelSmall ?? const TextStyle())
                            .copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: isRead ? 0.33 : 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        child: Text(article.feedTitle ?? ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedDefaultTextStyle(
                      duration: kReadDimDuration,
                      curve: Curves.easeOut,
                      style: (theme.textTheme.labelSmall ?? const TextStyle())
                          .copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: isRead ? 0.25 : 0.45),
                      ),
                      child: Text(
                        formatRelativeTimestamp(
                            article.publishedAt, AppLocalizations.of(context)!),
                      ),
                    ),
                    Builder(builder: (context) {
                      final rt = readingTime(article.description);
                      if (rt.isEmpty) return const SizedBox.shrink();
                      return Row(children: [
                        const SizedBox(width: 6),
                        AnimatedDefaultTextStyle(
                          duration: kReadDimDuration,
                          curve: Curves.easeOut,
                          style:
                              (theme.textTheme.labelSmall ?? const TextStyle())
                                  .copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: isRead ? 0.2 : 0.38),
                          ),
                          child: Text('· $rt'),
                        ),
                      ]);
                    }),
                  ],
                ),
                const SizedBox(height: 6),
                // Title
                AnimatedDefaultTextStyle(
                  duration: kReadDimDuration,
                  curve: Curves.easeOut,
                  style: (theme.textTheme.bodyMedium ?? const TextStyle())
                      .copyWith(
                    fontWeight: isRead ? FontWeight.w400 : FontWeight.w600,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: isRead ? 0.45 : 1.0),
                    height: 1.35,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 3,
                  child: Text(article.title),
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

    final swipeBg = _swipeBackground(
      context,
      alignment: Alignment.centerLeft,
      color: theme.colorScheme.primary.withValues(alpha: 0.15),
      icon: Icons.mark_email_read_rounded,
      iconColor: theme.colorScheme.primary,
    );
    return Dismissible(
      key: ValueKey('article_${article.id}'),
      background: swipeBg,
      secondaryBackground: swipeBg,
      // confirmDismiss always returns false — the card never leaves the list,
      // it just marks read and springs back. The stock 200ms snap-back is
      // longer than it needs to be for a gesture with no dismissal to wait on.
      movementDuration: const Duration(milliseconds: 150),
      confirmDismiss: (_) async {
        onMarkRead();
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

    return _DimTransition(dimmed: dimmed, child: widget);
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
      return _thumb(theme, Image.file(
        File(article.thumbnailPath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(theme),
      ));
    }

    // Remote URL
    if (article.thumbnailUrl != null && article.thumbnailUrl!.isNotEmpty) {
      return _thumb(
        theme,
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

  Widget _thumb(ThemeData theme, Widget child) {
    // A solid themed base under every thumbnail, so an image that hasn't
    // decoded yet reveals the surface colour rather than whatever happens to
    // be behind — Image.file paints nothing at all while decoding.
    Widget clipped = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 72,
        height: 72,
        child: ColoredBox(
          color: theme.colorScheme.surfaceContainerHighest,
          child: child,
        ),
      ),
    );
    // Opacity dims *toward the page*: darker on the dark theme, lighter on
    // the light one. Animated rather than cut, but the image inside `clipped`
    // is the same instance throughout — see _DimTransition.
    return _DimTransition(dimmed: dimmed, child: clipped);
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
