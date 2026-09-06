// The app's one loading indicator: how it behaves, and where it sits.
//
// Both placements were reported from the device rather than found in a test:
// the refresh button replaced its own icon with the app's bolt for the
// duration of a refresh, and the global bolt was pinned to the top *centre*
// of the whole screen stack — which on a phone is directly under the camera
// cut-out.
//
// The rotating bolt is gone entirely now, so the assertions worth keeping
// from its own deleted suite live here: that it turns, that it turns at a
// *constant* rate (the bolt's whole character was the opposite — a flick and
// a drift — so this is the assertion that has changed sign, not merely moved
// house), that an explicit size is honoured, and that its ticker is released.
//
// Nothing here uses pumpAndSettle: SpinningRefreshIcon drives a `..repeat()`
// controller, so nothing ever settles.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/widgets/global_loading_indicator.dart';
import 'package:flash/widgets/spinning_refresh_icon.dart';

/// A phone-shaped surface with a status-bar/cut-out inset, which is the whole
/// point of the placement being tested.
const Size _phone = Size(360, 800);
const double _topInset = 44;

void main() {
  group('the refresh button while refreshing', () {
    testWidgets('keeps its own circular arrow rather than the bolt',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: SpinningRefreshIcon())),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget,
          reason: 'the glyph the user pressed is the glyph that responds');
      expect(find.byIcon(Icons.bolt_outlined), findsNothing,
          reason: 'swapping in the app bolt made a different control appear '
              'under the finger');
    });

    testWidgets('turns clockwise', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: SpinningRefreshIcon())),
      ));
      await tester.pump();

      // Scoped: MaterialApp's own scaffolding contributes RotationTransitions
      // of its own, so a bare byType finder matches more than one.
      final rotation = find.descendant(
        of: find.byType(SpinningRefreshIcon),
        matching: find.byType(RotationTransition),
      );
      double turns() =>
          tester.widget<RotationTransition>(rotation).turns.value;

      final start = turns();
      await tester.pump(const Duration(milliseconds: 200));
      final later = turns();

      expect(later, greaterThan(start),
          reason: 'turns increasing is clockwise; a decreasing value would '
              'spin the arrowhead backwards against the direction it points');
    });

    testWidgets('inherits its size from the surrounding IconTheme',
        (tester) async {
      // So the spinning and resting states are the same size without either
      // naming a number.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: IconTheme(
            data: IconThemeData(size: 33),
            child: Center(child: SpinningRefreshIcon()),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.widget<Icon>(find.byType(Icon)).size, isNull,
          reason: 'a hardcoded size here would diverge from the resting icon');
      expect(tester.getSize(find.byType(Icon)).width, 33);
    });

    testWidgets('leaves its colour to the FAB when none is given',
        (tester) async {
      // The refresh button is the one call site that passes no colour, so the
      // FAB's own foreground applies. An override here would be invisible in
      // the default palette and wrong in every other one.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: SpinningRefreshIcon())),
      ));
      await tester.pump();

      expect(tester.widget<Icon>(find.byType(Icon)).color, isNull);
    });
  });

  group('the glyph itself', () {
    Future<void> pump(WidgetTester tester,
        {double? size, Color? color}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: SpinningRefreshIcon(size: size, color: color)),
        ),
      ));
      await tester.pump();
    }

    double turns(WidgetTester tester) => tester
        .widget<RotationTransition>(find.descendant(
          of: find.byType(SpinningRefreshIcon),
          matching: find.byType(RotationTransition),
        ))
        .turns
        .value;

    testWidgets('renders at the size it was given', (tester) async {
      // The former bolt sites pass explicit sizes from 16 to 40, so this is
      // no longer only an IconTheme story.
      await pump(tester, size: 40);
      expect(tester.getSize(find.byType(Icon)).width, 40);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('paints the colour it was given', (tester) async {
      await pump(tester, size: 28, color: const Color(0xFF00695C));
      expect(tester.widget<Icon>(find.byType(Icon)).color,
          const Color(0xFF00695C));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('turns at a constant rate, not in flicks', (tester) async {
      // Inherited, inverted, from the deleted bolt suite, which asserted the
      // fastest slice outran the slowest by 2x. A control the user pressed
      // that speeds up and slows down reads as the app stuttering.
      await pump(tester, size: 24);

      // Six 100ms slices inside the 900ms period, so no sample crosses the
      // loop boundary — a wrap would show up as one huge negative delta and
      // say nothing about the easing.
      const slice = Duration(milliseconds: 100);
      var previous = turns(tester);
      final deltas = <double>[];
      for (var i = 0; i < 6; i++) {
        await tester.pump(slice);
        final now = turns(tester);
        deltas.add(now - previous);
        previous = now;
      }

      expect(deltas.every((d) => d > 0), isTrue,
          reason: 'turns increasing is clockwise, the way the arrowhead '
              'already points');

      final fastest = deltas.reduce((a, b) => a > b ? a : b);
      final slowest = deltas.reduce((a, b) => a < b ? a : b);
      expect(fastest, lessThan(slowest * 1.2),
          reason: 'every equal slice of time should cover an equal part of '
              'the turn; the bolt this replaced varied by more than 2x');

      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('disposes its controller without leaking a ticker',
        (tester) async {
      await pump(tester, size: 24);
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      expect(tester.takeException(), isNull);
    });
  });

  group('the global loading indicator', () {
    Future<void> pumpOverlay(WidgetTester tester) async {
      tester.view.physicalSize = _phone;
      tester.view.devicePixelRatio = 1.0;
      tester.view.viewPadding = const FakeViewPadding(top: _topInset * 1.0);
      tester.view.padding = const FakeViewPadding(top: _topInset * 1.0);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: GlobalLoadingIndicator(),
              ),
            ],
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('sits on the right, not under the centre cut-out',
        (tester) async {
      await pumpOverlay(tester);

      final rect = tester.getRect(find.descendant(
        of: find.byType(GlobalLoadingIndicator),
        matching: find.byType(RotationTransition),
      ));
      final screenCentreX = _phone.width / 2;

      expect(rect.left, greaterThan(screenCentreX),
          reason: 'centred put it directly beneath the punch-hole camera, '
              'which is the entire reason this moved');
      expect(rect.right, lessThanOrEqualTo(_phone.width),
          reason: 'and not pushed off the edge');
    });

    testWidgets('clears the app-bar action icons', (tester) async {
      await pumpOverlay(tester);

      final rect = tester.getRect(find.descendant(
        of: find.byType(GlobalLoadingIndicator),
        matching: find.byType(RotationTransition),
      ));
      // The feed screen puts two IconButtons here. Anything overlapping them
      // would draw the bolt on top of a control the user can press.
      const actionsWidth = 2 * 48.0;
      expect(rect.right, lessThanOrEqualTo(_phone.width - actionsWidth),
          reason: 'the bolt must not overlap quick settings or filter');
    });

    testWidgets('is vertically inside the toolbar row, below the inset',
        (tester) async {
      await pumpOverlay(tester);

      final rect = tester.getRect(find.descendant(
        of: find.byType(GlobalLoadingIndicator),
        matching: find.byType(RotationTransition),
      ));
      expect(rect.top, greaterThanOrEqualTo(_topInset),
          reason: 'above this is the status bar and the cut-out');
      expect(rect.bottom, lessThanOrEqualTo(_topInset + kToolbarHeight),
          reason: 'and it should read as part of the app bar, not float below '
              'it over the first article');
    });
  });
}
