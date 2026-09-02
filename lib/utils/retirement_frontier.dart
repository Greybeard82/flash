/// Decides which rows have scrolled far enough above the viewport to retire.
///
/// Extracted rather than inlined because it is arithmetic that must be exactly
/// right: an off-by-one queues an article the user can still see, and that
/// article is gone at the next flush. Invisible in a widget test, obvious on a
/// device.
///
/// The plan is now an *enqueue* list, not a delete list. Nothing here moves
/// the list or touches the scroll offset, so the plan can be computed at any
/// time — including during an active scroll.
class RetirementPlan {
  /// Row indices to remove, ascending. Includes day headers left with no
  /// articles beneath them.
  final List<int> rowIndices;

  /// Article ids to retire in the database.
  final List<int> articleIds;

  const RetirementPlan(this.rowIndices, this.articleIds);

  bool get isEmpty => rowIndices.isEmpty;

  static const RetirementPlan empty = RetirementPlan([], []);
}

/// One row's contribution to the plan.
class RowMetric {
  /// Null for a day header.
  final int? articleId;

  /// True when this row is a saved article — exempt from retirement, and so
  /// exempt from removal.
  final bool isSaved;

  /// Used only to locate the frontier — how far down the list the viewport
  /// top has reached. Nothing is corrected by it any more, so an imperfect
  /// height shifts which row is queued by one, and never moves the list.
  final double height;

  const RowMetric({
    required this.height,
    this.articleId,
    this.isSaved = false,
  });

  bool get isHeader => articleId == null;
}

/// Builds the plan for a list sitting at [scrollOffset].
///
/// An article is eligible when [bufferCards] other article rows sit entirely
/// between its bottom edge and the top of the viewport. Rows are walked from
/// the top, accumulating height, so "above the viewport" means cumulative
/// bottom edge <= scrollOffset.
///
/// **The built-row ceiling below is the operative safety rule**, not
/// [bufferCards]. A row `ListView` still has built may be visible; a disposed
/// one cannot be. With the feed's `cacheExtent: 500` and ~110dp cards, about
/// 4.5 rows above the viewport stay built, so the ceiling stops the frontier
/// before a 2-card buffer would. The buffer is the floor for the cases where
/// that is not true — a smaller `cacheExtent`, taller cards, a large text
/// scale — and the effective distance is the larger of the two.
///
/// This couples retirement distance to a rendering knob, which is worth
/// knowing before tuning `cacheExtent` for scroll smoothness.
///
/// A saved article is never eligible and, crucially, **blocks everything above
/// it from being removed too**. Removing rows either side of a row that stays
/// would leave the survivor in the wrong place, and the arithmetic that keeps
/// the list still assumes one contiguous block at the top.
///
/// A day header is included only when every article beneath it is being
/// removed and it is inside the contiguous block.
RetirementPlan planRetirement({
  required List<RowMetric> rows,
  required double scrollOffset,
  int bufferCards = 2,
}) {
  if (rows.isEmpty || scrollOffset <= 0) return RetirementPlan.empty;

  // Walk down accumulating height; find the last row whose bottom edge is at
  // or above the viewport top. A row straddling the top edge stops the walk,
  // so a partially visible row is never a candidate.
  var cumulative = 0.0;
  var lastAboveViewport = -1;
  for (var i = 0; i < rows.length; i++) {
    final bottom = cumulative + rows[i].height;
    if (bottom <= scrollOffset) {
      lastAboveViewport = i;
      cumulative = bottom;
    } else {
      break;
    }
  }
  if (lastAboveViewport < 0) return RetirementPlan.empty;

  // Step back past the buffer, counting article rows only — headers are not
  // articles and must not consume the buffer.
  var frontier = lastAboveViewport;
  var buffered = 0;
  while (frontier >= 0 && buffered < bufferCards) {
    if (!rows[frontier].isHeader) buffered++;
    frontier--;
  }
  if (frontier < 0) return RetirementPlan.empty;

  // Everything from 0..frontier is a candidate, but a saved article truncates
  // the block: nothing at or above it may be removed.
  for (var i = 0; i <= frontier; i++) {
    if (rows[i].isSaved) return RetirementPlan.empty;
  }

  final indices = <int>[];
  final ids = <int>[];
  for (var i = 0; i <= frontier; i++) {
    indices.add(i);
    final id = rows[i].articleId;
    if (id != null) ids.add(id);
  }

  // If the block ends mid-day, the surviving articles still need their header.
  //
  // The old check only caught a header sitting exactly at the frontier. A
  // frontier landing *inside* a group removed that group's header while its
  // later articles survived, leaving the top of the list with no date label.
  //
  // Dropping the header out of the block is safe: it simply becomes the new
  // top row. Indices stop being contiguous, which the caller already handles —
  // it removes by set membership, not by range.
  if (frontier + 1 < rows.length && !rows[frontier + 1].isHeader) {
    for (var i = frontier; i >= 0; i--) {
      if (rows[i].isHeader) {
        indices.remove(i);
        break;
      }
    }
  }

  if (ids.isEmpty) return RetirementPlan.empty;
  return RetirementPlan(indices, ids);
}
