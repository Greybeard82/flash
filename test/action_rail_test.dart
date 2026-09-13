// The card's right edge carries two controls now, not one.
//
// Pass 3 splits `_SummaryButton` into a two-half rail: AI summary on top,
// bookmark underneath. The card's outer geometry does not move — the rail
// keeps the same 40x72 footprint it had as a single button — so everything
// this file pins is *inside* that box.
//
// **Why the heights are asserted as numbers.** The split costs target size,
// and that is the whole risk of the change. One 40x72 button became two
// 40x36 ones, so each half is 1440dp² against the 2304dp² of the 48dp square
// this app holds itself to elsewhere, and it is now under the minimum on both
// axes rather than just one. Worse, a mis-tap no longer does nothing: aiming
// for summary and hitting save is a visible, wrong outcome the user then has
// to undo. That was accepted as a product decision, but it means any later
// layout edit that shaves a few dp off either half makes a known-marginal
// target worse without anybody noticing. Hence exact numbers, not ranges.
//
// **Why the halves must meet.** The 2dp gap between them is painted, not
// laid out: the two touch boxes are 36dp each and share an edge at y=36, and
// the gap comes from aligning a 35dp painted block to the top of the upper
// box and the bottom of the lower one. If the gap were a real SizedBox it
// would be 2dp of dead pixels sitting exactly where a user aiming at the
// boundary between two already-small targets is most likely to land.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart';

/// The geometry this pass must not change, measured on the card before it.
const Size _cardSizeBefore = Size(1080, 92);
const Size _railSizeBefore = Size(40, 72);

/// The heights settled on for this pass. Equal halves.
const double _summaryTouchHeight = 36;
const double _saveTouchHeight = 36;

Article _article({bool isSaved = false, bool isRead = false}) => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: 'A headline that wraps across two lines in the card body',
      url: 'https://example.com/1',
      publishedAt: DateTime.now().millisecondsSinceEpoch,
      fetchedAt: 0,
      isRead: isRead,
      isSaved: isSaved,
      feedTitle: 'Example Feed',
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool isSaved,
  ThemeData? theme,
  VoidCallback? onBookmark,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: theme ?? flashQuietInkTheme(brightness: Brightness.light),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: ListView(children: [
        ArticleCard(
          article: _article(isSaved: isSaved),
          onTap: () {},
          onMarkRead: () {},
          onMarkUnread: () {},
          onShare: () {},
          onBookmark: onBookmark ?? () {},
        ),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The painted block inside one half — the thing that carries the fill.
Finder _paintedOf(Finder half) =>
    find.descendant(of: half, matching: find.byType(Material));

Color _fillOf(WidgetTester tester, Finder half) =>
    tester.widget<Material>(_paintedOf(half).first).color!;

Finder _summaryHalf() => find.byTooltip('Summary');
Finder _saveHalf({required bool isSaved}) =>
    find.byTooltip(isSaved ? 'Saved' : 'Bookmark');

void main() {
  group('the save half paints the state it is in', () {
    for (final brightness in Brightness.values) {
      final theme = flashQuietInkTheme(brightness: brightness);
      final scheme = theme.colorScheme;
      final name = brightness.name;

      testWidgets('$name: not saved is the teal tint with a neutral glyph',
          (tester) async {
        await _pump(tester, isSaved: false, theme: theme);

        expect(
            _fillOf(tester, _saveHalf(isSaved: false)), scheme.primaryContainer,
            reason: '$name: an unsaved save button is the same tint as the '
                'summary half above it — the rail reads as one control');

        final icon = tester.widget<Icon>(find.descendant(
          of: _saveHalf(isSaved: false),
          matching: find.byIcon(Icons.bookmark_border_rounded),
        ));
        expect(icon.color, scheme.onSurfaceVariant,
            reason: '$name: the unsaved glyph is neutral, not teal — it is '
                'the one thing distinguishing the two halves at rest');
      });

      testWidgets('$name: saved fills with the accent', (tester) async {
        await _pump(tester, isSaved: true, theme: theme);

        expect(_fillOf(tester, _saveHalf(isSaved: true)), scheme.secondary,
            reason: '$name: a saved article is scannable down the column');

        final icon = tester.widget<Icon>(find.descendant(
          of: _saveHalf(isSaved: true),
          matching: find.byIcon(Icons.bookmark_rounded),
        ));
        expect(icon.color, scheme.onSecondary);
      });

      testWidgets('$name: the summary half is untouched by save state',
          (tester) async {
        for (final saved in [false, true]) {
          await _pump(tester, isSaved: saved, theme: theme);
          expect(_fillOf(tester, _summaryHalf()), scheme.primaryContainer,
              reason: 'saving an article must not restyle the summary button');
        }
      });
    }
  });

  group('the icons are the radial menu\'s, exactly', () {
    // Reused rather than re-chosen: the radial menu already renders these two
    // for the same action, and a card offering a different bookmark glyph
    // from the menu that bookmarks the same article is a bug in waiting.
    testWidgets('unsaved uses the outline', (tester) async {
      await _pump(tester, isSaved: false);
      expect(
          find.descendant(
              of: _saveHalf(isSaved: false),
              matching: find.byIcon(Icons.bookmark_border_rounded)),
          findsOneWidget);
    });

    testWidgets('saved uses the filled', (tester) async {
      await _pump(tester, isSaved: true);
      expect(
          find.descendant(
              of: _saveHalf(isSaved: true),
              matching: find.byIcon(Icons.bookmark_rounded)),
          findsOneWidget);
    });
  });

  group('tapping the right half does the right thing', () {
    testWidgets('the save half fires onBookmark exactly once', (tester) async {
      var calls = 0;
      await _pump(tester, isSaved: false, onBookmark: () => calls++);

      await tester.tap(_saveHalf(isSaved: false));
      await tester.pumpAndSettle();

      expect(calls, 1,
          reason: 'the painted InkWell and the outer touch box must not both '
              'claim the same tap');
    });

    testWidgets('the summary half does not fire onBookmark', (tester) async {
      var calls = 0;
      await _pump(tester, isSaved: false, onBookmark: () => calls++);

      await tester.tap(_summaryHalf());
      await tester.pumpAndSettle();

      expect(calls, 0,
          reason: 'this is the mis-tap the split makes possible; the two '
              'halves must not overlap');
    });

    testWidgets('a tap in the top half of the save box still saves',
        (tester) async {
      // The dead-pixel check, expressed as a gesture. This lands 1dp below
      // the boundary, inside the painted gap, where the save touch box
      // extends above its own painted block.
      var calls = 0;
      await _pump(tester, isSaved: false, onBookmark: () => calls++);

      final rect = tester.getRect(_saveHalf(isSaved: false));
      await tester.tapAt(Offset(rect.center.dx, rect.top + 1));
      await tester.pumpAndSettle();

      expect(calls, 1,
          reason: 'the 2dp gap is painted, not laid out — no tap may fall '
              'between the halves');
    });
  });

  group('geometry', () {
    testWidgets('each half has the touch height it was given', (tester) async {
      await _pump(tester, isSaved: false);

      expect(tester.getSize(_summaryHalf()).height, _summaryTouchHeight);
      expect(
          tester.getSize(_saveHalf(isSaved: false)).height, _saveTouchHeight);
      expect(tester.getSize(_summaryHalf()).width, _railSizeBefore.width);
      expect(tester.getSize(_saveHalf(isSaved: false)).width,
          _railSizeBefore.width);
    });

    testWidgets('the two touch boxes meet, with nothing between them',
        (tester) async {
      await _pump(tester, isSaved: false);

      final top = tester.getRect(_summaryHalf());
      final bottom = tester.getRect(_saveHalf(isSaved: false));

      expect(bottom.top, top.bottom,
          reason: 'a gap here would be dead pixels at the boundary between '
              'two already-marginal targets');
      expect(bottom.bottom - top.top, _railSizeBefore.height,
          reason: 'the two halves together still occupy the old rail');
    });

    testWidgets('the rail footprint is what it was before the split',
        (tester) async {
      for (final saved in [false, true]) {
        await _pump(tester, isSaved: saved);
        final top = tester.getRect(_summaryHalf());
        final bottom = tester.getRect(_saveHalf(isSaved: saved));
        expect(Size(top.width, bottom.bottom - top.top), _railSizeBefore);
      }
    });

    testWidgets('the card itself is exactly the size it was', (tester) async {
      // The measurement that proves the pass stayed inside the rail. Both
      // values were taken from the card before this change.
      for (final saved in [false, true]) {
        await _pump(tester, isSaved: saved);
        expect(tester.getSize(find.byType(ArticleCard)), _cardSizeBefore,
            reason: 'saved=$saved changed the card\'s outer geometry');
      }
    });
  });

  group('every theme renders both states', () {
    // The class of bug pass 2 built flash_colors_resolution_test.dart for.
    // Newspaper resolves `secondary` to its own red, which is a live design
    // question — but whatever it resolves to, it must not throw.
    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
      ('stock ThemeData', null),
    ]) {
      for (final saved in [false, true]) {
        testWidgets('$name renders with isSaved=$saved', (tester) async {
          await _pump(tester, isSaved: saved, theme: theme);
          expect(tester.takeException(), isNull);
          expect(_saveHalf(isSaved: saved), findsOneWidget);
        });
      }
    }
  });
}
