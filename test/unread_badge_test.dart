// UnreadBadge single-line rendering tests.
//
// Regression coverage for the badge wrapping onto two lines: the fixed-
// width slot from the earlier tab-bar jitter fix (UnreadBadge.maxWidth())
// was sized using an unscaled TextPainter measurement, while the actual
// rendered Text picked up the ambient system font-scale from MediaQuery —
// so on any device with text scaling above 1.0, the real digits were wider
// than the box they were measured against and wrapped mid-number.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/widgets/unread_badge.dart';

Widget _harness(Widget child, {double textScale = 1.0}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('single-line rendering', () {
    for (final count in [1, 31, 999, 1234]) {
      testWidgets('count $count renders on exactly one line', (tester) async {
        await tester.pumpWidget(_harness(UnreadBadge(count: count)));
        await tester.pump();

        final textWidget = tester.widget<Text>(find.byType(Text));
        expect(textWidget.maxLines, 1);
        expect(textWidget.softWrap, isFalse);

        // A wrapped badge is roughly 2x a single line's height. Compare
        // against a bare reference Text at the same style to catch a
        // regression even if maxLines/softWrap were ever removed.
        final badgeHeight = tester.getSize(find.byType(Text)).height;
        final reference = Text(
          count > 999 ? '999+' : count.toString(),
          textScaler: TextScaler.noScaling,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, height: 1.2),
        );
        await tester.pumpWidget(_harness(reference));
        final referenceHeight = tester.getSize(find.byType(Text)).height;

        expect(badgeHeight, closeTo(referenceHeight, 1.0),
            reason: 'count $count should be one line tall, not wrapped onto two');
      });
    }
  });

  group('fixed-width box fits the widest single-line count', () {
    testWidgets('999+ fits inside maxWidth() without wrapping', (tester) async {
      await tester.pumpWidget(_harness(
        SizedBox(
          width: UnreadBadge.maxWidth(small: true),
          child: const UnreadBadge(count: 1234, small: true),
        ),
      ));
      await tester.pump();

      final textWidget = tester.widget<Text>(find.byType(Text));
      expect(textWidget.maxLines, 1);

      // No RenderFlex/text overflow exception was thrown by pump().
      expect(tester.takeException(), isNull);
    });

    testWidgets('a large system font scale does not cause wrapping '
        '(the actual bug: unscaled box, scaled text)', (tester) async {
      await tester.pumpWidget(_harness(
        SizedBox(
          width: UnreadBadge.maxWidth(small: true),
          child: const UnreadBadge(count: 999, small: true),
        ),
        textScale: 1.5,
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final badgeHeight = tester.getSize(find.byType(Text)).height;

      // Same height as at the default scale — proving the badge's own text
      // is genuinely pinned (TextScaler.noScaling), not just coincidentally
      // fitting on one line this time.
      await tester.pumpWidget(_harness(
        SizedBox(
          width: UnreadBadge.maxWidth(small: true),
          child: const UnreadBadge(count: 999, small: true),
        ),
        textScale: 1.0,
      ));
      await tester.pump();
      final baselineHeight = tester.getSize(find.byType(Text)).height;

      expect(badgeHeight, baselineHeight);
    });
  });

  group('no visual regression to shape/colour', () {
    testWidgets('still a rounded, filled badge for a normal count', (tester) async {
      await tester.pumpWidget(_harness(const UnreadBadge(count: 7)));
      await tester.pump();

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(10));
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('hides entirely at zero', (tester) async {
      await tester.pumpWidget(_harness(const UnreadBadge(count: 0)));
      await tester.pump();
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('caps at "999+" above 999', (tester) async {
      await tester.pumpWidget(_harness(const UnreadBadge(count: 5000)));
      await tester.pump();
      expect(find.text('999+'), findsOneWidget);
    });
  });
}
