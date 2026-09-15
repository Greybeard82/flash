// The chip a person just made has to be ON SCREEN.
//
// **This is the bug, not the fix for it.** The article list was rebuilding
// correctly the whole time: create a category and the chip appeared
// immediately, at the far right of a horizontally scrolling strip, past the
// fold, with nothing to say the strip scrolls. Three chips fit before the
// edge on a tablet and about three and a half on a phone. The user's report
// was "the category disappeared"; the data was perfect and the chip was
// eleven hundred pixels to the right.
//
// `FolderTabBar` already had `_scrollToSelected`. It had never worked for
// this case and could not have, for two reasons that are each enough on
// their own:
//
//   1. **`didUpdateWidget` watched only `selectedIndex`.** The folder list
//      was not in the condition, so a bar that grew a chip was not a reason
//      to scroll anywhere.
//   2. **`didUpdateWidget` runs before `build`.** `_tabKeys` is populated
//      inside `build` by `_keyFor`, so for a chip that has just appeared the
//      lookup returns null, `Scrollable.ensureVisible` is never called, and
//      the method returns having done nothing — silently, past a guard that
//      reads like a defensive null check rather than the thing that swallows
//      the whole feature.
//
// Both are pinned below by driving the real widget and reading the real
// scroll offset, because both failure modes leave source that looks right.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/folder_tab_bar.dart';

Folder _folder(int id, String name) =>
    Folder(id: id, name: name, position: id, createdAt: 0, colorIndex: id % 6);

/// Six categories, which is what David's library actually holds and roughly
/// twice what fits across a phone.
List<Folder> _sixFolders() => [
      _folder(1, 'World News'),
      _folder(2, 'Tech'),
      _folder(3, 'Fitness'),
      _folder(4, 'Travelling'),
      _folder(5, 'Gaming'),
      _folder(6, 'Science'),
    ];

Widget _harness({
  required List<Folder> folders,
  required int selectedIndex,
  double width = 400,
}) =>
    MaterialApp(
      locale: const Locale('en'),
      theme: flashQuietInkTheme(brightness: Brightness.light),
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
            selectedIndex: selectedIndex,
            folderUnreadCounts: const {},
            allUnreadCount: 0,
            onTabSelected: (_) {},
          ),
        ),
        body: SizedBox(width: width),
      ),
    );

double _offset(WidgetTester tester) => tester
    .widget<SingleChildScrollView>(find.descendant(
      of: find.byType(FolderTabBar),
      matching: find.byType(SingleChildScrollView),
    ))
    .controller!
    .offset;

void main() {
  group('a newly created category is brought into view', () {
    testWidgets('the bar scrolls when a chip is appended and selected',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final folders = _sixFolders();
      await tester.pumpWidget(_harness(folders: folders, selectedIndex: 0));
      await tester.pumpAndSettle();

      expect(_offset(tester), 0,
          reason: 'the strip opens at the left, which is the whole problem');

      // The new category, appended at the end the way FolderRepository does
      // it, and selected the way the article list now does.
      await tester.pumpWidget(_harness(
        folders: [...folders, _folder(7, 'Cycling')],
        selectedIndex: 7,
      ));
      await tester.pumpAndSettle();

      expect(_offset(tester), greaterThan(0),
          reason: 'this is the assertion the old implementation failed: the '
              'chip existed, the selection was right, and the strip had not '
              'moved a pixel');
      expect(find.text('Cycling'), findsOneWidget);
    });

    testWidgets('the new chip is actually inside the viewport afterwards',
        (tester) async {
      // Not the same claim as "the offset changed". Reading the chip's
      // painted rectangle is what says a person can see it.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final folders = _sixFolders();
      await tester.pumpWidget(_harness(folders: folders, selectedIndex: 0));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_harness(
        folders: [...folders, _folder(7, 'Cycling')],
        selectedIndex: 7,
      ));
      await tester.pumpAndSettle();

      final chip = tester.getRect(find.text('Cycling'));
      final viewport = tester.getRect(find.descendant(
        of: find.byType(FolderTabBar),
        matching: find.byType(SingleChildScrollView),
      ));
      expect(chip.left, greaterThanOrEqualTo(viewport.left - 0.5));
      expect(chip.right, lessThanOrEqualTo(viewport.right + 0.5));
    });

    testWidgets('it scrolls even when the selected INDEX does not change',
        (tester) async {
      // The case a condition watching only selectedIndex cannot see. The user
      // is on the last category; a new one is inserted before it, so the
      // selection follows the folder to a new index -- or, as here, the index
      // stays put while the chip under it changes identity and position.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final folders = _sixFolders();
      await tester.pumpWidget(_harness(folders: folders, selectedIndex: 6));
      await tester.pumpAndSettle();
      final before = _offset(tester);

      await tester.pumpWidget(_harness(
        folders: [
          ...folders.take(5),
          _folder(7, 'Cycling'),
          folders.last,
        ],
        selectedIndex: 6,
      ));
      await tester.pumpAndSettle();

      expect(_offset(tester), isNot(before),
          reason: 'the chip at index 6 is a different category now, and the '
              'old condition would not have looked');
    });
  });

  group('what it must not do', () {
    testWidgets('a bar that fits does not scroll at all', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Tech')],
        selectedIndex: 1,
      ));
      await tester.pumpAndSettle();
      expect(_offset(tester), 0);
    });

    testWidgets('disposing mid-animation does not throw', (tester) async {
      // The scroll is deferred to a post-frame callback now, so the widget
      // can be gone by the time it runs. Without the mounted check this is
      // an exception in a callback nobody is catching.
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final folders = _sixFolders();
      await tester.pumpWidget(_harness(folders: folders, selectedIndex: 0));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_harness(
        folders: [...folders, _folder(7, 'Cycling')],
        selectedIndex: 7,
      ));
      // One frame only, so the post-frame callback is queued but the
      // animation has not run, and then the bar is torn down under it.
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
