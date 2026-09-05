import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../utils/date_utils.dart';
import '../utils/form_factor.dart';
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
  final VoidCallback onMarkUnread;
  final VoidCallback onShare;
  final VoidCallback onBookmark;

  /// Whether horizontal swipes mark the article read/unread.
  ///
  /// Off in the main feed, where a horizontal drag now pages between category
  /// tabs and the two gestures would fight. Still on in Bookmarks, which has
  /// no tabs and where swipe is the main way to toggle read state.
  final bool enableSwipeActions;

  /// Alert keywords this article matched, badged under the title.
  ///
  /// Empty everywhere but the Alerts tab, and empty by default so no existing
  /// construction site changes shape. An article can carry several: matching
  /// used to stop at the first hit and file the article under that one
  /// keyword alone, which is exactly the misattribution these badges exist to
  /// make visible.
  final List<String> alertKeywords;

  /// Dismisses this card, offered as a fourth button in the long-press radial
  /// menu when non-null.
  ///
  /// Only the Alerts tab supplies one. An alert match has no article row
  /// behind it and survives every path that removes an article, so by-hand
  /// dismissal is the only way one ever leaves the list.
  final VoidCallback? onDelete;

  const ArticleCard({
    super.key,
    required this.article,
    required this.onTap,
    required this.onMarkRead,
    required this.onMarkUnread,
    required this.onShare,
    required this.onBookmark,
    this.enableSwipeActions = true,
    this.alertKeywords = const [],
    this.onDelete,
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
                  ],
                ),
                const SizedBox(height: 6),
                // Title
                AnimatedDefaultTextStyle(
                  duration: kReadDimDuration,
                  curve: Curves.easeOut,
                  style: (theme.textTheme.bodyMedium ?? const TextStyle())
                      .copyWith(
                    // Constant by design. This used to drop to w400 when
                    // read. Lighter glyphs are narrower, so a title sitting
                    // near a wrap boundary reflowed from three lines to two
                    // the moment mark-read-on-scroll fired: the card lost a
                    // line of height and every card below it slid up under
                    // the user's eyes, mid-scroll, with no gesture to explain
                    // it. Read state is now carried by colour and opacity
                    // alone — neither can change layout.
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: isRead ? 0.45 : 1.0),
                    height: 1.35,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 3,
                  child: Text(article.title),
                ),
                if (alertKeywords.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _AlertKeywordBadges(
                    keywords: alertKeywords,
                    dimmed: isRead,
                  ),
                ],
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

    // Long-press radial menu (share / bookmark) is independent of swipe, so
    // turning swipe off must not take bookmarking from the feed with it.
    final tappable = GestureDetector(
      onLongPress: () => showRadialMenu(
        context: context,
        onShare: onShare,
        onBookmark: onBookmark,
        article: article,
        onDelete: onDelete,
      ),
      child: InkWell(onTap: onTap, child: content),
    );
    if (!enableSwipeActions) return tappable;

    // Two gestures, two backgrounds. Flutter paints `background` behind a
    // startToEnd drag (finger moving left-to-right, revealing the left edge)
    // and `secondaryBackground` behind endToStart (right-to-left, revealing
    // the right edge). Right-to-left marks read; left-to-right marks unread.
    // Each icon sits on the edge its own gesture uncovers.
    final unreadBg = _swipeBackground(
      context,
      alignment: Alignment.centerLeft,
      color: theme.colorScheme.secondary.withValues(alpha: 0.15),
      icon: Icons.mark_email_unread_rounded,
      iconColor: theme.colorScheme.secondary,
    );
    final readBg = _swipeBackground(
      context,
      alignment: Alignment.centerRight,
      color: theme.colorScheme.primary.withValues(alpha: 0.15),
      icon: Icons.mark_email_read_rounded,
      iconColor: theme.colorScheme.primary,
    );
    return Dismissible(
      key: ValueKey('article_${article.id}'),
      background: unreadBg,
      secondaryBackground: readBg,
      // confirmDismiss always returns false — the card never leaves the list,
      // it just changes read state and springs back. The stock 200ms
      // snap-back is longer than it needs to be for a gesture with no
      // dismissal to wait on.
      movementDuration: const Duration(milliseconds: 150),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart) {
          onMarkRead();
        } else {
          onMarkUnread();
        }
        return false;
      },
      child: tappable,
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

/// The alert keywords an article matched, as a single row of small chips
/// under its title.
///
/// Everything here is pinned so the row's height cannot vary with content or
/// with read state. That is the same rule the title's constant fontWeight
/// obeys, and for the same reason: mark-read-on-scroll fires while the user is
/// still scrolling, so any card whose height depends on `isRead` drags every
/// card below it out from under their finger, with no gesture to explain the
/// jump. Colour and opacity may change when the article is read; height and
/// line count may not. Hence a fixed chip height, exactly one line, and a
/// [_DimTransition] — a filter and an opacity, both layout-neutral — rather
/// than swapping in smaller or fewer chips.
class _AlertKeywordBadges extends StatelessWidget {
  /// Chip height, fixed rather than derived from the text so a font with
  /// taller metrics cannot reflow the card.
  static const double _chipHeight = 20;

  /// Beyond three the row stops being scannable and starts being a wall, and
  /// on a narrow phone the fourth chip is what pushes the third to a single
  /// ellipsised glyph. The rest are summarised as "+N".
  static const int _maxChips = 3;

  /// Longer keywords are cut here rather than being allowed to eat the row.
  /// Truncation happens before layout so the chip that gets shortened is the
  /// long one, not whichever one happens to sit last.
  static const int _maxKeywordChars = 14;

  final List<String> keywords;
  final bool dimmed;

  const _AlertKeywordBadges({required this.keywords, required this.dimmed});

  static String _truncate(String keyword) => keyword.length <= _maxKeywordChars
      ? keyword
      : '${keyword.substring(0, _maxKeywordChars)}…';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    // Sorted, so which three survive the cut is a property of the keyword set
    // and not of the row order the query happened to return — the same card
    // must not show "zelda, mario" one refresh and "mario, zelda" the next.
    final sorted = [...keywords]..sort();
    final shown = sorted.take(_maxChips).toList();
    final overflow = sorted.length - shown.length;

    return _DimTransition(
      dimmed: dimmed,
      child: SizedBox(
        height: _chipHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              // Flexible, never a fixed width: a keyword long enough to
              // overrun the card has to shrink and ellipsise, and a hardcoded
              // chip width is exactly what a long word spills out of.
              Flexible(child: _chip(theme, _truncate(shown[i]))),
            ],
            // The overflow chip is short and known, so it keeps its full width
            // while the keyword chips give theirs up.
            if (overflow > 0) ...[
              const SizedBox(width: 4),
              _chip(theme, l10n.alertsMoreKeywords(overflow)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, String label) {
    return Container(
      height: _chipHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      // Center with widthFactor 1.0, not `alignment:` on the Container. A
      // Container's alignment installs a plain Align, which grows to the
      // largest size its constraints allow — and the constraints here are
      // loose from Flexible, so a single chip stretched the full width of the
      // card and read as a banner rather than a badge. widthFactor: 1.0 sizes
      // the width to the label while the height stays pinned to _chipHeight.
      child: Center(
        widthFactor: 1.0,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // Only bites when Flexible has squeezed the chip narrower than its
          // label; at natural width the chip already hugs the text.
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
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
