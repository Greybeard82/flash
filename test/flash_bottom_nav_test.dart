// The bottom nav reads its colours from the navigation theme, and the pill
// from a role — which is how one widget serves two themes.
//
// This replaced Material's BottomNavigationBar, which cannot draw the mock's
// selected state: a filled pill around the icon *and* its label. Material's
// own indicator sits behind the icon only.
//
// **The risk the replacement introduced, and what this file guards.** A custom
// widget is free to read `colorScheme` directly, and doing so would have
// silently restyled Newspaper. Newspaper's bar is `_npSurface2` under `_npRed`,
// declared in its `bottomNavigationBarTheme`; its ColorScheme does not declare
// `surfaceContainer` at all, so a widget reading that would have picked up
// whatever Material's fallback produced and nobody would have noticed until
// they turned Newspaper on.
//
// So every colour comes from `bottomNavigationBarTheme`, and the one thing
// Material has no slot for — the pill — comes from `FlashColors.navPill`.
// Newspaper sets that to transparent, which is how a theme opts out of a shape
// without the widget branching on which theme it is. These tests assert that
// opt-out actually holds.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/flash_bottom_nav.dart';

const _destinations = [
  FlashNavDestination(
    icon: Icon(Icons.bolt_outlined),
    selectedIcon: Icon(Icons.bolt),
    label: 'Flash',
  ),
  FlashNavDestination(
    icon: Icon(Icons.rss_feed_outlined),
    selectedIcon: Icon(Icons.rss_feed_rounded),
    label: 'Categories',
  ),
  FlashNavDestination(
    icon: Icon(Icons.bookmark_border_rounded),
    selectedIcon: Icon(Icons.bookmark_rounded),
    label: 'Bookmarks',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  int currentIndex = 0,
  ValueChanged<int>? onTap,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(
      bottomNavigationBar: FlashBottomNav(
        currentIndex: currentIndex,
        onTap: onTap ?? (_) {},
        destinations: _destinations,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _item(int i) => find.byKey(ValueKey('nav_item_$i'));

/// The painted box inside one item — the thing carrying the pill, or not.
Container _boxOf(WidgetTester tester, int i) => tester.widget<Container>(
      find.descendant(of: _item(i), matching: find.byType(Container)),
    );

Color? _pillOf(WidgetTester tester, int i) =>
    (_boxOf(tester, i).decoration! as BoxDecoration).color;

TextStyle _labelOf(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style!;

Color _glyphOf(WidgetTester tester, int i) => tester
    .widget<IconTheme>(
      find.descendant(of: _item(i), matching: find.byType(IconTheme)).first,
    )
    .data
    .color!;

void main() {
  group('Newspaper renders exactly as it always has', () {
    final theme = flashNewspaperTheme();
    final nav = theme.bottomNavigationBarTheme;

    testWidgets('no pill is painted, on any item', (tester) async {
      // The opt-out. If this fails, Newspaper has grown a capsule it never
      // had, which is Quiet Ink furniture wearing newsprint colours.
      await _pump(tester, theme: theme, currentIndex: 1);

      for (var i = 0; i < _destinations.length; i++) {
        expect(_pillOf(tester, i), Colors.transparent,
            reason: 'item $i painted a pill in Newspaper');
      }
      expect(theme.flashColors.navPill, Colors.transparent);
    });

    testWidgets('the selected item is still _npRed', (tester) async {
      await _pump(tester, theme: theme, currentIndex: 1);

      expect(_glyphOf(tester, 1), nav.selectedItemColor);
      expect(_labelOf(tester, 'Categories').color, nav.selectedItemColor);
      // Belt and braces: the value itself, so a theme edit that changed what
      // selectedItemColor resolves to would have to be deliberate.
      expect(nav.selectedItemColor, const Color(0xFFA0231A));
    });

    testWidgets('unselected items take its own unselected grey',
        (tester) async {
      await _pump(tester, theme: theme, currentIndex: 1);

      expect(_glyphOf(tester, 0), nav.unselectedItemColor);
      expect(nav.unselectedItemColor, const Color(0xFF888880));
    });

    testWidgets('the bar is _npSurface2, not a scheme colour', (tester) async {
      // The specific mistake this widget could have made. Newspaper's
      // ColorScheme does not declare surfaceContainer, so a widget reading it
      // would get Material's fallback and quietly restyle the bar.
      await _pump(tester, theme: theme);

      final bar = tester.widget<Material>(
        find
            .ancestor(
              of: find.byType(SafeArea),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(bar.color, nav.backgroundColor);
      expect(bar.color, const Color(0xFFE7E7E3));
      expect(bar.color, isNot(theme.colorScheme.surfaceContainer),
          reason: 'if these are equal the test proves nothing — Newspaper was '
              'chosen for this assertion because the two differ');
    });
  });

  group('Quiet Ink puts the selected item in a pill', () {
    for (final brightness in Brightness.values) {
      final theme = flashQuietInkTheme(brightness: brightness);
      final nav = theme.bottomNavigationBarTheme;
      final name = brightness.name;

      testWidgets('$name: the pill is primaryContainer', (tester) async {
        await _pump(tester, theme: theme, currentIndex: 1);

        expect(_pillOf(tester, 1), theme.colorScheme.primaryContainer);
        expect(theme.flashColors.navPill, theme.colorScheme.primaryContainer);
      });

      testWidgets('$name: only the selected item has one', (tester) async {
        await _pump(tester, theme: theme, currentIndex: 1);

        expect(_pillOf(tester, 0), Colors.transparent);
        expect(_pillOf(tester, 2), Colors.transparent);
      });

      testWidgets('$name: content colours come from the nav theme',
          (tester) async {
        await _pump(tester, theme: theme, currentIndex: 1);

        expect(_glyphOf(tester, 1), nav.selectedItemColor);
        expect(_labelOf(tester, 'Categories').color, nav.selectedItemColor);
        expect(_glyphOf(tester, 0), nav.unselectedItemColor);
        expect(_labelOf(tester, 'Flash').color, nav.unselectedItemColor);
      });

      testWidgets('$name: the geometry is what the mock asks for',
          (tester) async {
        await _pump(tester, theme: theme, currentIndex: 1);

        expect(_boxOf(tester, 1).padding,
            const EdgeInsets.symmetric(horizontal: 18, vertical: 6));
        expect((_boxOf(tester, 1).decoration! as BoxDecoration).borderRadius,
            BorderRadius.circular(14));
        expect(_labelOf(tester, 'Categories').fontSize, 11);

        final iconTheme = tester.widget<IconTheme>(
          find.descendant(of: _item(1), matching: find.byType(IconTheme)).first,
        );
        expect(iconTheme.data.size, 21);

        final gap = tester.widget<SizedBox>(
          find.byKey(const ValueKey('nav_icon_label_gap')).first,
        );
        expect(gap.height, 3);
      });

      testWidgets('$name: an unselected item is the same shape, unpainted',
          (tester) async {
        // So moving the selection does not shift the row sideways.
        await _pump(tester, theme: theme, currentIndex: 1);
        expect(_boxOf(tester, 0).padding, _boxOf(tester, 1).padding);
      });
    }

    testWidgets('the bar padding is 10 above, 6 aside, 16 below',
        (tester) async {
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light));
      expect(
          FlashBottomNav.barPadding, const EdgeInsets.fromLTRB(6, 10, 6, 16));

      final padding = tester.widget<Padding>(
        find.byKey(const ValueKey('nav_bar_padding')),
      );
      expect(padding.padding, FlashBottomNav.barPadding);
    });
  });

  group('it still navigates', () {
    testWidgets('tapping an item reports its index', (tester) async {
      int? tapped;
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light),
          onTap: (i) => tapped = i);

      await tester.tap(_item(2));
      await tester.pumpAndSettle();

      expect(tapped, 2);
    });

    testWidgets('tapping the already-selected item still reports it',
        (tester) async {
      int? tapped;
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light),
          currentIndex: 1,
          onTap: (i) => tapped = i);

      await tester.tap(_item(1));
      await tester.pumpAndSettle();

      expect(tapped, 1);
    });

    testWidgets('the selected glyph is used, not the unselected one',
        (tester) async {
      await _pump(tester,
          theme: flashQuietInkTheme(brightness: Brightness.light),
          currentIndex: 1);

      expect(find.byIcon(Icons.rss_feed_rounded), findsOneWidget);
      expect(find.byIcon(Icons.rss_feed_outlined), findsNothing);
    });
  });

  group('every theme renders it without throwing', () {
    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
      // The one that carries no FlashColors at all, so navPill comes from the
      // fallback rather than from a registered extension.
      ('stock ThemeData', null),
    ]) {
      testWidgets(name, (tester) async {
        await _pump(tester, theme: theme, currentIndex: 1);
        expect(tester.takeException(), isNull);
        expect(find.text('Categories'), findsOneWidget);
      });
    }
  });

  group('it occupies a bar, not the page', () {
    // The regression this file did not catch, and the reason it did not.
    //
    // FlashBottomNav shipped with a `Center` wrapping each item. Center takes
    // the largest size its constraints allow, and in the Scaffold's
    // bottomNavigationBar slot the incoming height constraint is the whole
    // viewport — so every item became as tall as the screen, the Row with it,
    // and the bar with that. The body was laid out at exactly zero pixels and
    // the nav floated in the vertical middle of an empty page. On device: no
    // app bar, no content, no FAB, four destinations hanging in the middle.
    //
    // Every test above passed throughout. They pumped the nav into a Scaffold
    // with no `body:`, and asserted colours, paddings and the sizes of nodes
    // *inside* an item — never the height of the bar itself, and never what
    // was left over for anything else. A widget that renders correct-looking
    // parts while consuming the entire screen satisfied all of them.
    //
    // So these assert the two things that were actually wrong: the body gets
    // room, and the bar is at the bottom of it.

    Future<void> pumpShell(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: flashQuietInkTheme(brightness: Brightness.light),
        home: Scaffold(
          appBar: AppBar(title: const Text('Flash')),
          body: Container(key: const ValueKey('body'), color: Colors.white),
          floatingActionButton: FloatingActionButton(
            mini: true,
            onPressed: () {},
            child: const Icon(Icons.add),
          ),
          bottomNavigationBar: FlashBottomNav(
            currentIndex: 1,
            onTap: (_) {},
            destinations: const [
              FlashNavDestination(
                icon: Icon(Icons.bolt),
                selectedIcon: Icon(Icons.bolt),
                label: 'Flash',
              ),
              FlashNavDestination(
                icon: Icon(Icons.rss_feed),
                selectedIcon: Icon(Icons.rss_feed),
                label: 'Categories',
              ),
              FlashNavDestination(
                icon: Icon(Icons.bookmark),
                selectedIcon: Icon(Icons.bookmark),
                label: 'Bookmarks',
              ),
              FlashNavDestination(
                icon: Icon(Icons.notifications),
                selectedIcon: Icon(Icons.notifications),
                label: 'Alerts',
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    for (final width in [320.0, 360.0, 411.0]) {
      final w = width.toInt();

      testWidgets('at ${w}dp the body gets the screen', (tester) async {
        await pumpShell(tester, width);

        final body = tester.getSize(find.byKey(const ValueKey('body')));
        expect(body.height, greaterThan(0),
            reason: 'the bar consumed the whole viewport and left the body '
                'nothing — the bug, stated as plainly as it can be');
        expect(body.height, greaterThan(400),
            reason: 'and it should get most of the screen, not a sliver');
      });

      testWidgets('at ${w}dp the bar is bar-sized', (tester) async {
        await pumpShell(tester, width);

        final nav = tester.getSize(find.byType(FlashBottomNav));
        expect(nav.height, lessThan(120),
            reason: 'a navigation bar taller than 120dp is not a bar');
        expect(nav.height, greaterThan(40),
            reason: 'and one shorter than 40dp has collapsed');
      });

      testWidgets('at ${w}dp it sits at the bottom', (tester) async {
        await pumpShell(tester, width);

        final screen =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final nav = tester.getRect(find.byType(FlashBottomNav));
        final body = tester.getRect(find.byKey(const ValueKey('body')));

        expect(nav.bottom, screen, reason: 'flush with the bottom edge');
        expect(nav.top, greaterThan(screen / 2),
            reason: 'the bar floated at half the screen height when its items '
                'expanded to fill it');
        expect(body.bottom, nav.top,
            reason: 'the body ends exactly where the bar begins');
      });

      testWidgets('at ${w}dp no label is truncated', (tester) async {
        // Not "does it ellipsize" but whether the painted word is the whole
        // word. scaleDown shrinks rather than cutting, so a label that does
        // not fit gets smaller, never shorter.
        await pumpShell(tester, width);

        for (final label in ['Flash', 'Categories', 'Bookmarks', 'Alerts']) {
          // Scoped to the bar: the AppBar title is also "Flash", and an
          // unscoped finder matches both.
          final widget = tester.widget<Text>(find.descendant(
            of: find.byType(FlashBottomNav),
            matching: find.text(label),
          ));
          expect(widget.data, label,
              reason: 'the Text must carry the whole word');
          expect(widget.overflow, isNot(TextOverflow.ellipsis),
              reason: '"Categori..." stops being the word — the label shrinks '
                  'instead');
        }
      });

      testWidgets('at ${w}dp nothing overflows', (tester) async {
        await pumpShell(tester, width);
        expect(tester.takeException(), isNull,
            reason: 'a RenderFlex overflow here is four destinations not '
                'fitting across the bar');
      });
    }
  });

  group('the label respects the user font size, down to a floor', () {
    // What went wrong in the first fix, and why this matrix exists.
    //
    // The labels were originally wrapped in a bare FittedBox(scaleDown) to
    // stop them ellipsizing. That solved the truncation and created something
    // worse: FittedBox has no floor and no idea what textScaler is for, so a
    // user who set Android's font size to large got the label scaled up by the
    // system and scaled straight back down by the widget. Their accessibility
    // setting did nothing whatsoever, on the surface they touch most, and no
    // test noticed because no test ever set a scale factor.
    //
    // The sizing is deliberate now: the scaled size is where it starts, the
    // pill's padding gives way first because a narrower pill is invisible and
    // a smaller label is not, and only then does the label shrink — stopping
    // at a hard 9px, because below that it is not a label any more and an
    // unreadable word is no better than a truncated one.
    //
    // FittedBox is still there, but only as a backstop for the gap between
    // what TextPainter measures and what the raster needs.

    Future<void> pumpAt(
      WidgetTester tester, {
      required double width,
      required double scale,
    }) async {
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        theme: flashQuietInkTheme(brightness: Brightness.light),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Container(key: const ValueKey('body'), color: Colors.white),
            bottomNavigationBar: FlashBottomNav(
              currentIndex: 1,
              onTap: (_) {},
              destinations: const [
                FlashNavDestination(
                  icon: Icon(Icons.bolt),
                  selectedIcon: Icon(Icons.bolt),
                  label: 'Flash',
                ),
                FlashNavDestination(
                  icon: Icon(Icons.rss_feed),
                  selectedIcon: Icon(Icons.rss_feed),
                  label: 'Categories',
                ),
                FlashNavDestination(
                  icon: Icon(Icons.bookmark),
                  selectedIcon: Icon(Icons.bookmark),
                  label: 'Bookmarks',
                ),
                FlashNavDestination(
                  icon: Icon(Icons.notifications),
                  selectedIcon: Icon(Icons.notifications),
                  label: 'Alerts',
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Text labelOf(WidgetTester tester, String label) =>
        tester.widget<Text>(find.descendant(
          of: find.byType(FlashBottomNav),
          matching: find.text(label),
        ));

    const labels = ['Flash', 'Categories', 'Bookmarks', 'Alerts'];

    for (final width in [320.0, 360.0, 411.0]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        final at = 'at ${width.toInt()}dp / ${scale}x';

        testWidgets('$at no label goes below the 9px floor', (tester) async {
          await pumpAt(tester, width: width, scale: scale);

          for (final label in labels) {
            final size = labelOf(tester, label).style!.fontSize!;
            expect(size, greaterThanOrEqualTo(FlashBottomNav.minLabelSize),
                reason: '$at "$label" rendered at '
                    '${size.toStringAsFixed(2)}px, below the floor');
          }
        });

        testWidgets('$at no label is truncated', (tester) async {
          await pumpAt(tester, width: width, scale: scale);

          for (final label in labels) {
            final text = labelOf(tester, label);
            expect(text.data, label, reason: '$at the whole word must survive');
            expect(text.overflow, isNot(TextOverflow.ellipsis));
          }
        });

        testWidgets('$at the bar is still a bar and the body still has room',
            (tester) async {
          // A larger font must not reopen the bug that started all this: the
          // bar growing until the page has nothing left.
          await pumpAt(tester, width: width, scale: scale);

          expect(
              tester.getSize(find.byType(FlashBottomNav)).height, lessThan(160),
              reason: '$at the bar grew out of proportion');
          expect(tester.getSize(find.byKey(const ValueKey('body'))).height,
              greaterThan(400),
              reason: '$at the body lost the screen');
        });

        testWidgets('$at nothing overflows', (tester) async {
          await pumpAt(tester, width: width, scale: scale);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('a larger setting really does produce a larger label',
        (tester) async {
      // The assertion the old FittedBox would have failed. Measured at the
      // widest tier and on the shortest label, so there is room for the
      // scale-up to actually happen rather than being spent on fitting.
      await pumpAt(tester, width: 411, scale: 1.0);
      final plain = labelOf(tester, 'Flash').style!.fontSize!;

      await pumpAt(tester, width: 411, scale: 1.3);
      final larger = labelOf(tester, 'Flash').style!.fontSize!;

      expect(larger, greaterThan(plain),
          reason: 'Android font size is set to large and the label did not '
              'change — which is the accessibility setting doing nothing');
    });

    testWidgets('padding gives way before the label does', (tester) async {
      // The ordering that makes the floor reachable at all: under pressure
      // the pill tightens before the text shrinks.
      //
      // Measured on the SHORT label for the roomy case, deliberately. In
      // `flutter test` the real font is replaced by a fixed-width test font
      // where every glyph is a square of the font size, so "Categories" comes
      // out 110px at 11px where Instrument Sans draws it near 58. That makes
      // the harness considerably harsher than a phone — which is fine, and
      // useful, but it means even 411dp is already tightening for the long
      // labels here and would not be on device.
      EdgeInsets padOf(WidgetTester tester, int item) => tester
          .widget<Container>(find.descendant(
            of: find.byKey(ValueKey('nav_item_$item')),
            matching: find.byType(Container),
          ))
          .padding as EdgeInsets;

      await pumpAt(tester, width: 411, scale: 1.0);
      expect(padOf(tester, 0).left, FlashBottomNav.pillPaddingH,
          reason:
              'a short label on a wide screen keeps the 18dp the mock asks for');

      await pumpAt(tester, width: 320, scale: 2.0);
      final tight = padOf(tester, 1);
      expect(tight.left, lessThan(FlashBottomNav.pillPaddingH),
          reason: 'the pill should have tightened under pressure');
      expect(tight.left, greaterThanOrEqualTo(FlashBottomNav.minPillPaddingH),
          reason: 'but not past its own minimum');
    });
  });
}
