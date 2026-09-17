// B1: the unread dot, and the invariant that matters more than the dot.
//
// The dot is a 5dp circle in `secondary` at the head of the meta line. That
// part is easy. The part this file exists for is that **the 12dp it occupies
// is laid out whether or not it paints.**
//
// On read the dot fades to transparent and keeps its space. If the space were
// released instead, the meta line would shift left the instant
// mark-read-on-scroll fired, and every row below it would move under the
// reader's thumb — while they are reading. That is the same failure as the
// read font-weight change this project already refused once
// (`article_card_read_colour_test.dart`), arriving by a different route: not a
// glyph getting narrower, but a box going away.
//
// **Why there is a mid-transition test.** A fade that reclaims its space at the
// end of the animation passes a naive before/after comparison perfectly — you
// measure at rest, you measure at rest again, and the 180ms in between is where
// the row jumps. So one test measures at t=0.5 of `kReadDimDuration`, which is
// the only place that bug is visible.
//
// All four assert the dot is actually present, because "the geometry does not
// move" is trivially true of a feature that does not exist, and these were
// written before it did.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/utils/date_utils.dart';
import 'package:flash/widgets/article_card.dart';

/// The dot's own width plus the gap before the favicon. Pinned as a number
/// because the whole point is that it does not depend on what is painted:
/// 5dp of circle and 7dp of air, reserved in both states.
const double kUnreadDotReservedWidth = 12.0;
const double kUnreadDotDiameter = 5.0;

/// A title long enough to wrap, because a wrapped title is where a reflow is
/// visible and where the original weight bug bit.
const String _title =
    'A headline long enough to wrap across more than one line inside the card, '
    'which is where a reflow would actually show';

Article _article({required bool isRead}) => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: _title,
      url: 'https://example.com/1',
      publishedAt: DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch,
      fetchedAt: 0,
      isRead: isRead,
      feedTitle: 'The Guardian',
    );

Widget _app(ThemeData theme, Widget child) => MaterialApp(
      locale: const Locale('en'),
      theme: theme,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: ListView(children: [child])),
    );

ArticleCard _card({required bool isRead}) => ArticleCard(
      article: _article(isRead: isRead),
      onTap: () {},
      onShare: () {},
      onBookmark: () {},
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool isRead,
  required ThemeData theme,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(_app(theme, _card(isRead: isRead)));
  await tester.pumpAndSettle();
}

Finder _slot() => find.byKey(const ValueKey('unread_dot_slot'));
Finder _dot() => find.byKey(const ValueKey('unread_dot'));

void main() {
  final themes = <String, ThemeData>{
    'light': flashQuietInkTheme(brightness: Brightness.light),
    'dark': flashQuietInkTheme(brightness: Brightness.dark),
  };

  themes.forEach((name, theme) {
    group(name, () {
      testWidgets('1. the row is exactly the same height read and unread',
          (tester) async {
        await _pump(tester, isRead: false, theme: theme);
        expect(_dot(), findsOneWidget,
            reason: 'an unread row must have a dot to reserve space for');
        final unread = tester.getSize(find.byType(ArticleCard));

        await _pump(tester, isRead: true, theme: theme);
        final read = tester.getSize(find.byType(ArticleCard));

        expect(read, unread,
            reason: '$name: the row changed size on read. Every card below '
                'this one has just moved under the reader.');
      });

      testWidgets('2. the meta line does not move sideways on read',
          (tester) async {
        // The specific shift a released slot would cause. Height can be stable
        // while the line still slides left.
        //
        // Measured on the source text rather than the favicon: a card with no
        // stored favicon renders no Image at all, so an Image finder is empty
        // exactly when this is being checked. The source is the leftmost thing
        // in the meta line that always paints.
        await _pump(tester, isRead: false, theme: theme);
        final unread = tester.getTopLeft(find.text('The Guardian')).dx;

        await _pump(tester, isRead: true, theme: theme);
        final read = tester.getTopLeft(find.text('The Guardian')).dx;

        expect(read, unread,
            reason: '$name: the meta line moved ${(unread - read).abs()}dp '
                'when the article was marked read');
      });

      testWidgets('3. the slot is 12dp wide whether or not the dot paints',
          (tester) async {
        for (final isRead in [false, true]) {
          await _pump(tester, isRead: isRead, theme: theme);

          expect(_slot(), findsOneWidget,
              reason: '$name: the reserved slot must exist in both states, '
                  'not only when the dot is visible');
          expect(tester.getSize(_slot()).width, kUnreadDotReservedWidth,
              reason: '$name: isRead=$isRead reserved '
                  '${tester.getSize(_slot()).width}dp instead of '
                  '$kUnreadDotReservedWidth');
          expect(tester.getSize(_dot()).width, kUnreadDotDiameter);
          expect(tester.getSize(_dot()).height, kUnreadDotDiameter);
        }
      });

      testWidgets('4. and mid-fade, halfway through the transition',
          (tester) async {
        // The test the other three cannot replace. A fade that gives its space
        // back at the end of the animation measures identically at rest on
        // both sides; the jump happens in the 180ms between.
        var isRead = false;
        late StateSetter setState;

        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(
          theme,
          StatefulBuilder(builder: (context, setter) {
            setState = setter;
            return _card(isRead: isRead);
          }),
        ));
        await tester.pumpAndSettle();

        final before = tester.getSize(find.byType(ArticleCard));
        final metaBefore = tester.getTopLeft(find.text('The Guardian')).dx;

        setState(() => isRead = true);
        await tester.pump();
        await tester.pump(kReadDimDuration ~/ 2);

        expect(tester.getSize(_slot()).width, kUnreadDotReservedWidth,
            reason: '$name: the slot collapsed mid-fade');
        expect(tester.getSize(find.byType(ArticleCard)), before,
            reason: '$name: the row resized mid-fade — invisible to a '
                'before/after test and very visible to a reader');
        expect(tester.getTopLeft(find.text('The Guardian')).dx, metaBefore,
            reason: '$name: the meta line slid sideways mid-fade');

        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(ArticleCard)), before,
            reason: '$name: the row resized once the fade finished');
      });
    });
  });

  group('the dot itself', () {
    testWidgets('light is the unread orange', (tester) async {
      final theme = flashQuietInkTheme(brightness: Brightness.light);
      await _pump(tester, isRead: false, theme: theme);

      final box = tester.widget<Container>(_dot());
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFBE6530));
      expect(decoration.color, theme.colorScheme.secondary);
      expect(decoration.shape, BoxShape.circle);
    });

    testWidgets('dark is the dark unread orange', (tester) async {
      final theme = flashQuietInkTheme(brightness: Brightness.dark);
      await _pump(tester, isRead: false, theme: theme);

      final decoration =
          tester.widget<Container>(_dot()).decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFFE79E62));
      expect(decoration.color, theme.colorScheme.secondary);
    });

    testWidgets('and it is fully transparent once read', (tester) async {
      await _pump(tester,
          isRead: true,
          theme: flashQuietInkTheme(brightness: Brightness.light));

      final decoration =
          tester.widget<Container>(_dot()).decoration! as BoxDecoration;
      expect(decoration.color!.a, 0.0,
          reason: 'a read article shows no dot — it keeps the space, not the '
              'mark');
    });

    testWidgets('Newspaper renders it without throwing', (tester) async {
      // Newspaper has no orange; secondary there is _npRed, which is its own
      // unread accent rather than a fault colour.
      await _pump(tester, isRead: false, theme: flashNewspaperTheme());
      expect(tester.takeException(), isNull);
      expect(_slot(), findsOneWidget);
    });
  });

  group('the timestamp is mono and tabular', () {
    // kNumeralTimestampStyle was declared in pass 1 and wired to nothing until
    // this pass. Tabular is the reason rather than the look: a proportional
    // "1" is narrower than a "4", so a relative timestamp ticking from "1h
    // ago" to "4h ago" changes width and pulls the meta line with it. That is
    // the same reflow the reserved dot slot exists to prevent, arriving on a
    // timer instead of on a gesture — and nothing would have caught it,
    // because no test watches a card for an hour.
    Future<String> label() async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      return formatRelativeTimestamp(
          DateTime.now()
              .subtract(const Duration(hours: 2))
              .millisecondsSinceEpoch,
          l10n);
    }

    for (final brightness in Brightness.values) {
      final theme = flashQuietInkTheme(brightness: brightness);

      testWidgets('${brightness.name}: JetBrains Mono at 12.5, tabular',
          (tester) async {
        await _pump(tester, isRead: false, theme: theme);

        final style = DefaultTextStyle.of(
          tester.element(find.text(await label())),
        ).style;

        expect(style.fontFamily, kMonoFamily);
        expect(style.fontSize, 12.5);
        expect(style.fontFeatures, contains(const FontFeature.tabularFigures()),
            reason: 'without tabular figures the timestamp changes width as it '
                'ticks, and the meta line moves with it');
      });

      testWidgets('${brightness.name}: and it stays that way when read',
          (tester) async {
        await _pump(tester, isRead: true, theme: theme);

        final style = DefaultTextStyle.of(
          tester.element(find.text(await label())),
        ).style;

        expect(style.fontFamily, kMonoFamily);
        expect(style.fontSize, 12.5);
        expect(style.color, theme.flashColors.onSurfaceMuted,
            reason: 'the timestamp is the one element that does not change on '
                'read — it already sits at the floor of the ink scale');
      });
    }
  });
}
