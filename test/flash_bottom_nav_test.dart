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
}
