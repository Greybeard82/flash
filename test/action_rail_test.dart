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
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flash/db/database.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/screens/article_summary_sheet.dart';
import 'package:flash/widgets/article_card.dart';

/// The rail's footprint, which is a real invariant: `_ActionRail` declares
/// itself `SizedBox(width: 40, height: 72)`, and the tests below assert the two
/// halves still sum to exactly that.
const Size _railSizeBefore = Size(40, 72);

// There was a `_cardSizeBefore = Size(1080, 92)` here. It was removed
// deliberately, and the reason is worth keeping.
//
// It was a snapshot, not an invariant. The card's height is declared nowhere —
// it falls out of the title font, its line height, the maxLines: 3 cap and the
// row padding — and 92 was measured on the pre-split card under
// `flutter_test`'s substitute font, where every glyph is a square of the font
// size. It was never the height the card has on a phone.
//
// So it was a tripwire with a misleading label: it would fire on any
// typography change while reporting "the card's outer geometry changed", when
// what changed was a font. It did its job for the pass that added it, whose
// whole claim was that the card did not move. As a standing assertion it is a
// future false positive.
//
// What replaced it asserts the actual claim — that changing an article's state
// does not resize its card — by comparing two cards in one run rather than one
// card against a number from a previous one. That survives a font change,
// which is the point.

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
  bool isRead = false,
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
          article: _article(isSaved: isSaved, isRead: isRead),
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

/// Loaded once in `setUpAll`, because the tooltips below are the ARB's to
/// decide and not this file's.
///
/// These finders used to carry the English literals, and pass 6 broke eight
/// tests at once by changing `saved` from "Saved" to "Bookmarks" — a strings
/// pass with no business touching the rail's geometry. Nothing here is
/// asserting what the tooltip says; every one of these tests is trying to
/// *reach* a half so it can measure or tap it, so the string is an address,
/// not a claim, and hardcoding an address that lives in another file is how a
/// copy edit ends up looking like a layout regression.
late AppLocalizations _l10n;

Finder _summaryHalf() => find.byTooltip(_l10n.summary);
Finder _saveHalf({required bool isSaved}) =>
    find.byTooltip(isSaved ? _l10n.saved : _l10n.bookmark);

void main() {
  // Tapping the summary half really does open the summary sheet, and the
  // sheet really does reach for the database on init. Standing one up is
  // cheaper than pretending the tap went somewhere else.
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.useForTesting();
    _l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

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

      testWidgets('$name: saved changes the glyph and nothing else',
          (tester) async {
        // **The fill no longer moves, and that is the assertion.** It used to
        // flip to `savedFill`, and the justification was that a saved article
        // should be scannable down the column — which is the Bookmarks
        // destination's job, one tap away, so the feed was paying a solid
        // orange block for work another screen already does.
        await _pump(tester, isSaved: true, theme: theme);

        expect(
            _fillOf(tester, _saveHalf(isSaved: true)), scheme.primaryContainer,
            reason: '$name: the block under the bookmark is the same teal '
                'tint whether or not the article is saved. A fill here is '
                'what was just removed.');

        final icon = tester.widget<Icon>(find.descendant(
          of: _saveHalf(isSaved: true),
          matching: find.byIcon(Icons.bookmark_rounded),
        ));
        expect(icon.color, scheme.secondary,
            reason: '$name: the saved signal is the glyph colour now');
        expect(icon.color, isNot(scheme.onSurfaceVariant),
            reason: '$name: saved and unsaved must not resolve to the same '
                'colour, or the shape swap is carrying the whole signal');
      });

      testWidgets('$name: the fill is identical in both states',
          (tester) async {
        // Measured across a state change rather than asserted twice against a
        // role, because the role could be changed in both places at once and
        // this still has to fail if the two ever diverge again.
        await _pump(tester, isSaved: false, theme: theme);
        final unsaved = _fillOf(tester, _saveHalf(isSaved: false));

        await _pump(tester, isSaved: true, theme: theme);
        final saved = _fillOf(tester, _saveHalf(isSaved: true));

        expect(saved, unsaved,
            reason: '$name: the saved state is a glyph, not a block');
      });

      testWidgets('$name: the shape swap survives, carrying half the signal',
          (tester) async {
        // It was decoration on top of a colour change while the fill existed.
        // With the fill gone it is one of exactly two things distinguishing
        // the states, so losing it would leave a colour-only distinction.
        await _pump(tester, isSaved: false, theme: theme);
        expect(
            find.descendant(
              of: _saveHalf(isSaved: false),
              matching: find.byIcon(Icons.bookmark_border_rounded),
            ),
            findsOneWidget);

        await _pump(tester, isSaved: true, theme: theme);
        expect(
            find.descendant(
              of: _saveHalf(isSaved: true),
              matching: find.byIcon(Icons.bookmark_rounded),
            ),
            findsOneWidget);
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(calls, 0,
          reason: 'this is the mis-tap the split makes possible; the two '
              'halves must not overlap');

      // The summary half does its own job on tap: it opens the summary
      // sheet, which reaches for a database this test has no reason to
      // stand up. That failure belongs to the sheet, not the rail, and is
      // drained here so it cannot be misread as a rail failure. It is also
      // the proof that the tap landed on summary rather than on nothing.
      // Proof the tap landed on summary rather than on nothing: the sheet
      // it opens is now on screen.
      expect(find.byType(ArticleSummarySheet), findsOneWidget,
          reason: 'the tap must actually have reached the summary half');
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

    testWidgets('saving an article does not resize its card', (tester) async {
      // The measurement that proves the split stayed inside the rail, stated
      // as the claim itself: the same card, in both states, in one run. No
      // hardcoded pixel height, so a typography change cannot make this fail
      // while blaming card geometry.
      await _pump(tester, isSaved: false);
      final unsaved = tester.getSize(find.byType(ArticleCard));

      await _pump(tester, isSaved: true);
      final saved = tester.getSize(find.byType(ArticleCard));

      expect(saved, unsaved,
          reason: 'the saved and unsaved cards are different sizes, so the '
              'rail is pushing on the row it lives in');
    });

    testWidgets('and neither does marking it read', (tester) async {
      // The same claim on the other state change, and the one with history:
      // read state used to alter the title weight, which reflowed a wrapped
      // title and slid every card below it mid-scroll.
      await _pump(tester, isSaved: false, isRead: false);
      final unread = tester.getSize(find.byType(ArticleCard));

      await _pump(tester, isSaved: false, isRead: true);
      final read = tester.getSize(find.byType(ArticleCard));

      expect(read, unread,
          reason: 'reading an article changed its card height — this is the '
              'mid-scroll reflow the read treatment is colour-only to avoid');
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
