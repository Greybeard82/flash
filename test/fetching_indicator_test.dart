// The background-fetch indicator that replaced the full-screen boot pulse.
//
// The glyph is specified as bilaterally symmetric — the app's own bolt logo is
// an asymmetric zigzag, and an asymmetric shape wobbles visibly when rotated.
// The painter authors only the right half and mirrors it, so symmetry is a
// property of the construction rather than of carefully-typed coordinates;
// these tests hold it to that.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/fetching_indicator.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: flashDarkTheme(),
    home: const Scaffold(
      body: Center(child: FetchingIndicator(size: 24)),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('renders at the requested size', (tester) async {
    await _pump(tester);
    expect(
      tester.getSize(find.descendant(
        of: find.byType(FetchingIndicator),
        matching: find.byType(CustomPaint),
      ).first).width,
      24,
    );
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

  // Symmetry is checked on the geometry, synchronously. Rasterising and
  // comparing pixels would be the obvious alternative, but picture.toImage()
  // never resolves inside flutter_test's FakeAsync zone — the same reason
  // this repo keeps real sqflite I/O out of testWidgets (see
  // feed_repository_test.dart). Path.contains needs no event loop.
  group('the glyph is bilaterally symmetric', () {
    test('the authored half touches the mirror axis only at its two apexes',
        () {
      final onAxis = kBoltRightHalf.where((p) => p.dx == 0).toList();
      expect(onAxis.length, 2,
          reason: 'the shared points are the top and bottom apexes; any other '
              'point on the axis would be emitted twice when mirrored');
      expect(onAxis.first, kBoltRightHalf.first);
      expect(onAxis.last, kBoltRightHalf.last);
      expect(kBoltRightHalf.every((p) => p.dx >= 0), isTrue,
          reason: 'only the right half is authored');
    });

    test('the built path contains a point iff it contains its mirror', () {
      const size = Size(240, 240);
      final path = buildSymmetricBoltPath(size);

      var insideSamples = 0;
      for (var y = 1.0; y < size.height; y += 2) {
        for (var x = 0.0; x < size.width / 2; x += 2) {
          final mirroredX = size.width - x;
          final left = path.contains(Offset(x, y));
          final right = path.contains(Offset(mirroredX, y));
          expect(left, right,
              reason: 'asymmetry at y=$y: x=$x is '
                  '${left ? "inside" : "outside"} but its mirror '
                  'x=$mirroredX is ${right ? "inside" : "outside"}');
          if (left) insideSamples++;
        }
      }

      expect(insideSamples, greaterThan(50),
          reason: 'sanity: the path must enclose a real area, otherwise the '
              'symmetry check above passes vacuously');
    });

    test('the bounds are centred on the vertical axis', () {
      const size = Size(240, 240);
      final bounds = buildSymmetricBoltPath(size).getBounds();

      expect(bounds.center.dx, closeTo(size.width / 2, 0.01));
      expect(size.width - bounds.right, closeTo(bounds.left, 0.01));
    });

    test('symmetry holds at a non-square size too', () {
      const size = Size(64, 128);
      final path = buildSymmetricBoltPath(size);

      for (var y = 1.0; y < size.height; y += 3) {
        for (var x = 0.0; x < size.width / 2; x += 1) {
          expect(path.contains(Offset(x, y)),
              path.contains(Offset(size.width - x, y)),
              reason: 'asymmetry at ($x, $y) when not square');
        }
      }
    });
  });
}
