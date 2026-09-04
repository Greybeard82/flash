// FolderTabBar sizing tests.
//
// Written independently of the implementation. PRD §5.2 mandates a 48×48dp
// minimum tap target; the shipped tab bar was a 48dp-tall strip whose tappable
// Column sat inside it with a 3dp indicator and 6dp gap eating the height, so
// the real target was well under spec and awkward to hit one-handed.
//
// Covered behaviours:
//  1. The bar reports its height via a public constant (so the FAB offset in
//     FeedScreen can reference it instead of a hardcoded 48.0)
//  2. Every tab meets the 48dp minimum on both axes, with headroom on height
//  3. Short folder names still produce a wide-enough target
//  4. Tapping a tab reports the right index
//  5. Unread counts render inline with the label, and hide entirely at zero

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/folder.dart';
import 'package:flash/widgets/folder_tab_bar.dart';

Folder _folder(int id, String name) =>
    Folder(id: id, name: name, position: id, createdAt: 0);

Widget _harness({
  required List<Folder> folders,
  int selectedIndex = 0,
  Map<int, int> folderUnreadCounts = const {},
  int allUnreadCount = 0,
  ValueChanged<int>? onTabSelected,
}) {
  return MaterialApp(
    locale: const Locale('en'),
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
          ),
        ],
      ),
    ),
  );
}

void main() {
  group('bar height', () {
    test('exposes a public height constant of at least 56dp', () {
      expect(FolderTabBar.barHeight, greaterThanOrEqualTo(56.0));
    });

    testWidgets('renders at the declared height', (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
      ));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(FolderTabBar));
      expect(size.height, FolderTabBar.barHeight);
    });
  });

  group('tap targets', () {
    testWidgets('every tab meets the 48dp minimum on both axes',
        (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech'), _folder(3, 'UK')],
      ));
      await tester.pumpAndSettle();

      // Tabs are keyed folder_tab_0 (All), folder_tab_1..n.
      for (var i = 0; i <= 3; i++) {
        final finder = find.byKey(ValueKey('folder_tab_$i'));
        expect(finder, findsOneWidget, reason: 'tab $i should exist');
        final size = tester.getSize(finder);
        expect(size.height, greaterThanOrEqualTo(48.0),
            reason: 'tab $i height');
        expect(size.width, greaterThanOrEqualTo(48.0),
            reason: 'tab $i width');
      }
    });

    testWidgets('a two-character folder name still gets a wide target',
        (tester) async {
      await tester.pumpWidget(_harness(folders: [_folder(1, 'UK')]));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byKey(const ValueKey('folder_tab_1')));
      expect(size.width, greaterThanOrEqualTo(72.0),
          reason: 'minWidth should be comfortable, not just legal');
    });

    testWidgets('tabs are taller than the previous 48dp bar', (tester) async {
      await tester.pumpWidget(_harness(folders: [_folder(1, 'Gaming')]));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byKey(const ValueKey('folder_tab_0')));
      expect(size.height, greaterThan(48.0));
    });
  });

  group('interaction', () {
    testWidgets('tapping a folder tab reports its index', (tester) async {
      int? tapped;
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        onTabSelected: (i) => tapped = i,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('folder_tab_2')));
      await tester.pumpAndSettle();

      expect(tapped, 2, reason: 'index 0 is All, so Tech is index 2');
    });

    testWidgets('tapping the already-selected tab still reports it',
        (tester) async {
      int? tapped;
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        selectedIndex: 0,
        onTabSelected: (i) => tapped = i,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('folder_tab_0')));
      await tester.pumpAndSettle();

      expect(tapped, 0);
    });
  });

  group('unread counts', () {
    testWidgets('renders inline with the label, in parentheses',
        (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        folderUnreadCounts: const {1: 7},
        allUnreadCount: 12,
      ));
      await tester.pumpAndSettle();

      // One Text widget per tab now, not a label plus a separate badge —
      // the fixed-width slot that could re-skin without shifting anything is
      // gone along with the badge; the count lives inside the label's own
      // Text, in the label's own colour, so it can never lose contrast
      // against its own chip fill the way a same-colour badge pill could.
      expect(find.text('Gaming (7)'), findsOneWidget);
      expect(find.text('All (12)'), findsOneWidget);
    });

    testWidgets('hidden entirely at zero, not shown as "(0)"', (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        folderUnreadCounts: const {1: 0},
        allUnreadCount: 0,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Gaming'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.textContaining('(0)'), findsNothing);
    });
  });
}
