// FlashColors has to resolve from any theme, including Newspaper's.
//
// The bug this pins reached the branch in pass 1 and was invisible until pass 2
// widened the blast radius. `FlashColors` is a ThemeExtension registered by
// `flashQuietInkTheme`, and the call sites read it as
// `theme.extension<FlashColors>()!` — a null check. Two themes in this app do
// not carry it:
//
//   * `flashNewspaperTheme()`, which registers no extensions at all. Newspaper
//     mode is a first-class setting, so every widget reading the extension
//     crashed the moment the user turned it on. The article card's read-title
//     colour, added in pass 1, was already in that position.
//   * any stock `ThemeData` — a widget test that pumps `MaterialApp()` with no
//     `theme:`, which is most of them.
//
// A crash is the worst possible failure for a colour lookup, so `flashColors`
// falls back instead of throwing, and Newspaper registers its own ink so it
// gets newsprint greys rather than a generic fallback.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart';
import 'package:flash/widgets/article_detail_pane.dart';

Article _article({bool isRead = false}) => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: 'A headline',
      url: 'https://example.com/1',
      publishedAt: DateTime.now().millisecondsSinceEpoch,
      fetchedAt: 0,
      isRead: isRead,
      feedTitle: 'Example Feed',
    );

Future<void> _pump(WidgetTester tester, ThemeData? theme, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: ListView(children: [child])),
  ));
  await tester.pump();
}

void main() {
  group('every theme resolves the ink roles', () {
    test('Quiet Ink carries the extension outright', () {
      for (final b in Brightness.values) {
        expect(flashQuietInkTheme(brightness: b).extension<FlashColors>(),
            isNotNull);
      }
    });

    test('Newspaper carries one of its own', () {
      // Not the Quiet Ink values — newsprint is a different palette, and an
      // ink role borrowed from the teal theme would read as a bug on paper.
      final paper = flashNewspaperTheme();
      final ink = paper.extension<FlashColors>();
      expect(ink, isNotNull,
          reason: 'Newspaper mode is a setting a user can turn on; a widget '
              'that reads the extension must not crash there');
      expect(
          ink!.onSurfaceMuted,
          isNot(flashQuietInkTheme(brightness: Brightness.light)
              .extension<FlashColors>()!
              .onSurfaceMuted));
    });

    test('a stock ThemeData falls back rather than throwing', () {
      // Most widget tests pump MaterialApp() with no theme:. Before this,
      // every one of them that touched a converted widget died on a null
      // check — which is how pass 2 found the Newspaper bug.
      expect(() => ThemeData().flashColors, returnsNormally);
      expect(() => ThemeData.dark().flashColors, returnsNormally);
    });

    test('the fallback still gives three distinct, usable levels', () {
      for (final base in [ThemeData(), ThemeData.dark()]) {
        final ink = base.flashColors;
        expect({ink.onSurfaceMuted, ink.onSurfaceRead, ink.placeholder},
            hasLength(3));
        expect(ink.brightness, base.brightness);
      }
    });

    test('flashColors prefers a registered extension over the fallback', () {
      final theme = flashQuietInkTheme(brightness: Brightness.light);
      expect(theme.flashColors, same(theme.extension<FlashColors>()));
    });
  });

  group('widgets that read the roles survive every theme', () {
    // The regression, end to end. Each of these paints via FlashColors.
    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
      ('stock ThemeData', ThemeData()),
    ]) {
      testWidgets('$name: an article card renders', (tester) async {
        await _pump(
          tester,
          theme,
          ArticleCard(
            article: _article(isRead: true),
            onTap: () {},
            onMarkRead: () {},
            onMarkUnread: () {},
            onShare: () {},
            onBookmark: () {},
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('A headline'), findsOneWidget);
      });

      testWidgets('$name: the empty reading pane renders', (tester) async {
        await _pump(tester, theme, const ArticleDetailPlaceholder());
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the ink hierarchy never inverts', () {
    // What "read is quieter than unread, but still louder than a timestamp"
    // means numerically, and why it is not "read is darker than muted".
    //
    // Darkness is the wrong measure because it flips with the theme. In Quiet
    // Ink light the read title is #79817F against muted's #8A9391 — darker. In
    // Quiet Ink dark it is #87908F against #767F7E — *lighter*. Both are
    // correct: what actually holds in both is that the read title stands
    // further from the page than the timestamp does. So the invariant is
    // contrast against `surface`, and asserting darkness would have passed in
    // light and failed in dark for a theme that was right all along.
    //
    // This exists because Newspaper got it backwards. Its two levels were
    // lerped at 0.45 and 0.50, which put muted at #7D7C7A and read at #888785
    // — a read title lighter than the timestamp under it, in the one theme
    // nobody looks at twice. Nothing caught it, because nothing compared them.

    double luminance(Color c) {
      double channel(double v) {
        final s = v / 255.0;
        return s <= 0.03928
            ? s / 12.92
            : math.pow((s + 0.055) / 1.055, 2.4) as double;
      }

      return 0.2126 * channel((c.r * 255).roundToDouble()) +
          0.7152 * channel((c.g * 255).roundToDouble()) +
          0.0722 * channel((c.b * 255).roundToDouble());
    }

    double contrast(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final (name, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
    ]) {
      test('$name: a read title outranks a timestamp', () {
        final ink = theme.flashColors;
        final surface = theme.colorScheme.surface;

        final read = contrast(ink.onSurfaceRead, surface);
        final muted = contrast(ink.onSurfaceMuted, surface);

        expect(read, greaterThan(muted),
            reason: '$name puts the read title at '
                '${read.toStringAsFixed(2)}:1 against the page and the '
                'timestamp at ${muted.toStringAsFixed(2)}:1. A read article '
                'is still an article; its title cannot recede behind its own '
                'metadata.');
      });
    }

    test('the fallback DOES invert, and that is not fixed here', () {
      // Flagged rather than corrected, because it was not in scope and the
      // brief cites this pair as the reference the Newspaper fix was matched
      // to. `_fallbackFlashColors` blends muted at 0.5 and read at 0.55
      // toward the surface, and further toward the surface means *less*
      // contrast — so read comes out quieter than muted, exactly the fault
      // just corrected in Newspaper.
      //
      // No user sees it: the fallback is only reached by a theme carrying no
      // FlashColors, which in practice means a stock ThemeData in a widget
      // test. Production themes all register their own.
      //
      // The fix is one character, muted 0.5 -> 0.62, mirroring Newspaper.
      // This test fails when someone makes it, which is the point: at that
      // moment this block moves up into the loop above and the comment goes.
      for (final base in [ThemeData(), ThemeData.dark()]) {
        final ink = base.flashColors;
        final surface = base.colorScheme.surface;
        expect(contrast(ink.onSurfaceRead, surface),
            lessThan(contrast(ink.onSurfaceMuted, surface)),
            reason: 'a known inversion, awaiting a decision — not a pass');
      }
    });
  });

  group('the saved rail takes a role, not the accent', () {
    test('Newspaper does not fill it red', () {
      // _npRed is already the nav selection, the FAB, the switch and the
      // masthead tint. A red block on every saved card competes with all of
      // them and distinguishes nothing.
      final theme = flashNewspaperTheme();
      final ink = theme.flashColors;
      expect(ink.savedFill, isNot(theme.colorScheme.secondary));
      expect(ink.savedFill, isNot(theme.colorScheme.primary));
    });

    test('Quiet Ink fills it with the unread orange', () {
      // Here the accent IS right: orange appears nowhere else in a resting
      // feed, so a saved card is scannable down the column.
      for (final b in Brightness.values) {
        final theme = flashQuietInkTheme(brightness: b);
        expect(theme.flashColors.savedFill, theme.colorScheme.secondary);
      }
    });

    test('every theme keeps a legible glyph on the saved fill', () {
      double luminance(Color c) {
        double channel(double v) {
          final s = v / 255.0;
          return s <= 0.03928
              ? s / 12.92
              : math.pow((s + 0.055) / 1.055, 2.4) as double;
        }

        return 0.2126 * channel((c.r * 255).roundToDouble()) +
            0.7152 * channel((c.g * 255).roundToDouble()) +
            0.0722 * channel((c.b * 255).roundToDouble());
      }

      for (final (name, theme) in [
        ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
        ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
        ('Newspaper', flashNewspaperTheme()),
      ]) {
        final ink = theme.flashColors;
        final la = luminance(ink.savedFill);
        final lb = luminance(ink.onSavedFill);
        final ratio = (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5),
            reason: '$name paints the saved glyph at '
                '${ratio.toStringAsFixed(2)}:1 — this is the pair that was '
                '4.12:1 before the glyph moved off onSecondary');
      }
    });
  });
}
