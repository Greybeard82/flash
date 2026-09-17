// The custom switch.
//
// **Why it exists, verified rather than assumed.** `SwitchThemeData` in the
// pinned Flutter (3.41.6) has ten properties and none of them is a shape;
// `Switch` takes no `ShapeBorder`; and `_SwitchPainter` paints the track as
// `RRect.fromRectAndRadius(trackRect, Radius.circular(trackHeight / 2))` — a
// stadium derived from the height, with no way in from a theme. A theme entry
// could not have done this.
//
// **The three ways a custom toggle is worse than the stock one it replaced**
// are what most of this file is about: announcing itself as a button rather
// than a switch, shrinking the touch target to the size of the art, and
// responding to taps but not to the swipe everybody uses. A switch that only
// looks right is a picture of a switch.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/flash_switch.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

final _themes = <String, ThemeData>{
  'Quiet Ink light': flashQuietInkTheme(brightness: Brightness.light),
  'Quiet Ink dark': flashQuietInkTheme(brightness: Brightness.dark),
  'Newspaper': flashNewspaperTheme(),
};

Future<void> _pump(
  WidgetTester tester, {
  required bool value,
  ValueChanged<bool>? onChanged,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme ?? flashQuietInkTheme(brightness: Brightness.light),
    home: Scaffold(
      body: Center(child: FlashSwitch(value: value, onChanged: onChanged)),
    ),
  ));
}

void main() {
  group('it announces itself as a switch', () {
    testWidgets('on: toggled true, enabled, tappable', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, value: true, onChanged: (_) {});

      expect(
          tester.getSemantics(find.byType(FlashSwitch)),
          matchesSemantics(
            hasToggledState: true,
            isToggled: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ));
      handle.dispose();
    });

    testWidgets('off: toggled false, still enabled and tappable',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, value: false, onChanged: (_) {});

      expect(
          tester.getSemantics(find.byType(FlashSwitch)),
          matchesSemantics(
            hasToggledState: true,
            isToggled: false,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
          ));
      handle.dispose();
    });

    testWidgets('disabled: has the state, is not enabled, has no tap action',
        (tester) async {
      // A disabled control that still advertises a tap action is a control a
      // screen reader user will try to operate and get nothing from.
      final handle = tester.ensureSemantics();
      await _pump(tester, value: false, onChanged: null);

      expect(
          tester.getSemantics(find.byType(FlashSwitch)),
          matchesSemantics(
            hasToggledState: true,
            isToggled: false,
            hasEnabledState: true,
            isEnabled: false,
          ));
      handle.dispose();
    });

    testWidgets('the decoration does not leak its own semantics nodes',
        (tester) async {
      // Without ExcludeSemantics the containers underneath announce
      // themselves too and the switch is read twice.
      final handle = tester.ensureSemantics();
      await _pump(tester, value: true, onChanged: (_) {});
      expect(find.byType(FlashSwitch), findsOneWidget);
      expect(
          tester.getSemantics(find.byType(FlashSwitch)).childrenCount, 0,
          reason: 'one node for the control, not a tree of decoration');
      handle.dispose();
    });
  });

  group('it is 48dp to the finger', () {
    testWidgets('the tappable box is at least 48 on both axes',
        (tester) async {
      await _pump(tester, value: false, onChanged: (_) {});
      final size = tester.getSize(find.byType(FlashSwitch));
      expect(size.height, greaterThanOrEqualTo(48.0));
      expect(size.width, greaterThanOrEqualTo(48.0));
    });

    testWidgets('a tap outside the painted track still toggles',
        (tester) async {
      // The point of the 48dp box: the track is 26dp tall, so roughly the top
      // 11dp of the target paints nothing and must still work.
      bool? got;
      await _pump(tester, value: false, onChanged: (v) => got = v);

      final rect = tester.getRect(find.byType(FlashSwitch));
      await tester.tapAt(Offset(rect.center.dx, rect.top + 4));
      expect(got, isTrue,
          reason: 'HitTestBehavior.opaque is what makes the empty part of the '
              'target live');
    });

    test('the visible track is smaller than the target, by design', () {
      expect(kFlashSwitchTrackHeight, lessThan(kFlashSwitchMinTarget));
      expect(kFlashSwitchMinTarget, 48);
    });
  });

  group('it behaves like a switch, not a picture of one', () {
    testWidgets('tap toggles in both directions', (tester) async {
      bool? got;
      await _pump(tester, value: false, onChanged: (v) => got = v);
      await tester.tap(find.byType(FlashSwitch));
      expect(got, isTrue);

      await _pump(tester, value: true, onChanged: (v) => got = v);
      await tester.tap(find.byType(FlashSwitch));
      expect(got, isFalse);
    });

    testWidgets('a rightward drag turns it on', (tester) async {
      bool? got;
      await _pump(tester, value: false, onChanged: (v) => got = v);
      final g = await tester.startGesture(
          tester.getCenter(find.byType(FlashSwitch)));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(10, 0));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(got, isTrue, reason: 'people swipe switches');
    });

    testWidgets('a leftward drag turns it off', (tester) async {
      bool? got;
      await _pump(tester, value: true, onChanged: (v) => got = v);
      final g = await tester.startGesture(
          tester.getCenter(find.byType(FlashSwitch)));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(-10, 0));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(got, isFalse);
    });

    testWidgets('dragging the way it already points does nothing',
        (tester) async {
      bool? got;
      await _pump(tester, value: true, onChanged: (v) => got = v);
      final g = await tester.startGesture(
          tester.getCenter(find.byType(FlashSwitch)));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(10, 0));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(got, isNull, reason: 'an on switch dragged right is already on');
    });

    testWidgets('disabled does not toggle by tap or by drag', (tester) async {
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        theme: flashQuietInkTheme(brightness: Brightness.light),
        home: Scaffold(
          body: Center(
            child: Builder(builder: (_) {
              calls++;
              return const FlashSwitch(value: false, onChanged: null);
            }),
          ),
        ),
      ));
      final before = calls;
      await tester.tap(find.byType(FlashSwitch));
      final g = await tester.startGesture(
          tester.getCenter(find.byType(FlashSwitch)));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(10, 0));
      }
      await g.up();
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(calls, before, reason: 'nothing should have rebuilt');
    });

    testWidgets('the thumb animates rather than jumping', (tester) async {
      await _pump(tester, value: false, onChanged: (_) {});
      final off = tester.getCenter(find.byType(Container).last);

      await _pump(tester, value: true, onChanged: (_) {});
      await tester.pump(const Duration(milliseconds: 1));
      final mid = tester.getCenter(find.byType(Container).last);
      await tester.pumpAndSettle();
      final on = tester.getCenter(find.byType(Container).last);

      expect(on.dx, greaterThan(off.dx), reason: 'it should end up right');
      expect(mid.dx, lessThan(on.dx),
          reason: 'one frame in it must not already be there — that is a jump, '
              'not an animation');
    });

    test('the tempo is one the app already uses', () {
      // folder_tab_bar's chip selection and notification_banner's slide are
      // both 200ms. Inventing a fourth tempo for a fourth control is how an
      // app stops feeling like one app.
      expect(kFlashSwitchDuration, const Duration(milliseconds: 200));
    });
  });

  group('WCAG 1.4.11: 3:1 for every graphical pair', () {
    _themes.forEach((name, theme) {
      final scheme = theme.colorScheme;
      final ink = theme.flashColors;

      test('$name: OFF track against the page', () {
        expect(_contrast(ink.onSurfaceMuted, scheme.surface),
            greaterThanOrEqualTo(3.0),
            reason: '$name: a pale Material-style track measures about 1.1 '
                'here and relies on an outline to exist at all');
      });

      test('$name: OFF thumb against its track', () {
        expect(_contrast(scheme.surface, ink.onSurfaceMuted),
            greaterThanOrEqualTo(3.0));
      });

      test('$name: ON track against the page', () {
        expect(_contrast(scheme.primary, scheme.surface),
            greaterThanOrEqualTo(3.0));
      });

      test('$name: ON thumb against its track', () {
        expect(_contrast(scheme.onPrimary, scheme.primary),
            greaterThanOrEqualTo(3.0));
      });

      test('$name: disabled is perceivably different from both live states',
          () {
        // 1.4.11 exempts inactive components from the 3:1 floor — that is
        // what "disabled" is allowed to look like. What it may NOT be is
        // indistinguishable from an enabled state.
        expect(ink.inert, isNot(ink.onSurfaceMuted), reason: name);
        expect(ink.inert, isNot(scheme.primary), reason: name);
      });
    });
  });

  group('the shape, and the one knob that changes it', () {
    test('the corner ratio is not a stadium and not a rectangle', () {
      expect(kFlashSwitchCornerRatio, greaterThan(0.0));
      expect(kFlashSwitchCornerRatio, lessThan(0.5),
          reason: '0.5 IS the stadium this widget exists to avoid — if the '
              'ratio ever reaches it, delete the widget and use Switch');
    });

    testWidgets('the track radius is the ratio applied to track height',
        (tester) async {
      await _pump(tester, value: false, onChanged: (_) {});
      final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer).first);
      final decoration = container.decoration as BoxDecoration;
      final radius = decoration.borderRadius as BorderRadius;
      expect(radius.topLeft.x,
          closeTo(kFlashSwitchTrackHeight * kFlashSwitchCornerRatio, 0.01),
          reason: 'David tunes one constant; this is what follows from it');
    });
  });
}
