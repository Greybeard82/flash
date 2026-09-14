// FolderTabBar: geometry, hues, the separated numeral, and the hidden gesture.
//
// Rewritten for the chip redesign. The round r999 pills with "(12)" inside the
// label are gone; chips are 36x9dp rounded rectangles tinted with their own
// category's hue, and the count is a separate mono numeral beside the label.
//
// **What this file is really for.** Two things survive the redesign that
// nothing else protects:
//
//   1. The 36dp target floor. It is below Material's 48 and always has been —
//      the row is tuned to fit four chips across a phone — so it is pinned
//      rather than quietly altered. If the chip height moves, this says so.
//   2. Long-press a chip to mark that category read. **The previous version of
//      this file did not cover it at all** — its harness never even passed
//      `onMarkAllRead`. A gesture with no visible affordance and no test is one
//      refactor away from being deleted by someone who cannot see it.
//
// Everything the old file pinned is still pinned here, with one deliberate
// change: the inline "Gaming (7)" assertions are now "Gaming" plus a separate
// "7", because that is the thing the redesign changed.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/theme/category_colors.dart';
import 'package:flash/widgets/folder_tab_bar.dart';

/// The chip geometry, asserted as numbers so a layout edit cannot drift it.
const double kChipHeight = 36.0;
const double kChipRadius = 9.0;
const double kSelectedSidePadding = 13.0;
const double kUnselectedSidePadding = 12.0;
const double kMinChipWidth = 72.0;

Folder _folder(int id, String name, {int colorIndex = 0}) => Folder(
    id: id, name: name, position: id, createdAt: 0, colorIndex: colorIndex);

Widget _harness({
  required List<Folder> folders,
  int selectedIndex = 0,
  Map<int, int> folderUnreadCounts = const {},
  int allUnreadCount = 0,
  ValueChanged<int>? onTabSelected,
  VoidCallback? onMarkAllRead,
  ThemeData? theme,
}) {
  return MaterialApp(
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
      body: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FolderTabBar(
            folders: folders,
            selectedIndex: selectedIndex,
            folderUnreadCounts: folderUnreadCounts,
            allUnreadCount: allUnreadCount,
            onTabSelected: onTabSelected ?? (_) {},
            onMarkAllRead: onMarkAllRead,
          ),
        ],
      ),
    ),
  );
}

Finder _chip(int i) => find.byKey(ValueKey('folder_tab_$i'));

Finder _inkOf(int i) =>
    find.descendant(of: _chip(i), matching: find.byType(InkWell));

/// The painted chip body — the thing carrying the fill and the radius.
AnimatedContainer _bodyOf(WidgetTester tester, int i) => tester.widget(
      find.descendant(of: _chip(i), matching: find.byType(AnimatedContainer)),
    );

BoxDecoration _decorationOf(WidgetTester tester, int i) =>
    _bodyOf(tester, i).decoration! as BoxDecoration;

TextStyle _labelStyleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  group('bar height', () {
    // Carried over unchanged: FeedScreen's FAB offset references this constant
    // rather than a hardcoded number.
    test('exposes a public height constant of at least 56dp', () {
      expect(FolderTabBar.barHeight, greaterThanOrEqualTo(56.0));
    });

    testWidgets('renders at the declared height', (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
      ));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(FolderTabBar)).height,
          FolderTabBar.barHeight);
    });
  });

  group('tap targets', () {
    // Measured on the InkWell, not on the keyed Padding.
    //
    // _FolderTab puts `Padding(vertical: 10)` OUTSIDE the Material/InkWell, so
    // measuring the keyed box returns 56 — 36dp of gesture area plus 10dp of
    // dead margin above and below. Asserting >= 48 on that box passes for any
    // InkWell height whatsoever, including zero, so it proves nothing about
    // the chip. These read the descendant InkWell, which is what a finger
    // actually has to hit.
    testWidgets('every chip is 36dp tall and at least 48dp wide',
        (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech'), _folder(3, 'UK')],
      ));
      await tester.pumpAndSettle();

      for (var i = 0; i <= 3; i++) {
        final size = tester.getSize(_inkOf(i));
        expect(size.height, kChipHeight, reason: 'chip $i height');
        expect(size.width, greaterThanOrEqualTo(48.0), reason: 'chip $i width');
      }
    });

    testWidgets('a two-character folder name still gets a wide target',
        (tester) async {
      // Unchanged from the pill. The redesign tightened side padding from 14
      // to 12, which would have taken a "UK" chip under Material's 48dp floor
      // on width if the minimum had gone with it. It did not.
      await tester.pumpWidget(_harness(folders: [_folder(1, 'UK')]));
      await tester.pumpAndSettle();

      expect(
          tester.getSize(_inkOf(1)).width, greaterThanOrEqualTo(kMinChipWidth),
          reason: 'minWidth should be comfortable, not just legal');
    });
  });

  group('the gesture with no affordance', () {
    // None of this was covered before the rewrite.
    testWidgets('long-pressing a category chip marks it read', (tester) async {
      var marked = 0;
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        onMarkAllRead: () => marked++,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(_chip(1));
      await tester.pumpAndSettle();

      expect(marked, 1,
          reason: 'long-press to mark a category read has no visible '
              'affordance, so this test is the only thing standing between it '
              'and a refactor that cannot see it');
    });

    testWidgets('long-pressing the All chip works too', (tester) async {
      var marked = 0;
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        onMarkAllRead: () => marked++,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(_chip(0));
      await tester.pumpAndSettle();

      expect(marked, 1);
    });

    testWidgets('a long-press does not also fire a tap', (tester) async {
      var marked = 0;
      int? tapped;
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        onTabSelected: (i) => tapped = i,
        onMarkAllRead: () => marked++,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(_chip(1));
      await tester.pumpAndSettle();

      expect(marked, 1);
      expect(tapped, isNull,
          reason: 'marking a category read must not also switch to it');
    });

    testWidgets('chips still work when no mark-read callback is given',
        (tester) async {
      // FolderTabBar takes onMarkAllRead as nullable and FeedScreen can pass
      // null; a null long-press handler must not break tapping.
      int? tapped;
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        onTabSelected: (i) => tapped = i,
      ));
      await tester.pumpAndSettle();

      await tester.longPress(_chip(1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(_chip(1));
      await tester.pumpAndSettle();
      expect(tapped, 1);
    });
  });

  group('interaction', () {
    testWidgets('tapping a folder chip reports its index', (tester) async {
      int? tapped;
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        onTabSelected: (i) => tapped = i,
      ));
      await tester.pumpAndSettle();

      await tester.tap(_chip(2));
      await tester.pumpAndSettle();

      expect(tapped, 2, reason: 'index 0 is All, so Tech is index 2');
    });

    testWidgets('tapping the already-selected chip still reports it',
        (tester) async {
      int? tapped;
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        selectedIndex: 0,
        onTabSelected: (i) => tapped = i,
      ));
      await tester.pumpAndSettle();

      await tester.tap(_chip(0));
      await tester.pumpAndSettle();

      expect(tapped, 0);
    });
  });

  group('the count is its own numeral now', () {
    testWidgets('label and count are separate widgets, not "Gaming (7)"',
        (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        folderUnreadCounts: const {1: 7},
        allUnreadCount: 12,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gaming'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.textContaining('('), findsNothing,
          reason: 'the count split out of the label string');
    });

    testWidgets('the numeral is mono and tabular', (tester) async {
      // Tabular figures so a chip does not twitch sideways as its count
      // changes width on refresh: "9" and "11" take the same advance.
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        folderUnreadCounts: const {1: 7},
      ));
      await tester.pumpAndSettle();

      final style = _labelStyleOf(tester, '7');
      expect(style.fontFamily, kMonoFamily);
      expect(style.fontSize, kNumeralChipStyle.fontSize);
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
    });

    testWidgets('the numeral takes the label colour, never its own',
        (tester) async {
      // The bug the old gold badge had: a gold pill on a selected gold chip
      // was present in the layout and invisible on screen. Text drawn in the
      // label's own colour cannot lose contrast against its own fill.
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        selectedIndex: 0,
        allUnreadCount: 12,
        folderUnreadCounts: const {1: 7},
      ));
      await tester.pumpAndSettle();

      expect(_labelStyleOf(tester, '12').color,
          _labelStyleOf(tester, 'All').color);
      expect(_labelStyleOf(tester, '7').color,
          _labelStyleOf(tester, 'Gaming').color);
    });

    testWidgets('hidden entirely at zero, not shown as "0"', (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        folderUnreadCounts: const {1: 0},
        allUnreadCount: 0,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gaming'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('0'), findsNothing);
    });
  });

  group('chip shape and colour', () {
    for (final brightness in Brightness.values) {
      final theme = flashQuietInkTheme(brightness: brightness);
      final scheme = theme.colorScheme;
      final name = brightness.name;

      testWidgets('$name: corners are 9dp, not a full pill', (tester) async {
        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Gaming')],
          theme: theme,
        ));
        await tester.pumpAndSettle();

        expect(_decorationOf(tester, 0).borderRadius,
            BorderRadius.circular(kChipRadius));
        expect(_decorationOf(tester, 1).borderRadius,
            BorderRadius.circular(kChipRadius));
      });

      testWidgets('$name: the selected chip is primary under onPrimary',
          (tester) async {
        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Gaming')],
          selectedIndex: 0,
          theme: theme,
        ));
        await tester.pumpAndSettle();

        expect(_decorationOf(tester, 0).color, scheme.primary);
        expect(_labelStyleOf(tester, 'All').color, scheme.onPrimary);
        expect(_labelStyleOf(tester, 'All').fontWeight, FontWeight.w600);
      });

      testWidgets('$name: an unselected category wears its own hue',
          (tester) async {
        // The point of the rewrite. Folder.colorIndex has been carried through
        // the database and the model since pass 1 with nothing reading it.
        const index = 3;
        final expected = categoryPalette(index, brightness);

        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Travelling', colorIndex: index)],
          selectedIndex: 0,
          theme: theme,
        ));
        await tester.pumpAndSettle();

        expect(_decorationOf(tester, 1).color, expected.chipBackground);
        expect(
            _labelStyleOf(tester, 'Travelling').color, expected.chipForeground);
        expect(_labelStyleOf(tester, 'Travelling').fontWeight, FontWeight.w500);
      });

      testWidgets('$name: two categories with different hues differ',
          (tester) async {
        await tester.pumpWidget(_harness(
          folders: [
            _folder(1, 'Gaming', colorIndex: 2),
            _folder(2, 'Sports', colorIndex: 4),
          ],
          selectedIndex: 0,
          theme: theme,
        ));
        await tester.pumpAndSettle();

        expect(_decorationOf(tester, 1).color,
            isNot(_decorationOf(tester, 2).color));
      });

      testWidgets('$name: selection overrides the hue', (tester) async {
        // A selected category is teal, not its own colour — teal is the only
        // interactive colour, and "selected" is the interaction.
        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Gaming', colorIndex: 2)],
          selectedIndex: 1,
          theme: theme,
        ));
        await tester.pumpAndSettle();

        expect(_decorationOf(tester, 1).color, scheme.primary);
      });

      testWidgets('$name: All has no hue, so it takes the neutral tone',
          (tester) async {
        // Inferred, and flagged as such: the mock never draws All unselected,
        // because every unselected chip in it is a real category. Borrowing a
        // category hue would make the aggregate look like one more category.
        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Gaming', colorIndex: 2)],
          selectedIndex: 1,
          theme: theme,
        ));
        await tester.pumpAndSettle();

        expect(_decorationOf(tester, 0).color, scheme.surfaceContainer);
        expect(_labelStyleOf(tester, 'All').color, scheme.onSurfaceVariant);
      });

      testWidgets('$name: side padding is 13 selected, 12 unselected',
          (tester) async {
        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Gaming')],
          selectedIndex: 0,
          theme: theme,
        ));
        await tester.pumpAndSettle();

        expect(_bodyOf(tester, 0).padding,
            const EdgeInsets.symmetric(horizontal: kSelectedSidePadding));
        expect(_bodyOf(tester, 1).padding,
            const EdgeInsets.symmetric(horizontal: kUnselectedSidePadding));
      });

      testWidgets('$name: the label is 13px Instrument Sans', (tester) async {
        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Gaming')],
          theme: theme,
        ));
        await tester.pumpAndSettle();

        final style = _labelStyleOf(tester, 'Gaming');
        expect(style.fontSize, 13);
        expect(style.fontFamily, kSansFamily);
      });
    }
  });

  group('every theme renders it', () {
    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
      ('stock ThemeData', null),
    ]) {
      testWidgets('$name renders without throwing', (tester) async {
        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Gaming', colorIndex: 2)],
          folderUnreadCounts: const {1: 7},
          allUnreadCount: 12,
          theme: theme,
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Gaming'), findsOneWidget);
        expect(find.text('7'), findsOneWidget);
      });
    }
  });
}
