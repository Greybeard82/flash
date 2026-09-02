/// Scroll position remembered as *an article*, not as a pixel offset.
///
/// A pixel offset is only meaningful against the exact list that produced it.
/// By the time it is restored the list has usually changed: read articles have
/// been filtered out, retirement has removed rows, a fetch has inserted new
/// ones above, and rows that had not laid out their thumbnails were shorter
/// than they will be. Restoring the number lands somewhere else in the
/// content, and everything it lands past looks, to the mark-as-read walk, like
/// something the user scrolled through.
///
/// Anchoring to an article id survives all of that: whatever the list did, the
/// article the user was looking at is either still there or it is not.
///
/// Pure Dart — no Flutter import at all.
class ScrollAnchor {
  /// The topmost fully-visible article when the snapshot was taken.
  final int articleId;

  /// The next articles below it, in order, used when [articleId] itself did
  /// not survive. Two or three is enough: if that many consecutive articles
  /// all vanished, the list has changed so much that the top is the honest
  /// answer.
  final List<int> fallbackIds;

  /// Distance from that row's top edge to the viewport top.
  ///
  /// Only meaningful for the anchor article itself — see [ScrollTarget.exact].
  final double pixelsIntoItem;

  const ScrollAnchor({
    required this.articleId,
    required this.fallbackIds,
    required this.pixelsIntoItem,
  });
}

/// Where to scroll to, resolved against the list as it exists now.
class ScrollTarget {
  /// Index into the *article id* list handed to [ScrollAnchorResolver.resolve].
  final int index;

  /// Pixels to scroll past that row's top edge. Zero unless [exact].
  final double pixelsIntoItem;

  /// True when the anchor article itself was found.
  ///
  /// When false the anchor is gone and this is a fallback, so the remembered
  /// intra-item offset belongs to a different article and carrying it over
  /// would land the list at an arbitrary point inside an unrelated row.
  final bool exact;

  const ScrollTarget({
    required this.index,
    required this.pixelsIntoItem,
    required this.exact,
  });

  /// The top of the list — the answer when nothing in the chain survived.
  static const ScrollTarget top =
      ScrollTarget(index: 0, pixelsIntoItem: 0.0, exact: false);
}

abstract final class ScrollAnchorResolver {
  /// Resolves [anchor] against [articleIds], the current list in display
  /// order.
  ///
  /// Tries the anchor first, then each fallback in order. Falling back always
  /// lands the row flush at the viewport top: an inexact match never carries
  /// [ScrollAnchor.pixelsIntoItem].
  static ScrollTarget resolve(ScrollAnchor anchor, List<int> articleIds) {
    if (articleIds.isEmpty) return ScrollTarget.top;

    final exactIndex = articleIds.indexOf(anchor.articleId);
    if (exactIndex >= 0) {
      return ScrollTarget(
        index: exactIndex,
        pixelsIntoItem: anchor.pixelsIntoItem,
        exact: true,
      );
    }

    for (final id in anchor.fallbackIds) {
      final i = articleIds.indexOf(id);
      if (i >= 0) {
        return ScrollTarget(index: i, pixelsIntoItem: 0.0, exact: false);
      }
    }

    return ScrollTarget.top;
  }
}
