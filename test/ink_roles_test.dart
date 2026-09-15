// The three ink levels, rendered.
//
// Pass 1 authored the roles; pass 2 makes the app use them. The point of this
// file is that a role substitution is only correct if the pixel that comes out
// is the authored hex — so these assert the exact value, in both brightnesses,
// not "is darker than" or "is not the default".
//
// Why exact matters here specifically: the thing being replaced was
// `onSurface.withValues(alpha: n)`, which is *plausible* at every value. 60%
// ink over white is a grey, and a reviewer scanning a diff cannot tell it from
// #5A6361. Only the number can.
//
// One widget per role:
//
//   onSurfaceVariant  FeedCard's domain subtitle — secondary text under a
//                     primary title, the textbook case for the middle level.
//   onSurfaceMuted    ArticleDetailPlaceholder — the reading pane's empty
//                     state, whose local variable was already called `muted`.
//   onSurfaceRead     already covered, in article_card_read_colour_test.dart,
//                     which also pins that read state never changes weight.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/feed.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_detail_pane.dart';
import 'package:flash/widgets/feed_card.dart';

Feed _feed() => const Feed(
      id: 1,
      folderId: 1,
      title: 'Example Feed',
      url: 'https://news.example.com/rss',
      siteUrl: 'https://news.example.com',
      position: 0,
      createdAt: 0,
    );

Future<void> _pump(WidgetTester tester, Widget child, Brightness brightness) async {
  await tester.pumpWidget(MaterialApp(
    theme: flashQuietInkTheme(brightness: brightness),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

/// The resolved colour of a rendered Text, by its content.
Color? _colourOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  for (final brightness in Brightness.values) {
    final theme = flashQuietInkTheme(brightness: brightness);
    final scheme = theme.colorScheme;
    final flash = theme.extension<FlashColors>()!;
    final name = brightness.name;

    group('$name: onSurfaceVariant', () {
      testWidgets("a feed's domain is secondary text", (tester) async {
        await _pump(tester, FeedCard(feed: _feed()), brightness);

        final colour = _colourOf(tester, 'news.example.com');
        expect(colour, scheme.onSurfaceVariant);
        expect(colour, isNot(scheme.onSurface),
            reason: 'the domain must stay quieter than the title above it');
        expect(colour, isNot(flash.onSurfaceMuted),
            reason: 'it is secondary, not tertiary — there is nothing below '
                'it for it to recede behind');
      });

      test('the role is the authored hex, not a computed grey', () {
        expect(
          scheme.onSurfaceVariant.toARGB32(),
          brightness == Brightness.light ? 0xFF5A6361 : 0xFF8C9695,
        );
      });
    });

    group('$name: onSurfaceMuted', () {
      testWidgets('the empty reading pane is tertiary text', (tester) async {
        await _pump(tester, const ArticleDetailPlaceholder(), brightness);

        final text = tester.widget<Text>(
          find.descendant(
            of: find.byType(ArticleDetailPlaceholder),
            matching: find.byType(Text),
          ),
        );
        expect(text.style?.color, flash.onSurfaceMuted);
      });

      testWidgets('and so is the icon above it', (tester) async {
        // One local named `muted` paints both, and they have to stay together:
        // an icon and its caption at two different greys reads as a rendering
        // bug rather than a hierarchy.
        await _pump(tester, const ArticleDetailPlaceholder(), brightness);

        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byType(ArticleDetailPlaceholder),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.color, flash.onSurfaceMuted);
      });

      test('the role is the authored hex, not a computed grey', () {
        expect(
          flash.onSurfaceMuted.toARGB32(),
          brightness == Brightness.light ? 0xFF717877 : 0xFF767F7E,
        );
      });
    });

    test('$name: the three levels are three distinct colours', () {
      // If any two ever collapsed, the hierarchy would be gone while every
      // individual assertion above still passed.
      final levels = {
        scheme.onSurface,
        scheme.onSurfaceVariant,
        flash.onSurfaceMuted,
        flash.onSurfaceRead,
      };
      expect(levels, hasLength(4));
    });
  }
}
