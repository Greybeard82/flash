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

  const RetirementPlan(this.rowIndices, this.articleIds, this.removedHeight);

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
  return RetirementPlan(indices, ids, height);
}
