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
      // The fallback is in the loop now. It was the last inverted pair —
      // muted blended 0.5 toward the surface against read's 0.55, and further
      // toward the surface means less contrast, so read came out quieter than
      // muted. Fixed by moving muted to 0.62, mirroring Newspaper.
      ('the fallback, light', ThemeData()),
      ('the fallback, dark', ThemeData.dark()),
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
  });

  // **A group of three tests stood here and went with the two roles it
  // measured.** Recorded rather than silently dropped, because two of the
  // three were making claims that are still true of something else, and
  // one of them is now true in reverse:
  //
  //   1. `Newspaper does not fill it red` — `savedFill` was
  //      `_npInk`, on the argument that `_npRed` is already the nav
  //      selection, the FAB, the switch and the masthead, so a red block
  //      on every saved card competes with all of them. **That argument
  //      was overturned by measurement, not by this deletion.**
  //      Newspaper's `onSurfaceVariant` and its `_npInk` are the same
  //      `#1D1D1B`, so an ink saved GLYPH would be pixel-identical to an
  //      unsaved one and colour would become actively misleading rather
  //      than merely weak. Newspaper's saved glyph is `_npRed`, and the
  //      claim this test made is now inverted.
  //   2. `Quiet Ink fills it with the unread orange` — still true
  //      of the glyph. `batch4_ink_test.dart` holds that claim.
  //   3. `every theme keeps a legible glyph on the saved fill` — a
  //      4.5:1 check of `onSavedFill` against `savedFill`. Replaced by
  //      `summary_button_contrast_test.dart`, which measures the glyph
  //      against the tint it is actually painted on and holds it to WCAG
  //      1.4.11's 3:1 rather than the text bar: 3.36 / 6.88 / 5.97.
  //
  // Nothing here needs rebuilding. Every pair is measured where it is
  // painted now, which is what made the roles removable in the first
  // place.


  group('every ink role used for text clears 4.5:1 on its own surface', () {
    // The test that should have existed before Newspaper's ink levels were
    // chosen, and the reason it exists now.
    //
    // `onSurfaceMuted` and `onSurfaceRead` were set to lerp 0.62 and 0.55 to
    // correct an inverted hierarchy — muted was coming out darker than read —
    // and the fix was checked against each other and never against paper. It
    // took them to 2.31:1 and 2.76:1, where body text needs 4.5. They are
    // 0.35 and 0.30 now, at 5.00:1 and 5.85:1.
    //
    // The instructive part is that the values were authored under a "changes
    // no pixel" guarantee, which was true. A promise that nothing moved is
    // also a promise that nothing was measured, and it is exactly the kind of
    // reassurance that stops a second look. So the guard is a ratio against
    // the theme's own surface, not a comparison between two roles.
    //
    // Only roles that carry **text** are here. `illustration`, `inert` and
    // `placeholder` are decoration, a disabled state and a fill; none is read
    // as words and WCAG's text minimum does not apply to them.

    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
    }

    /// Roles that are known to sit under the bar, with the ratio each one
    /// actually measures.
    ///
    /// Both are Design's authored Quiet Ink light values and both are
    /// deliberate — a timestamp and a read headline are meant to recede. They
    /// are pinned to their measured ratios rather than merely excluded, so a
    /// drift in either direction fails: quieter is a regression, louder means
    /// somebody changed a decision without saying so.
    const known = <String, double>{
      'Quiet Ink light onSurfaceMuted': 3.15,
      'Quiet Ink light onSurfaceRead': 3.99,
    };

    for (final (themeName, theme) in [
      ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
      ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ('Newspaper', flashNewspaperTheme()),
    ]) {
      final surface = theme.colorScheme.surface;
      final ink = theme.flashColors;

      final roles = <String, Color>{
        'onSurface': theme.colorScheme.onSurface,
        'onSurfaceVariant': theme.colorScheme.onSurfaceVariant,
        'onSurfaceMuted': ink.onSurfaceMuted,
        'onSurfaceRead': ink.onSurfaceRead,
      };

      roles.forEach((roleName, colour) {
        final label = '$themeName $roleName';
        final ratio = contrast(colour, surface);

        if (known.containsKey(label)) {
          test('$label is ${known[label]}:1 — a known, deliberate exception',
              () {
            expect(ratio, closeTo(known[label]!, 0.01),
                reason: '$label measures ${ratio.toStringAsFixed(2)}:1 '
                    'against an expected ${known[label]}. This role is '
                    'deliberately under the text bar, so the value is pinned: '
                    'if it dropped, that is a regression; if it rose, someone '
                    'changed an authored decision without recording it.');
            expect(ratio, lessThan(4.5),
                reason: 'kept explicit so this block is not misread as a pass');
          });
        } else {
          test('$label clears 4.5:1', () {
            expect(ratio, greaterThanOrEqualTo(4.5),
                reason: '$label reads ${ratio.toStringAsFixed(2)}:1 against '
                    'its own surface. Body text needs 4.5. If this role is '
                    'genuinely meant to recede, add it to `known` with its '
                    'measured ratio and a reason — do not lower the bar.');
          });
        }
      });
    }

    test('Newspaper is back above the bar on both ink levels', () {
      // Named separately because it is the regression this group was written
      // for, and because the numbers are worth being able to read directly.
      final theme = flashNewspaperTheme();
      final surface = theme.colorScheme.surface;

      expect(contrast(theme.flashColors.onSurfaceMuted, surface),
          closeTo(5.00, 0.02));
      expect(contrast(theme.flashColors.onSurfaceRead, surface),
          closeTo(5.85, 0.02));
    });

    test('the known-exception list is small, and only Quiet Ink light', () {
      // A tripwire on drift. Two entries is a decision; five would mean the
      // bar had quietly stopped being the bar.
      expect(known, hasLength(2));
      expect(known.keys.every((k) => k.startsWith('Quiet Ink light')), isTrue,
          reason: 'a second theme appearing here means the exception has '
              'spread rather than been decided');
    });

    test('decoration roles are deliberately not in this group', () {
      // Stated as an assertion so the omission reads as a decision. These
      // legitimately sit far below the text bar: an empty-state glyph, a
      // disabled control and a thumbnail fill are not words.
      for (final (name, theme) in [
        ('light', flashQuietInkTheme(brightness: Brightness.light)),
        ('dark', flashQuietInkTheme(brightness: Brightness.dark)),
      ]) {
        final ink = theme.flashColors;
        final surface = theme.colorScheme.surface;
        expect(contrast(ink.illustration, surface), lessThan(4.5),
            reason: '$name: if an illustration ever cleared the text bar it '
                'would no longer be receding, and this group would be the '
                'wrong place to find that out');
        expect(contrast(ink.inert, surface), lessThan(4.5));
      }
    });
  });
}
