// The clean view's type, which is the one change in pass 8 a test cannot
// really judge and can only stop from drifting.
//
// Handoff 3's restyle list: body in Literata at 17 / 1.62, h3 off the sans
// `titleMedium` onto Literata 17 / w700, captions staying sans.
//
// **1.62 is the reason this file exists.** It is a value that looks like a
// rounding artefact and is not one, and the failure mode is somebody tidying it
// to 1.6 in a cleanup commit where nobody is looking at a paragraph. At 17px
// that is 27.5 against 27.2 — nothing on one line, a third of a line over
// forty.
//
// Per the standing rule in the handoff, this asserts against the widget the app
// actually builds, with the blocks the extractor actually produces. The
// last group checks the app really does build it, because a beautifully
// verified reading view nothing renders is the shape of coverage without the
// substance.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/models/content_block.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/clean_article_view.dart';

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  List<ContentBlock> blocks,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: CleanArticleView(blocks: blocks)),
  ));
  await tester.pumpAndSettle();
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  final themes = <String, ThemeData>{
    'light': flashQuietInkTheme(brightness: Brightness.light),
    'dark': flashQuietInkTheme(brightness: Brightness.dark),
    'Newspaper': flashNewspaperTheme(),
  };

  test('the measure is 17 / 1.62, and 1.62 is not 1.6', () {
    // Pinned on the constants as well as on the render, because this is the
    // pair somebody edits. The second assertion is not redundant with the
    // first: it is there so the diff that changes 1.62 has to delete a line
    // that says out loud it is not 1.6.
    expect(kCleanBodySize, 17.0);
    expect(kCleanBodyHeight, 1.62);
    expect(kCleanBodyHeight, isNot(1.6),
        reason: 'if this is 1.6 the value was tidied, not decided');
  });

  themes.forEach((name, theme) {
    final serif = theme.textTheme.titleLarge!.fontFamily;

    group(name, () {
      testWidgets('body paragraphs read at 17 / 1.62 in the serif',
          (tester) async {
        await _pump(tester, theme, [ParagraphBlock('A paragraph of body copy')]);
        final style = _styleOf(tester, 'A paragraph of body copy');

        expect(style.fontSize, kCleanBodySize);
        expect(style.height, kCleanBodyHeight);
        expect(style.fontFamily, serif,
            reason: '$name: the reading face is this theme\'s serif — '
                'Literata in Quiet Ink, PT Serif in Newspaper. The family is '
                'taken from titleLarge rather than hardcoded, because '
                'hardcoding kSerifFamily would put Literata into Newspaper.');
      });

      testWidgets('$name: and the serif is not the operating face',
          (tester) async {
        // The assertion that catches the lazy version of this change, which
        // is to leave `bodyLarge` alone and only bump the size. In Quiet Ink
        // `bodyLarge` is Instrument Sans; in Newspaper it happens to be the
        // serif already, so this is a no-op there and says so.
        if (name == 'Newspaper') {
          expect(serif, theme.textTheme.bodyLarge?.fontFamily,
              reason: 'Newspaper operates and reads in the same face, so '
                  'there is nothing for this test to catch here');
          return;
        }
        expect(serif, isNot(theme.textTheme.bodyLarge?.fontFamily),
            reason: '$name: if these are the same, the clean view could be '
                'reading bodyLarge and passing by accident');
      });

      testWidgets('h3 is the reading face at body size, w700', (tester) async {
        await _pump(tester, theme, [HeadingBlock(3, 'A third-level heading')]);
        final style = _styleOf(tester, 'A third-level heading');

        expect(style.fontFamily, serif,
            reason: '$name: h3 was titleMedium, the operating face — a sans '
                'subhead inside a serif article');
        expect(style.fontSize, kCleanBodySize);
        expect(style.fontWeight, FontWeight.w700);
      });

      testWidgets('h1 and h2 were already serif and did not move',
          (tester) async {
        await _pump(tester, theme, [
          HeadingBlock(1, 'Level one'),
          HeadingBlock(2, 'Level two'),
        ]);

        // Each against its own theme entry, not against the reading serif —
        // **Newspaper has two serifs**, Playfair Display for display and
        // headline, PT Serif for title and body. Asserting h1 == the reading
        // face would have demanded Newspaper give up that distinction, which
        // is one of the few things that makes it read as a newspaper.
        expect(_styleOf(tester, 'Level one').fontFamily,
            theme.textTheme.headlineSmall?.fontFamily);
        expect(_styleOf(tester, 'Level two').fontFamily,
            theme.textTheme.titleLarge?.fontFamily);
        // Still descending, which is what keeps h3 from reading as an h2.
        expect(_styleOf(tester, 'Level one').fontSize!,
            greaterThan(_styleOf(tester, 'Level two').fontSize!));
        expect(_styleOf(tester, 'Level two').fontSize!,
            greaterThan(kCleanBodySize));
      });

      testWidgets('quotes and list items take the same measure',
          (tester) async {
        await _pump(tester, theme, [
          QuoteBlock('A pulled quote'),
          ListBlock(ordered: false, items: ['A bullet']),
          ListBlock(ordered: true, items: ['A numeral']),
        ]);

        for (final text in ['A pulled quote', 'A bullet', 'A numeral']) {
          final style = _styleOf(tester, text);
          expect(style.fontSize, kCleanBodySize, reason: '$name: $text');
          expect(style.height, kCleanBodyHeight, reason: '$name: $text');
          expect(style.fontFamily, serif, reason: '$name: $text');
        }

        // The markers too. A sans bullet beside a serif line is the kind of
        // seam nobody names and everybody sees.
        expect(_styleOf(tester, '•').fontFamily, serif);
        expect(_styleOf(tester, '1.').fontFamily, serif);
      });

      testWidgets('captions stay sans, and are not swept up', (tester) async {
        // Explicit because the sweep through this file touched every other
        // text style in it. A caption is a label about the image, not part of
        // the reading flow, and 3's restyle list says so.
        await _pump(tester, theme, [
          ImageBlock('https://example.com/a.png', caption: 'A caption'),
        ]);
        final style = _styleOf(tester, 'A caption');

        expect(style.fontFamily, theme.textTheme.bodySmall?.fontFamily);
        expect(style.fontSize, isNot(kCleanBodySize),
            reason: '$name: a caption at the reading size is a paragraph');
        expect(style.color, theme.colorScheme.onSurfaceVariant);
      });

      testWidgets('it renders every block type without throwing',
          (tester) async {
        await _pump(tester, theme, [
          HeadingBlock(1, 'H1'),
          HeadingBlock(2, 'H2'),
          HeadingBlock(3, 'H3'),
          ParagraphBlock('Body'),
          QuoteBlock('Quote'),
          ListBlock(ordered: false, items: ['One']),
          ImageBlock('https://example.com/a.png', caption: 'Cap'),
        ]);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('the app actually builds this widget', () {
    // Per the standing rule: a test that constructs its own subject proves a
    // fact about the test. This file constructs `CleanArticleView` directly,
    // which is correct only while that is the widget the reader renders — so
    // the call site is checked rather than assumed.

    test('CleanArticleView has a call site outside its own file', () {
      final callers = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.endsWith('clean_article_view.dart'))
          .where((f) => f.readAsStringSync().contains('CleanArticleView('))
          .map((f) => f.path.replaceAll(r'\', '/'))
          .toList();

      expect(callers, isNotEmpty,
          reason: 'nothing renders the clean view, so every assertion above '
              'is about a widget the app never shows');
    });

    test('nothing else hardcodes a reading measure', () {
      // The other way this rots: a second reading surface appears, copies the
      // numbers rather than the constants, and the two drift. Catching the
      // literals is cheap and the message says where to get them instead.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (path == 'lib/theme/app_theme.dart') continue;

        var n = 0;
        for (final raw in entity.readAsLinesSync()) {
          n++;
          if (raw.trimLeft().startsWith('//')) continue;
          if (RegExp(r'height:\s*1\.6[0-9]?\b').hasMatch(raw)) {
            offenders.add('$path:$n  ${raw.trim()}');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'A reading line height written as a literal:\n  '
              '${offenders.join('\n  ')}\n\n'
              'Use `kCleanBodyHeight`. Two copies of 1.62 is one copy away '
              'from one of them being 1.6.');
    });
  });
}
