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
}
