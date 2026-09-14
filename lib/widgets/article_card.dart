import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../utils/date_utils.dart';
import '../theme/app_theme.dart';
import '../utils/form_factor.dart';
import '../screens/article_summary_sheet.dart';
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
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

const List<double> _kIdentityMatrix = <double>[
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

/// The AI-summary button's two colours, fixed rather than theme-derived.
///
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
/// The unread mark, and the 12dp it holds open whether or not it paints.
///
/// **The reserved width is the feature; the dot is the decoration.** A 5dp
/// circle with 7dp of air after it leads the meta line, and on read the circle
/// fades to transparent while the box stays exactly where it was.
///
/// Releasing the space instead would shift the favicon, the source and the
/// timestamp left the instant mark-read-on-scroll fired — under the thumb of
/// someone who is mid-scroll and did not touch anything. That is the same
/// failure this project already refused once when a read title dropped to
/// w400 and reflowed a wrapped headline; this is the same bug wearing a
/// different mechanism, a box going away rather than a glyph getting narrower.
///
/// So the [SizedBox] is unconditional and only the colour animates.
/// `unread_dot_geometry_test.dart` measures the row at rest in both states and
/// again at the halfway point of the fade, because a slot that collapses when
/// the animation ends looks perfect to a before/after comparison.
class _UnreadDot extends StatelessWidget {
  final bool isRead;

  const _UnreadDot({required this.isRead});

  static const double diameter = 5;

  /// Between the dot and the favicon.
  static const double gap = 7;

  /// What the row gives up for this, read or unread.
  static const double reservedWidth = diameter + gap;

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.secondary;

    return SizedBox(
      key: const ValueKey('unread_dot_slot'),
      width: reservedWidth,
      height: diameter,
      child: Align(
        alignment: Alignment.centerLeft,
        child: TweenAnimationBuilder<double>(
          // begin == null, so a row that is already read when it scrolls into
          // view renders with no dot on its first frame rather than fading one
          // out in front of the reader.
          tween: Tween<double>(end: isRead ? 0.0 : 1.0),
          duration: kReadDimDuration,
          curve: Curves.easeOut,
          builder: (context, t, _) => Container(
            key: const ValueKey('unread_dot'),
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Lerped to transparent rather than wrapped in an Opacity: one
              // fewer layer for a 5dp circle, and it keeps `secondary` exactly
              // at rest instead of approximately.
              color: Color.lerp(Colors.transparent, secondary, t),
            ),
          ),
        ),
      ),
    );
  }
}

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
      // Symmetric again. The right inset was zero while the summary button
      // sat at the card's edge and supplied its own margin from inside its
      // touch box; the thumbnail is the rightmost element once more, so the
      // normal 16dp screen inset applies on both sides.
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10, bottom: 10),
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
                    _UnreadDot(isRead: isRead),
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
                          // Two named levels, not two alphas. Reading an
                          // article drops the source one step down the ink
                          // scale rather than thinning the same colour.
                          color: isRead
                              ? theme.flashColors.onSurfaceMuted
                              : theme.colorScheme.onSurfaceVariant,
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
                      // kNumeralTimestampStyle: 12.5px JetBrains Mono with
                      // tabular figures, declared in pass 1 and wired to
                      // nothing until now.
                      //
                      // Tabular is the reason, not the look. A proportional
                      // "1" is narrower than a "4", so a relative timestamp
                      // ticking from "1h ago" to "4h ago" would change width
                      // and pull the meta line with it — the same reflow the
                      // reserved dot slot exists to prevent, arriving on a
                      // timer instead of on a gesture.
                      style: (theme.textTheme.labelSmall ?? const TextStyle())
                          .merge(kNumeralTimestampStyle)
                          .copyWith(
                            // One value, read or unread. The timestamp already
                            // sits at the floor of the ink scale, so there is no
                            // quieter level to move it to — and a third of the
                            // row changing on read, when the title and source
                            // already do, was more motion than the state change
                            // is worth.
                            color: theme.flashColors.onSurfaceMuted,
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
                    // Constant by design, and Quiet Ink does not change
                    // that.
                    //
                    // This used to drop to w400 when read. Lighter glyphs are
                    // narrower, so a title sitting near a wrap boundary
                    // reflowed from three lines to two the moment
                    // mark-read-on-scroll fired: the card lost a line of
                    // height and every card below it slid up under the user's
                    // eyes, mid-scroll, with no gesture to explain it.
                    //
                    // The Quiet Ink spec asks for w300 on read titles, which
                    // is a *larger* step than the w400 that caused that bug,
                    // against the app's central invariant that the list never
                    // moves under the reader. So the weight stays put and the
                    // lighter reading comes from the colour, which is what
                    // the spec's other half asks for anyway.
                    fontWeight: FontWeight.w600,
                    // A named role now, not ink at 45%. Alpha over a white
                    // surface and alpha over a near-black one are different
                    // greys, and neither was the one the palette specifies.
                    color: isRead
                        ? theme.flashColors.onSurfaceRead
                        : theme.colorScheme.onSurface,
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
          // 6, down from 12: the summary button needs the room and the
          // tightening is wanted rather than tolerated.
          const SizedBox(width: 6),
          _ActionRail(article: article, onBookmark: onBookmark),
          const SizedBox(width: 2),
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
        // secondaryContainer, not primary: these badges appear on every
        // alert-matched card across Flash, Bookmarks and Alerts, and the
        // accent hue is the right role for a chip specifically — the same
        // way this app already reaches for a container role rather than a
        // bare colour for badge-shaped things.
        color: theme.colorScheme.secondaryContainer,
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
            color: theme.colorScheme.onSecondaryContainer,
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

  const _FaviconWidget(
      {required this.faviconPath,
      required this.feedTitle,
      this.dimmed = false});

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

  const _ThumbnailWidget(
      {required this.article, required this.feedTitle, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Local cache first — no existsSync(), Image.file handles missing files via errorBuilder
    if (article.thumbnailPath != null) {
      return _thumb(
          theme,
          Image.file(
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
            // The floor of the ink scale, not an illustration: this is a
            // letter standing in for a picture, and it is still read as text.
            color: theme.flashColors.onSurfaceMuted,
          ),
        ),
      ),
    );
  }
}

/// The card's right-edge action rail: AI summary on top, save underneath.
///
/// Summary used to be a button in the long-press radial menu, which meant
/// every summary cost a long-press, a wait for the menu to spread, and a
/// second tap. It is the one action on a card people take repeatedly, so it
/// got a target of its own; the radial menu keeps the ones you reach for
/// occasionally. Save now shares that target, in the same footprint.
///
/// Save is still in the radial menu too, and that is deliberate rather than
/// duplication left to tidy up: long-press has to keep working because swipe
/// can be turned off, and the comment above `tappable` explains why.
///
/// **Geometry.** 28dp of visible button inside a 40dp touch box, 72dp tall to
/// match the thumbnail exactly, with the thumbnail's 8dp corner radius on the
/// rail's outer corners. The 6dp of invisible padding each side is what takes
/// the touch box from 28 to 40.
///
/// The rail is not at the card's edge: the row runs text, 6dp, rail, 2dp,
/// thumbnail, inside a symmetric 16dp card inset. (An earlier version of this
/// comment said the card's right inset was zero and that the rail supplied
/// the margin from inside its own touch box. That stopped being true when the
/// thumbnail became the rightmost element again, and the note on the padding
/// in `build` already records the change.)
///
/// **What the split cost, stated plainly.** This box used to hold one button,
/// and the justification here used to be that 40x72 is 2880dp² against a 48dp
/// square's 2304dp², so it was a *larger* thing to hit, just a differently
/// shaped one.
///
/// That argument does not survive the split and is not worth restating in a
/// weaker form. The rail now holds two controls of 40x36. Each is 1440dp²,
/// which is 62% of the 48dp square this app holds itself to, and it is under
/// the minimum on both axes rather than on one. Comparing 980dp² — the
/// painted 28x35 — against the old 2880dp² would flatter it, but those are
/// not the same measurement: 2880 was the touch area, and the touch area is
/// what a thumb meets.
///
/// The second cost is the larger one. A mis-tap on the old button did
/// nothing, because there was nothing else in the box to hit. A mis-tap now
/// performs the other action: reaching for a summary and saving the article
/// instead is a visible, annoying wrong outcome that has to be noticed and
/// undone.
///
/// Both costs were on the table and the split was chosen anyway, for a second
/// one-tap action on the most-used surface in the app. That is a product
/// decision, not a geometric one, and it is written here so the next person
/// to read this file gets the real numbers rather than a rounded-off defence
/// of them. `action_rail_test.dart` pins both heights so nothing shaves them
/// further by accident.
///
/// **Every available dp is in a touch box.** The two boxes are 36dp each and
/// share an edge at the rail's midpoint; no gap is laid out between them. The
/// 2dp visual slot is painted, by aligning each half's 35dp block to the
/// outer end of its own box. A laid-out gap would have put dead pixels
/// exactly where a thumb aiming at the boundary between two small targets is
/// most likely to land.
///
/// **The splash stays on the painted 28dp** rather than filling the touch
/// box, independently for each half: an ink ripple spreading into empty card
/// margin reads as a misdrawn button.
///
/// **Colour.** The summary half is the teal tint, `primaryContainer` under
/// `onPrimaryContainer`.
///
/// This was two fixed hexes for a while, and the reason is worth keeping
/// because it no longer applies. The button used to take `secondary` under
/// `onSecondary`, which meant it pulled whichever accent the active palette
/// had generated — in this position, on every card, that read as garish. The
/// fix was to leave the theme entirely: a pale cyan fill with a navy glyph,
/// fixed together because a fixed *light* fill cannot be paired with a role
/// that resolves light in dark mode.
///
/// Quiet Ink removes the premise. There is one interactive colour and the
/// container roles are authored rather than derived, so `primaryContainer`
/// is both predictable and already the tint every other chip-shaped thing in
/// the app uses — and unlike the fixed pair, it resolves correctly in dark
/// mode instead of staying stubbornly light.
///
/// The save half is the same tint when the article is not saved, with a
/// neutral `onSurfaceVariant` glyph so the two halves read as one control
/// with two jobs. Saved, it fills with `secondary` under `onSecondary`.
///
/// **That last pair is a live design question, not a settled one.** Two rules
/// are written into `app_theme.dart`: teal is the only interactive colour,
/// and orange means unread and nothing else. A pressable orange breaks both.
/// It is here because design 2a asks for it by name, and the reasoning given
/// is that "a saved article is scannable down the column without adding a
/// colour to the row's default state" — but that reasoning describes a feed
/// with unread dots in it, and this card has none. `secondary` currently has
/// two consumers in the whole app, both the swipe-reveal background, and
/// `onSecondary` has none at all. So this button is the first thing to paint
/// that pair, and in light mode it is 4.12:1, under the 4.5:1 the summary
/// glyph is held to. `summary_button_contrast_test.dart` records the exact
/// shortfall rather than lowering the bar to fit it.
///
/// Pinned in that file against the roles it actually paints, so a later edit
/// to either cannot quietly break a pair.
class _ActionRail extends StatelessWidget {
  final Article article;
  final VoidCallback onBookmark;

  const _ActionRail({required this.article, required this.onBookmark});

  /// Visible width. The touch box is [_touchWidth].
  static const double _visibleWidth = 28;
  static const double _touchWidth = 40;
  static const double _height = 72;

  /// The two touch heights. Equal, and summing to [_height] exactly so the
  /// boxes meet rather than leaving anything untappable between them.
  static const double summaryTouchHeight = 36;
  static const double saveTouchHeight = 36;

  /// Painted height per half. The 1dp each block leaves inside its own touch
  /// box is what opens the 2dp slot between the two.
  static const double _paintedHeight = 35;

  static const Radius _corner = Radius.circular(8);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = theme.flashColors;
    final saved = article.isSaved;

    void open() => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => ArticleSummarySheet(article: article),
        );

    // Deliberately not wrapped in _DimTransition, unlike the thumbnail and
    // the favicon beside it. Reading an article does not make summarising or
    // saving it any less available, and a control that fades with the content
    // it acts on reads as disabled — the one impression this rail must not
    // give.
    return SizedBox(
      width: _touchWidth,
      height: _height,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RailHalf(
            tooltip: l10n.summary,
            touchHeight: summaryTouchHeight,
            // Top of its own box, so the slot opens downwards.
            align: Alignment.topCenter,
            radius: const BorderRadius.vertical(top: _corner),
            fill: scheme.primaryContainer,
            glyph: scheme.onPrimaryContainer,
            icon: Icons.auto_awesome_rounded,
            onTap: open,
          ),
          _RailHalf(
            // The radial menu's own strings, for the radial menu's own
            // action. A card offering a different word for bookmarking than
            // the menu that bookmarks the same article is a bug in waiting.
            tooltip: saved ? l10n.saved : l10n.bookmark,
            touchHeight: saveTouchHeight,
            align: Alignment.bottomCenter,
            radius: const BorderRadius.vertical(bottom: _corner),
            fill: saved ? ink.savedFill : scheme.primaryContainer,
            glyph: saved ? ink.onSavedFill : scheme.onSurfaceVariant,
            icon:
                saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            onTap: onBookmark,
          ),
        ],
      ),
    );
  }
}

/// One half of the rail: a touch box with a painted block aligned to one end.
///
/// The fill and glyph cross-fade over [kReadDimDuration] rather than snapping.
/// That tempo is not chosen here — it is the one the card already uses for
/// read-state dimming, on the thumbnail, favicon and title beside this rail,
/// so a save lands at the same speed as everything else that changes on the
/// card. The icon itself swaps immediately: the outline-to-filled change is
/// the primary signal and cross-fading two different glyphs through each
/// other reads as a rendering fault rather than a transition.
class _RailHalf extends StatelessWidget {
  final String tooltip;
  final double touchHeight;
  final Alignment align;
  final BorderRadius radius;
  final Color fill;
  final Color glyph;
  final IconData icon;
  final VoidCallback onTap;

  const _RailHalf({
    required this.tooltip,
    required this.touchHeight,
    required this.align,
    required this.radius,
    required this.fill,
    required this.glyph,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      // The outer box is the target; the InkWell inside only covers the
      // painted 28dp. Opaque so the invisible margins belong to this half and
      // not to the card's own InkWell underneath — without it those strips
      // would open the article, which is the one thing a user aiming here is
      // not asking for. A tap on the visible part is claimed by the child, so
      // the two never both fire.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: _ActionRail._touchWidth,
          height: touchHeight,
          child: Align(
            alignment: align,
            // The Tooltip above already labels this half, and the InkWell and
            // Icon below were each contributing a second label of their own --
            // an accessibility dump showed two identically labelled,
            // separately focusable nodes per button, one 40dp wide and one
            // 28dp. The InkWell stays for its ripple and the Icon for the
            // glyph; neither needs to be reachable in its own right, so the
            // whole painted layer is excluded and the outer touch box is the
            // single node that remains.
            child: ExcludeSemantics(
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: fill),
                duration: kReadDimDuration,
                builder: (context, animatedFill, child) => Material(
                  color: animatedFill,
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  child: child,
                ),
                child: InkWell(
                  onTap: onTap,
                  child: SizedBox(
                    width: _ActionRail._visibleWidth,
                    height: _ActionRail._paintedHeight,
                    child: TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: glyph),
                      duration: kReadDimDuration,
                      builder: (context, animatedGlyph, _) =>
                          Icon(icon, size: 18, color: animatedGlyph),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
