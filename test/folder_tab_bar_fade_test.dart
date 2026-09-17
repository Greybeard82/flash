// The folder bar shows that it scrolls.
//
// **This is the half of the category bug that was left unfixed.** The chip a
// person had just made is now scrolled into view; every other chip past the
// third was still reachable only by a sideways swipe that nothing advertised.
// The ship list named it as the most likely tester complaint, and anyone who
// took the starter pack has five categories against three visible.
//
// **`scroll_fade.dart` was not reusable here, and the reason is worth keeping**
// because the two things share a word and nothing else. `ScrollFade` answers
// "is the list moving right now", with a 150ms settle timer, and fades the
// floating BUTTON CLUSTER down to 0.25 opacity so it stops covering rows —
// `fab_cluster.dart` is its only caller. This answers "is there anything past
// this edge", it is a gradient rather than an opacity, and it must be true
// while the finger is nowhere near the screen. Neither could be expressed in
// the other without breaking it.
//
// Three things make the fade right rather than merely present, and each is a
// group below:
//
//   1. It follows the scroll POSITION. An always-on fade is worse than none,
//      because it is an affordance that lies.
//   2. It never eats a tap. The chip under it is one the user can see and is
//      reaching for.
//   3. It fades to the surface it is actually sitting on, which is a
//      different colour in each of the three themes.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/folder_tab_bar.dart';

Folder _folder(int id, String name) =>
    Folder(id: id, name: name, position: id, createdAt: 0, colorIndex: id % 6);

/// Six categories, which is David's library and roughly twice what fits.
List<Folder> _many() => [
      _folder(1, 'World News'),
      _folder(2, 'Tech'),
      _folder(3, 'Fitness'),
      _folder(4, 'Travelling'),
      _folder(5, 'Gaming'),
      _folder(6, 'Science'),
    ];

Widget _harness({
  required List<Folder> folders,
  ThemeData? theme,
  ValueChanged<int>? onTabSelected,
}) =>
    MaterialApp(
      locale: const Locale('en'),
      theme: theme ?? flashQuietInkTheme(brightness: Brightness.light),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flash'),
          bottom: FolderTabBar(
            folders: folders,
            selectedIndex: 0,
            folderUnreadCounts: const {},
            allUnreadCount: 0,
            onTabSelected: onTabSelected ?? (_) {},
          ),
        ),
        body: const SizedBox(),
      ),
    );

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Finder get _fadeFinder => find.descendant(
      of: find.byType(FolderTabBar),
      matching: find.byType(AnimatedOpacity),
    );

/// The opacity of one edge's fade, identified by where it is painted rather
/// than by its order in the tree.
double _fadeOpacity(WidgetTester tester, {required bool atStart}) {
  final bar = tester.getRect(find.byType(FolderTabBar));
  final count = tester.widgetList(_fadeFinder).length;
  expect(count, 2, reason: 'one fade per edge, always built, opacity-driven');
  for (var i = 0; i < count; i++) {
    final rect = tester.getRect(_fadeFinder.at(i));
    final isStart = (rect.left - bar.left).abs() < 1;
    if (isStart == atStart) {
      return tester.widget<AnimatedOpacity>(_fadeFinder.at(i)).opacity;
    }
  }
  fail('no fade found at the ${atStart ? "start" : "end"} edge');
}

/// The opaque stop of a fade's gradient: the colour it is fading *to*.
Color _fadeSurface(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(find
      .descendant(of: _fadeFinder.first, matching: find.byType(DecoratedBox))
      .first);
  final gradient = (box.decoration as BoxDecoration).gradient! as LinearGradient;
  return gradient.colors.reduce((a, b) => a.a >= b.a ? a : b);
}

/// Scrolls the strip toward the end far enough to leave the start behind.
Future<void> _scrollRight(WidgetTester tester) async {
  await tester.drag(
    find.descendant(
      of: find.byType(FolderTabBar),
      matching: find.byType(SingleChildScrollView),
    ),
    const Offset(-160, 0),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the fade follows the scroll position', () {
    testWidgets('at rest with overflow: end only', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(folders: _many()));
      await tester.pumpAndSettle();

      expect(_fadeOpacity(tester, atStart: false), 1.0,
          reason: 'six categories do not fit; there is more to the right');
      expect(_fadeOpacity(tester, atStart: true), 0.0,
          reason: 'nothing is off the left yet, so nothing may suggest it is');
    });

    testWidgets('scrolled into the middle: both', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(folders: _many()));
      await tester.pumpAndSettle();
      await _scrollRight(tester);

      expect(_fadeOpacity(tester, atStart: true), 1.0,
          reason: 'the All chip is off to the left now, which is the same '
              'problem in reverse and the reason both edges exist');
      expect(_fadeOpacity(tester, atStart: false), 1.0);
    });

    testWidgets('scrolled to the very end: start only', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(folders: _many()));
      await tester.pumpAndSettle();
      await tester.fling(
        find.descendant(
          of: find.byType(FolderTabBar),
          matching: find.byType(SingleChildScrollView),
        ),
        const Offset(-800, 0),
        3000,
      );
      await tester.pumpAndSettle();

      expect(_fadeOpacity(tester, atStart: false), 0.0,
          reason: 'there is nothing further right, so promising some would be '
              'the lie this whole group is about');
      expect(_fadeOpacity(tester, atStart: true), 1.0);
    });

    testWidgets('everything fits: NEITHER fade', (tester) async {
      // The case that makes the feature honest rather than decorative.
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(folders: [_folder(1, 'Tech')]));
      await tester.pumpAndSettle();

      expect(_fadeOpacity(tester, atStart: true), 0.0);
      expect(_fadeOpacity(tester, atStart: false), 0.0);
    });

    testWidgets('a chip removed until it fits takes the fade with it',
        (tester) async {
      // maxScrollExtent changes with nobody scrolling, so the scroll listener
      // never fires. Deleting the category that was causing the overflow is
      // exactly this case.
      tester.view.physicalSize = const Size(700, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(folders: _many()));
      await tester.pumpAndSettle();
      expect(_fadeOpacity(tester, atStart: false), 1.0);

      await tester.pumpWidget(_harness(folders: [_folder(1, 'Tech')]));
      await tester.pumpAndSettle();
      expect(_fadeOpacity(tester, atStart: false), 0.0,
          reason: 'the bar fits now and must stop claiming otherwise');
    });
  });

  group('the fade never eats a tap', () {
    for (final atStart in [true, false]) {
      final edge = atStart ? 'start' : 'end';
      testWidgets('a chip under the $edge fade still fires', (tester) async {
        await _phone(tester);
        int? tapped;
        await tester.pumpWidget(
            _harness(folders: _many(), onTabSelected: (i) => tapped = i));
        await tester.pumpAndSettle();
        // Into the middle, so BOTH edges have a fade over a real chip.
        await _scrollRight(tester);
        expect(_fadeOpacity(tester, atStart: atStart), 1.0,
            reason: 'the fade must actually be there for this to prove '
                'anything -- rule 10.1');

        final bar = tester.getRect(find.byType(FolderTabBar));
        final fade = Rect.fromLTWH(
          atStart ? bar.left : bar.right - FolderTabBar.edgeFadeWidth,
          bar.top,
          FolderTabBar.edgeFadeWidth,
          bar.height,
        );

        // A pixel that is inside the fade AND on a chip's own ink area.
        Offset? point;
        int? expected;
        for (var i = 0; i < 7; i++) {
          final chip = find.byKey(ValueKey('folder_tab_$i'));
          if (chip.evaluate().isEmpty) continue;
          final ink = tester.getRect(
              find.descendant(of: chip, matching: find.byType(InkWell)));
          final overlap = ink.intersect(fade);
          if (overlap.width > 4 && overlap.height > 4) {
            point = Offset(overlap.center.dx, bar.center.dy);
            expected = i;
            break;
          }
        }
        expect(point, isNotNull,
            reason: 'no chip lies under the $edge fade, so this test is not '
                'testing what it claims to');

        await tester.tapAt(point!);
        await tester.pumpAndSettle();
        expect(tapped, expected,
            reason: 'IgnorePointer is the whole of the fix; without it this '
                'tap dies in a decoration');
      });
    }
  });

  group('it fades to the surface it is sitting on', () {
    // A fade hardcoded to white is a grey smudge on newsprint and a pale
    // bruise in the dark. The bar paints no background of its own -- it lives
    // in AppBar.bottom -- so the colour has to come from the app bar's.
    final cases = <String, (ThemeData, Color)>{
      'Quiet Ink light': (
        flashQuietInkTheme(brightness: Brightness.light),
        const Color(0xFFFFFFFF),
      ),
      'Quiet Ink dark': (
        flashQuietInkTheme(brightness: Brightness.dark),
        const Color(0xFF0D1211),
      ),
      'Newspaper': (flashNewspaperTheme(), const Color(0xFFF2F1EE)),
    };

    cases.forEach((name, expected) {
      testWidgets('$name fades to ${expected.$2}', (tester) async {
        await _phone(tester);
        await tester.pumpWidget(
            _harness(folders: _many(), theme: expected.$1));
        await tester.pumpAndSettle();

        expect(_fadeSurface(tester), expected.$2, reason: name);
        expect(_fadeSurface(tester),
            expected.$1.appBarTheme.backgroundColor,
            reason: '$name: resolved from the theme, not restated here');
      });
    });

    testWidgets('the three are actually different from one another',
        (tester) async {
      // Guards the test above from passing because every theme happens to
      // return the same hardcoded value.
      final seen = <Color>{};
      for (final entry in cases.values) {
        await _phone(tester);
        await tester.pumpWidget(_harness(folders: _many(), theme: entry.$1));
        await tester.pumpAndSettle();
        seen.add(_fadeSurface(tester));
      }
      expect(seen, hasLength(3),
          reason: 'if this collapses, the fade stopped reading the theme');
    });
  });

  group('geometry', () {
    test('a fade is narrower than the narrowest chip', () {
      // 72dp is the chip target floor. A fade wider than that could cover a
      // chip whole, which is not a soft edge, it is a missing chip.
      expect(FolderTabBar.edgeFadeWidth, lessThan(72.0));
      expect(FolderTabBar.edgeFadeWidth, greaterThan(0));
    });

    test('the tempo is the one the app already uses', () {
      expect(FolderTabBar.edgeFadeDuration, const Duration(milliseconds: 200));
    });
  });
}
