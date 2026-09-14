// Design's Batch 4, pinned in one place.
//
// Three open questions were answered at once and each closed a hole that had
// been sitting in the allowlist or in a comment describing a UI that did not
// exist. Grouping them here rather than scattering them keeps the batch
// reviewable against the memo that produced it.
//
//   1.1  Read state is two named levels, not two alphas. The title drops to
//        onSurfaceRead and the source from onSurfaceVariant to onSurfaceMuted.
//        The timestamp does not move, because it is already at the floor of
//        the scale and a third of the row changing on read is more motion than
//        the state is worth.
//   1.2  Orange has exactly three jobs, and faults are not among them.
//   1.4  confirm-mark-all-read stays. It is the only route back once "Don't
//        show again" is ticked.
//
// Plus the illustration role, which closed four empty-state glyphs, and two
// error-scope corrections.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/utils/date_utils.dart';
import 'package:flash/widgets/article_card.dart';

/// Two hours before whenever the suite runs, so the relative label is stable
/// within a run without being pinned to a wall-clock date that goes stale.
final int _publishedAt =
    DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch;

/// The label the card will actually render, computed with the same function
/// the card uses rather than guessed at — "2h ago" is an English assumption
/// and the formatter is the only thing that knows.
Future<String> _timestampLabel() async {
  final l10n = await AppLocalizations.delegate.load(const Locale('en'));
  return formatRelativeTimestamp(_publishedAt, l10n);
}

Article _article({required bool isRead}) => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: 'A headline',
      url: 'https://example.com/1',
      publishedAt: _publishedAt,
      fetchedAt: 0,
      isRead: isRead,
      feedTitle: 'The Guardian',
    );

Future<void> _pumpCard(
  WidgetTester tester, {
  required bool isRead,
  required ThemeData theme,
}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('en'),
    theme: theme,
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
          article: _article(isRead: isRead),
          onTap: () {},
          onMarkRead: () {},
          onMarkUnread: () {},
          onShare: () {},
          onBookmark: () {},
        ),
      ]),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The colour a piece of text actually resolves to, after the animated
/// default style above it has settled.
Color _resolved(WidgetTester tester, String text) {
  final widget = tester.widget<Text>(find.text(text));
  if (widget.style?.color != null) return widget.style!.color!;
  final style = DefaultTextStyle.of(tester.element(find.text(text))).style;
  return style.color!;
}

/// The authored unread orange, per brightness. Written out rather than
/// compared to another role, because every role it could be compared to
/// is one that could move with it.
Color _expectedUnread(Brightness b) => b == Brightness.light
    ? const Color(0xFFBE6530)
    : const Color(0xFFE79E62);

void main() {
  group('1.1 read state is two named levels', () {
    for (final brightness in Brightness.values) {
      final theme = flashQuietInkTheme(brightness: brightness);
      final ink = theme.flashColors;
      final name = brightness.name;

      testWidgets('$name: unread source is onSurfaceVariant', (tester) async {
        await _pumpCard(tester, isRead: false, theme: theme);
        expect(_resolved(tester, 'The Guardian'),
            theme.colorScheme.onSurfaceVariant);
      });

      testWidgets('$name: read source drops to onSurfaceMuted', (tester) async {
        await _pumpCard(tester, isRead: true, theme: theme);
        expect(_resolved(tester, 'The Guardian'), ink.onSurfaceMuted,
            reason: '$name: reading an article moves the source one step down '
                'the ink scale, it does not thin the same colour');
      });

      testWidgets('$name: the source really does change on read',
          (tester) async {
        // Guards the pair rather than each end: if both roles were ever set
        // to the same value the two tests above would still pass.
        expect(ink.onSurfaceMuted, isNot(theme.colorScheme.onSurfaceVariant));
      });

      testWidgets('$name: the timestamp does not move', (tester) async {
        final label = await _timestampLabel();

        await _pumpCard(tester, isRead: false, theme: theme);
        final unread = _resolved(tester, label);

        await _pumpCard(tester, isRead: true, theme: theme);
        final read = _resolved(tester, label);

        expect(read, unread,
            reason: 'the timestamp is already at the floor of the ink scale, '
                'so there is nowhere quieter for it to go');
        expect(read, ink.onSurfaceMuted);
      });

      testWidgets('$name: no alpha anywhere in the source line',
          (tester) async {
        // The shape of the thing being replaced: a colour with an alpha below
        // 1 means someone reintroduced the faded-ink approach.
        final label = await _timestampLabel();
        for (final isRead in [false, true]) {
          await _pumpCard(tester, isRead: isRead, theme: theme);
          expect(_resolved(tester, 'The Guardian').a, 1.0);
          expect(_resolved(tester, label).a, 1.0);
        }
      });
    }
  });

  group('the illustration role', () {
    test('light and dark are the values Design specified', () {
      expect(
          flashQuietInkTheme(brightness: Brightness.light)
              .flashColors
              .illustration,
          const Color(0xFFC3CAC9));
      expect(
          flashQuietInkTheme(brightness: Brightness.dark)
              .flashColors
              .illustration,
          const Color(0xFF3A4241));
    });

    test('it is quieter than the quietest ink level', () {
      // Which is the reason it is not just onSurfaceMuted. An empty-state
      // glyph is a picture standing in for content that is not there, and it
      // has to sit below text that is merely quiet.
      for (final brightness in Brightness.values) {
        final theme = flashQuietInkTheme(brightness: brightness);
        final surface = theme.colorScheme.surface;
        double contrast(Color c) {
          final a = c.computeLuminance();
          final b = surface.computeLuminance();
          final hi = a > b ? a : b;
          final lo = a > b ? b : a;
          return (hi + 0.05) / (lo + 0.05);
        }

        expect(contrast(theme.flashColors.illustration),
            lessThan(contrast(theme.flashColors.onSurfaceMuted)),
            reason: '${brightness.name}: an illustration must recede further '
                'than a timestamp');
      }
    });

    test('Newspaper mixes its own rather than borrowing the cool grey', () {
      final np = flashNewspaperTheme().flashColors.illustration;
      expect(
          np,
          isNot(flashQuietInkTheme(brightness: Brightness.light)
              .flashColors
              .illustration),
          reason: 'a cool grey glyph on warm newsprint reads as a rendering '
              'fault');
    });

    test('every theme resolves it without throwing', () {
      for (final theme in [ThemeData(), ThemeData.dark()]) {
        expect(() => theme.flashColors.illustration, returnsNormally);
      }
    });
  });

  group('1.2 orange has three jobs and faults are not one', () {
    for (final brightness in Brightness.values) {
      final theme = flashQuietInkTheme(brightness: brightness);
      final scheme = theme.colorScheme;

      test('${brightness.name}: error is not the orange', () {
        // The specific reversal in Batch 4. An invalid URL and a stale feed
        // are faults, and a fault that borrows the queue colour tells the
        // reader something is unread.
        expect(scheme.error, isNot(scheme.secondary));
      });

      // **Two assertions went from here with `savedFill`.** A second line
      // in the test above read `expect(scheme.error, isNot(flashColors
      // .savedFill))`, and a whole test beside it was named "the saved
      // fill IS the queue orange".
      //
      // The first asked the same question twice: `savedFill` resolved to
      // `secondary` in both Quiet Ink brightnesses, so the surviving line
      // already covered it. The second described a block the rail stopped
      // painting — the saved state is a glyph now.
      //
      // What replaced them is not here but in
      // `summary_button_contrast_test.dart`, which measures the saved
      // glyph against the tint it actually sits on: 3.36 / 6.88 / 5.97.
      test('${brightness.name}: orange still means one thing', () {
        // Kept because the claim is about orange's MEANING rather than
        // about the deleted role. Whatever paints "saved" has to be the
        // same orange that paints "unread", or a row that is both
        // carries two accents that look like two different states.
        expect(scheme.secondary, _expectedUnread(brightness));
        expect(scheme.error, isNot(scheme.secondary));
      });
    }
  });
}
