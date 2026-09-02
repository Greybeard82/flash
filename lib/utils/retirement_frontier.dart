/// Decides which rows have scrolled far enough above the viewport to retire.
///
/// Extracted rather than inlined because it is arithmetic that must be exactly
/// right — an off-by-one retires an article the user can still see, and an
/// error in [RetirementPlan.removedHeight] moves the list under them. Both are
/// invisible in a widget test and obvious on a device.
class RetirementPlan {
  /// Row indices to remove, ascending. Includes day headers left with no
  /// articles beneath them.
  final List<int> rowIndices;

  /// Article ids to retire in the database.
  final List<int> articleIds;

  /// Exact pixel height of everything in [rowIndices]. The scroll offset must
  /// be reduced by precisely this much in the same turn as the removal.
  final double removedHeight;

  /// True when the built-row ceiling, not the buffer, is what stopped the
  /// frontier.
  ///
  /// The buffer should already keep the frontier well clear of anything the
  /// ListView still has built. If this is ever true the buffer arithmetic is
  /// wrong somewhere upstream and the clamp is carrying it — worth knowing
  /// before it becomes a bug report.
  final bool clampedByBuiltRows;

  const RetirementPlan(
    this.rowIndices,
    this.articleIds,
    this.removedHeight, {
    this.clampedByBuiltRows = false,
  });

  bool get isEmpty => rowIndices.isEmpty;

  static const RetirementPlan empty = RetirementPlan([], [], 0);
}

/// One row's contribution to the plan.
class RowMetric {
  /// Null for a day header.
  final int? articleId;

  /// True when this row is a saved article — exempt from retirement, and so
  /// exempt from removal.
  final bool isSaved;

  /// Whether this row is currently built by the ListView.
  ///
  /// A built row may be visible, or within cacheExtent of visible. A disposed
  /// row is neither. Retirement is confined to disposed rows, so no arithmetic
  /// error anywhere else in this file can delete something on screen.
  final bool isBuilt;

  /// Whether [height] is a real measurement or a fallback guess.
  ///
  /// The offset correction is exactly the sum of the removed rows' heights, so
  /// a guessed height moves the list by the size of the guess. Pass 10
  /// measured real cards at 96.8dp and 121.9dp against a hardcoded 120, so the
  /// guess is wrong in both directions and the error accumulates down the
  /// list. A row that could not be measured therefore cancels the cycle
  /// instead of being estimated.
  final bool measured;

  final double height;

  const RowMetric({
    required this.height,
    this.articleId,
    this.isSaved = false,
    this.isBuilt = false,
    this.measured = true,
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
  bool scrollActive = false,
}) {
  // Quiescence. Retirement corrects the scroll offset in the same turn as the
  // removal, and a correction applied while a gesture is live either fights
  // the ballistic simulation or yanks the list out from under the finger.
  //
  // This is not a theoretical guard. Pass 10 logged five consecutive
  // retirements during sustained scrolling, every one of them with
  // scrollActive=true, each pulling the offset back between 240px and 861px:
  //
  //   [RETIRE] ids=7 removedExtent=861.0 offsetBefore=1417.0 offsetAfter=556.0
  //
  // That is the reported "list jumps upward" bug, in full. Being called from
  // ScrollEndNotification was not sufficient: with continuous scrolling the
  // *next* gesture has already started by the time this runs.
  if (scrollActive) return RetirementPlan.empty;
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

  // Hard ceiling: never touch a row the ListView still has built. This is a
  // safety net, not the primary mechanism — the buffer above should already
  // keep the frontier well clear. If this clamp is ever what stops a removal,
  // something upstream is wrong and the caller should be told.
  var clampedByBuiltRows = false;
  var firstBuilt = rows.length;
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].isBuilt) {
      firstBuilt = i;
      break;
    }
  }
  if (frontier >= firstBuilt) {
    clampedByBuiltRows = true;
    frontier = firstBuilt - 1;
  }
  if (frontier < 0) return RetirementPlan.empty;

  // Everything from 0..frontier is a candidate, but a saved article truncates
  // the block: nothing at or above it may be removed.
  for (var i = 0; i <= frontier; i++) {
    if (rows[i].isSaved) return RetirementPlan.empty;
  }

  // Every row being removed must have a real measured extent, because
  // removedHeight *is* the scroll correction. One guessed row and the list
  // moves by the error. Skipping a cycle costs nothing — the rows are still
  // there and the next settled scroll retires them.
  for (var i = 0; i <= frontier; i++) {
    if (!rows[i].measured) return RetirementPlan.empty;
  }

  final indices = <int>[];
  final ids = <int>[];
  var height = 0.0;
  for (var i = 0; i <= frontier; i++) {
    indices.add(i);
    height += rows[i].height;
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
  // top row, and removedHeight excludes it, so the offset correction still
  // lands on the pixel. Indices stop being contiguous, which the caller
  // already handles — it removes by set membership, not by range.
  if (frontier + 1 < rows.length && !rows[frontier + 1].isHeader) {
    for (var i = frontier; i >= 0; i--) {
      if (rows[i].isHeader) {
        indices.remove(i);
        height -= rows[i].height;
        break;
      }
    }
  }

  if (ids.isEmpty) return RetirementPlan.empty;
  return RetirementPlan(indices, ids, height,
      clampedByBuiltRows: clampedByBuiltRows);
}
