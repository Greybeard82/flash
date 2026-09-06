// Where the two loading indicators sit, and which glyph each one uses.
//
// Both of these were reported from the device rather than found in a test:
// the refresh button replaced its own icon with the app's bolt for the
// duration of a refresh, and the global bolt was pinned to the top *centre*
// of the whole screen stack — which on a phone is directly under the camera
// cut-out.
//
// Neither uses pumpAndSettle: FetchingIndicator and SpinningRefreshIcon both
// drive `..repeat()` controllers, so nothing ever settles.

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
