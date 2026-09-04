// The background-fetch indicator that replaced the full-screen boot pulse.
//
// It used to be a hand-drawn, bilaterally-symmetric bolt (an asymmetric shape
// wobbles visibly when rotated). It is now the real Icons.bolt_outlined glyph
// — the same one the bottom nav's "Flash" tab uses — accepting the wobble in
// exchange for the two icons being literally the same shape.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/fetching_indicator.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: flashPaletteTheme(palette: 'orange', brightness: Brightness.dark),
    home: const Scaffold(
      body: Center(child: FetchingIndicator(size: 24)),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('renders at the requested size', (tester) async {
    await _pump(tester);
    // Icon, not CustomPaint, since the real bolt glyph replaced the
    // hand-drawn painter — assert the outward contract (the indicator
    // occupies the size it was given) rather than an internal render node.
    expect(tester.getSize(find.byType(FetchingIndicator)).width, 24);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('rotates continuously', (tester) async {
    await _pump(tester);

    double turnsNow() => tester
        .widget<RotationTransition>(find.descendant(
          of: find.byType(FetchingIndicator),
          matching: find.byType(RotationTransition),
        ))
        .turns
        .value;

    final samples = <double>[turnsNow()];
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 180));
      samples.add(turnsNow());
    }

    expect(samples.toSet().length, greaterThan(1),
        reason: 'the glyph must actually be turning');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('turns at a varying rate, not like a mechanical spinner',
      (tester) async {
    await _pump(tester);

    double turnsNow() => tester
        .widget<RotationTransition>(find.descendant(
          of: find.byType(FetchingIndicator),
          matching: find.byType(RotationTransition),
        ))
        .turns
        .value;

    // Sample equal time slices across one loop and compare how far it moved
    // in each. A constant-rate spinner would move the same amount every time.
    const slice = Duration(milliseconds: 100);
    var previous = turnsNow();
    final deltas = <double>[];
    for (var i = 0; i < 12; i++) {
      await tester.pump(slice);
      final now = turnsNow();
      deltas.add((now - previous).abs());
      previous = now;
    }

    final fastest = deltas.reduce((a, b) => a > b ? a : b);
    final slowest = deltas.reduce((a, b) => a < b ? a : b);
    expect(fastest, greaterThan(slowest * 2),
        reason: 'the point is a flicker of energy — the fastest segment '
            'should clearly outrun the slowest');

    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('disposes its controller without leaking a ticker',
      (tester) async {
    await _pump(tester);
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    expect(tester.takeException(), isNull);
  });
}
