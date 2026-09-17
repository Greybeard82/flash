// The FAB cluster's geometry, and the fact that the theme already supplies it.
//
// The mock asks for mini buttons 40x40 at radius 12 on primaryContainer, 8dp
// apart, each faded while the list scrolls. Material 3 already produces the
// first three of those from `mini: true` — so the cluster passes that flag and
// lets the theme answer rather than overriding anything.
//
// **Which is exactly why this file exists.** "The framework happens to agree
// with us" is a thing that stops being true on an upgrade, and it stops being
// true silently: no analyzer warning, no failing build, just buttons that are
// 56dp or circular or the wrong tint on the next Flutter bump. Pinning the
// values means the disagreement surfaces here rather than on David's phone.
//
// **40 painted, 48 tappable, and both matter.** Material pads a mini FAB out
// to the 48dp minimum tap target, so the painted button is 40 and the thing a
// thumb has to hit is 48. Both are asserted, because the obvious "fix" on
// reading that the spec says 40 is to force the outer box to 40 too — which
// would take a control under the minimum for no gain. Unlike the category
// chips there is no row of four competing for the width here, so there is
// nothing to buy by shrinking it.
//
// The cluster itself was lifted out of two screens that had built it by hand —
// the feed with three buttons, Alerts with two — each repeating the same
// ScrollFade wrapper and the same 8dp SizedBox between every pair.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/fab_cluster.dart';
import 'package:flash/widgets/scroll_fade.dart';

late ScrollFadeController _controller;

List<FabAction> _actions({int count = 3, VoidCallback? onFirst}) => [
      FabAction(
        heroTag: 'a',
        icon: const Icon(Icons.refresh_rounded),
        tooltip: 'Refresh',
        onPressed: onFirst ?? () {},
        buttonKey: const ValueKey('fab_a'),
      ),
      FabAction(
        heroTag: 'b',
        icon: const Icon(Icons.search_rounded),
        tooltip: 'Search',
        onPressed: () {},
        buttonKey: const ValueKey('fab_b'),
      ),
      if (count > 2)
        FabAction(
          heroTag: 'c',
          icon: const Icon(Icons.done_all_rounded),
          tooltip: 'Mark all read',
          onPressed: () {},
          buttonKey: const ValueKey('fab_c'),
        ),
    ];

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  int count = 3,
  VoidCallback? onFirst,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      floatingActionButton: FabCluster(
        controller: _controller,
        actions: _actions(count: count, onFirst: onFirst),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The painted button, not the padded tap target around it.
Size _paintedSize(WidgetTester tester, Key key) => tester.getSize(
      find
          .descendant(of: find.byKey(key), matching: find.byType(Material))
          .first,
    );

Material _paintedOf(WidgetTester tester, Key key) => tester.widget<Material>(
      find
          .descendant(of: find.byKey(key), matching: find.byType(Material))
          .first,
    );

void main() {
  setUp(() => _controller = ScrollFadeController());
  tearDown(() => _controller.dispose());

  group('geometry', () {
    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
    ]) {
      testWidgets('$name: minis are 40x40 painted', (tester) async {
        await _pump(tester, theme: theme);
        for (final k in ['fab_a', 'fab_b', 'fab_c']) {
          expect(_paintedSize(tester, ValueKey(k)), const Size(40, 40),
              reason: '$name: $k is not the mock\'s 40dp button');
        }
      });

      testWidgets('$name: and 48x48 tappable', (tester) async {
        // Material's minimum. Do not "fix" this down to 40.
        await _pump(tester, theme: theme);
        expect(tester.getSize(find.byKey(const ValueKey('fab_a'))),
            const Size(48, 48));
      });

      testWidgets('$name: radius 12, not a circle', (tester) async {
        await _pump(tester, theme: theme);
        final shape = _paintedOf(tester, const ValueKey('fab_a')).shape;
        expect(shape, isA<RoundedRectangleBorder>());
        expect((shape! as RoundedRectangleBorder).borderRadius,
            BorderRadius.circular(12));
      });

      testWidgets('$name: filled with primaryContainer', (tester) async {
        await _pump(tester, theme: theme);
        expect(_paintedOf(tester, const ValueKey('fab_a')).color,
            theme.colorScheme.primaryContainer);
      });
    }

    testWidgets('buttons sit 8dp apart', (tester) async {
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light));

      final a = tester.getRect(find.byKey(const ValueKey('fab_a')));
      final b = tester.getRect(find.byKey(const ValueKey('fab_b')));
      final c = tester.getRect(find.byKey(const ValueKey('fab_c')));

      expect(FabCluster.gap, 8);
      // Measured on the padded tap boxes, which abut the SizedBox between
      // them, so the reported gap is the declared one.
      expect(b.top - a.bottom, FabCluster.gap);
      expect(c.top - b.bottom, FabCluster.gap);
    });

    testWidgets('no gap is added above the first or below the last',
        (tester) async {
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light));

      final cluster = tester.getSize(find.byType(FabCluster));
      // 3 buttons at 48 plus 2 gaps of 8.
      expect(cluster.height, 48 * 3 + FabCluster.gap * 2);
    });

    testWidgets('a two-button cluster gets one gap, not two', (tester) async {
      // Alerts builds two. An off-by-one in the separator loop would show up
      // as a stray 8dp under the last button.
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light), count: 2);

      expect(tester.getSize(find.byType(FabCluster)).height,
          48 * 2 + FabCluster.gap);
    });
  });

  group('every button fades with the list', () {
    testWidgets('all of them are wrapped, not just the first', (tester) async {
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light));
      expect(find.byType(ScrollFade), findsNWidgets(3));
    });

    testWidgets('scrolling fades the whole cluster', (tester) async {
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light));

      _controller.onScroll();
      // One frame, not pumpAndSettle. The controller's settle delay is 150ms
      // and the fade is 200ms, so settling runs the timer, brings the buttons
      // back, and reports 1.0 — which is the correct end state and the wrong
      // thing to measure. In use a fling re-arms that timer on every event.
      // Reading AnimatedOpacity.opacity gives the target rather than the
      // animation's current value, so one pump is enough.
      await tester.pump();

      final opacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity)
          .toSet();
      expect(opacities, {ScrollFade.fadedOpacity},
          reason: 'a button left unwrapped would still be at 1.0');

      // Let the settle timer run out before the tree is torn down; a pending
      // timer at disposal is an assertion failure in its own right.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
    });

    testWidgets('and they come back when it settles', (tester) async {
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light));

      _controller.onScroll();
      await tester.pumpAndSettle();
      _controller.settleNow();
      await tester.pumpAndSettle();

      final opacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .map((w) => w.opacity)
          .toSet();
      expect(opacities, {1.0});
    });
  });

  group('it still works as a button', () {
    testWidgets('tapping one fires its callback', (tester) async {
      var taps = 0;
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light),
          onFirst: () => taps++);

      await tester.tap(find.byKey(const ValueKey('fab_a')));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('a null onPressed disables it', (tester) async {
      // The feed's refresh button passes null while a fetch is in flight.
      await tester.pumpWidget(MaterialApp(
        theme: flashQuietInkTheme(brightness: Brightness.light),
        home: Scaffold(
          floatingActionButton: FabCluster(
            controller: _controller,
            actions: const [
              FabAction(
                heroTag: 'a',
                icon: Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: null,
                buttonKey: ValueKey('fab_a'),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNull);
    });

    testWidgets('an arbitrary widget can be the glyph', (tester) async {
      // Not an IconData: the feed swaps a spinner in mid-refresh.
      await tester.pumpWidget(MaterialApp(
        theme: flashQuietInkTheme(brightness: Brightness.light),
        home: Scaffold(
          floatingActionButton: FabCluster(
            controller: _controller,
            actions: [
              FabAction(
                heroTag: 'a',
                icon: const CircularProgressIndicator(),
                tooltip: 'Refreshing',
                onPressed: () {},
              ),
            ],
          ),
        ),
      ));
      // pump, not pumpAndSettle: a spinner never stops animating, so settling
      // waits for a frame that never comes.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('a stock ThemeData renders it without throwing', (tester) async {
    await _pump(tester, theme: null);
    expect(tester.takeException(), isNull);
    expect(find.byType(FloatingActionButton), findsNWidgets(3));
  });
}
