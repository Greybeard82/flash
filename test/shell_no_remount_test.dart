// Swapping sides moves the columns. It must never rebuild them.
//
// The regression this pins is the obvious way to write the feature and the
// wrong one. Reordering a Row's children to put the bar on the right hands
// every column a new position in the child list, and Flutter matches elements
// to children by position — so the article list would be offered the reading
// pane's element, both would be thrown away, and tapping Swap sides would
// silently reload the feed, scroll it to the top and close whatever article
// was open. None of that looks like a bug while you are writing it; it looks
// like the layout working.
//
// So both shell tiers lay their children out by position instead of by order:
// a CustomMultiChildLayout whose children list never changes, and a delegate
// that decides where each one goes. This test reads the source rather than
// driving a widget because what it is asserting is a property of the code —
// the child order is a constant — and a rendered frame cannot tell you that a
// list is constant, only what it happens to hold this time.
//
// If this fails, do not reorder the list to match. Move the position, not the
// child.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String source;

  setUpAll(() {
    source = File('lib/app.dart').readAsStringSync();
  });

  test('both tiers lay out by position, not by order', () {
    expect(RegExp(r'CustomMultiChildLayout\(').allMatches(source), hasLength(2),
        reason: 'the three-column tier and the rail tier each have one. A '
            'Row here is the bug in the header comment.');
  });

  test('the children are in a fixed order, and it is this one', () {
    final ids = RegExp(r'id: _Shell\.(\w+)')
        .allMatches(source)
        .map((m) => m.group(1))
        .toList();

    expect(ids, [
      // Three-column: content first so it paints below, the bar last so it
      // slides over the columns while they cross rather than behind them.
      'content', 'divider', 'detail', 'rule', 'bar',
      // Rail: the same order, minus the two pieces that tier does not have.
      'content', 'rule', 'bar',
    ],
        reason: 'the slot each child occupies is what carries its state. '
            'Reordering this list is exactly the remount being guarded '
            'against, even when the rendered layout looks identical.');
  });

  test('no slot is chosen by which side the bar is on', () {
    // A `_Shell.x` behind a conditional would reintroduce the same bug with
    // extra steps: the child list would be constant in length and still hand
    // a different element to a different column.
    final conditional =
        RegExp(r'id: [^,\n]*(?:\?|swapped)').allMatches(source);
    expect(conditional, isEmpty,
        reason: 'every LayoutId takes a literal slot: '
            '${conditional.map((m) => m.group(0)).toList()}');
  });

  test('the swap is animated by relayout, not by rebuilding', () {
    // `relayout:` is what lets the animation re-run layout without rebuilding
    // a single widget. Driving it from an AnimatedBuilder around the children
    // would work and would also rebuild them 13 times per swap.
    expect(RegExp(r'super\(relayout: swapProgress\)').allMatches(source),
        hasLength(2),
        reason: 'both delegates take the animation as their relayout signal');
  });
}
