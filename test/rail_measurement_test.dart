// The navigation rail is measured, not told how wide to be.
//
// This exists because of a bug that reached a device. The shell lays its
// columns out with a layout delegate rather than a Row, and the rail is the
// one piece whose width nobody chooses — it is as wide as its widest label,
// and this app puts the section actions ("Mark all as read") in its trailing
// slot, so it is not the 80dp a bare rail would be. The delegate therefore has
// to measure it.
//
// The first version measured it with a *loose* constraint, `0..displayWidth`,
// on the reasoning that loose is the safer sibling of unbounded and identical
// wherever the content is narrower than the display. That reasoning is wrong
// for this widget. NavigationRail aligns its destinations with an [Align], and
// an Align with no size factor fills its constraints whenever they are
// bounded. Given a bounded width it does not shrink-wrap — it takes all of it.
//
// On an 8" tablet in portrait, 600dp wide, that put the rail across the whole
// display and left the content column zero width: four labels centred on an
// empty screen, and no article list at all. A Row never showed it, because a
// Row hands its non-flexible children an infinite main-axis constraint.
//
// So the constraint is unbounded, and this is the test that says so with a
// real rail rather than by reading the source.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/app.dart';

/// The narrowest thing this bug could hide behind: at 600dp the rail tier is
/// only just in use, so a rail that swallows the width swallows all of it.
const double _railTierWidth = 600;
const double _displayHeight = 960;

/// Lays one child out exactly the way the shell measures the bar.
class _MeasureBar extends MultiChildLayoutDelegate {
  _MeasureBar(this.onMeasured);

  final void Function(Size) onMeasured;

  @override
  void performLayout(Size size) {
    final bar = layoutChild('bar', barMeasurementConstraints(size.height));
    onMeasured(bar);
    positionChild('bar', Offset.zero);
  }

  @override
  bool shouldRelayout(_MeasureBar old) => false;
}

Widget _rail() => NavigationRail(
      selectedIndex: 0,
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
            icon: Icon(Icons.bolt), label: Text('Flash')),
        NavigationRailDestination(
            icon: Icon(Icons.rss_feed), label: Text('Categories')),
        NavigationRailDestination(
            icon: Icon(Icons.bookmark), label: Text('Bookmarks')),
        NavigationRailDestination(
            icon: Icon(Icons.notifications), label: Text('Alerts')),
      ],
    );

void main() {
  testWidgets('a rail measured the shell way keeps to its own width',
      (tester) async {
    late Size measured;

    tester.view.physicalSize = const Size(_railTierWidth, _displayHeight);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomMultiChildLayout(
          delegate: _MeasureBar((s) => measured = s),
          children: [LayoutId(id: 'bar', child: _rail())],
        ),
      ),
    ));

    expect(measured.height, _displayHeight,
        reason: 'the bar always fills the height it is given');
    expect(measured.width, lessThan(_railTierWidth / 2),
        reason: 'the rail took ${measured.width}dp of a ${_railTierWidth}dp '
            'display. That is the bug: a bounded width makes NavigationRail '
            'fill it, and the content column is left with what remains.');
  });

  test('the measuring constraint leaves the width open', () {
    final c = barMeasurementConstraints(_displayHeight);
    expect(c.maxWidth, double.infinity,
        reason: 'bounded is what made the rail fill the display');
    expect(c.minHeight, _displayHeight);
    expect(c.maxHeight, _displayHeight,
        reason: 'the bar runs the full height, as it did inside the Row');
  });
}
