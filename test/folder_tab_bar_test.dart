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
//  5. Unread badges still render alongside the label

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

  group('badges', () {
    testWidgets('shows the unread count next to the folder label',
        (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        folderUnreadCounts: const {1: 7},
        allUnreadCount: 12,
      ));
      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('hides the badge at zero', (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming')],
        folderUnreadCounts: const {1: 0},
        allUnreadCount: 0,
      ));
      await tester.pumpAndSettle();

      // The badge container stays mounted at count zero (see UnreadBadge:
      // it self-manages visibility via AnimatedOpacity rather than being
      // swapped out, so a later count update never has to destroy/recreate
      // it) — so assert it's invisible rather than absent from the tree.
      for (final opacity in tester.widgetList<AnimatedOpacity>(
          find.byType(AnimatedOpacity))) {
        expect(opacity.opacity, 0.0);
      }
    });
  });

  // A live-updating count (including from a tab the user isn't viewing)
  // must never shift this tab's own label, or — since tabs share one Row —
  // every tab laid out after it.
  group('no layout shift on count change', () {
    Offset labelPos(WidgetTester tester, String label) =>
        tester.getTopLeft(find.text(label));

    testWidgets('label position is identical at 1, 2, and 3 digits',
        (tester) async {
      final positions = <int, Offset>{};
      for (final count in [1, 12, 123]) {
        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
          folderUnreadCounts: {1: count},
        ));
        await tester.pumpAndSettle();
        positions[count] = labelPos(tester, 'Gaming');
      }

      expect(positions[12], positions[1],
          reason: '1 → 2 digits must not move the label');
      expect(positions[123], positions[1],
          reason: '1 → 3 digits must not move the label');
    });

    testWidgets('a downstream sibling tab does not shift when an '
        'earlier tab\'s digit count changes', (tester) async {
      final positions = <int, Offset>{};
      for (final count in [1, 12, 123]) {
        await tester.pumpWidget(_harness(
          folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
          folderUnreadCounts: {1: count},
        ));
        await tester.pumpAndSettle();
        positions[count] = labelPos(tester, 'Tech');
      }

      expect(positions[12], positions[1],
          reason: 'Gaming growing to 2 digits must not push Tech sideways');
      expect(positions[123], positions[1],
          reason: 'Gaming growing to 3 digits must not push Tech sideways');
    });

    testWidgets('no shift crossing the 9 → 10 digit-bucket boundary',
        (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        folderUnreadCounts: const {1: 9},
      ));
      await tester.pumpAndSettle();
      final before = labelPos(tester, 'Tech');

      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        folderUnreadCounts: const {1: 10},
      ));
      await tester.pumpAndSettle();
      final after = labelPos(tester, 'Tech');

      expect(after, before);
    });

    testWidgets('no shift crossing the 99 → 100 digit-bucket boundary',
        (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        folderUnreadCounts: const {1: 99},
      ));
      await tester.pumpAndSettle();
      final before = labelPos(tester, 'Tech');

      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        folderUnreadCounts: const {1: 100},
      ));
      await tester.pumpAndSettle();
      final after = labelPos(tester, 'Tech');

      expect(after, before);
    });

    testWidgets(
        'no shift crossing the 999 → 1000 boundary into the "999+" cap',
        (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        folderUnreadCounts: const {1: 999},
      ));
      await tester.pumpAndSettle();
      final before = labelPos(tester, 'Tech');
      expect(find.text('999'), findsOneWidget);

      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        folderUnreadCounts: const {1: 1000},
      ));
      await tester.pumpAndSettle();
      final after = labelPos(tester, 'Tech');
      expect(find.text('999+'), findsOneWidget);

      expect(after, before);
    });

    testWidgets(
        'the slot is reserved even at zero — a badge appearing does not '
        'shift the label', (tester) async {
      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        folderUnreadCounts: const {1: 0},
      ));
      await tester.pumpAndSettle();
      final before = labelPos(tester, 'Tech');

      await tester.pumpWidget(_harness(
        folders: [_folder(1, 'Gaming'), _folder(2, 'Tech')],
        folderUnreadCounts: const {1: 5},
      ));
      await tester.pumpAndSettle();
      final after = labelPos(tester, 'Tech');

      expect(after, before,
          reason: 'The badge slot is reserved at zero specifically so it '
              'appearing/disappearing never shifts sibling tabs.');
    });
  });
}
