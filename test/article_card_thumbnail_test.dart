// Regression cover for the dark-mode scroll flicker.
//
// The thumbnail's "read article" treatment used to be:
//
//   ColorFiltered(
//     colorFilter: ColorFilter.mode(Colors.white, BlendMode.saturation),
//     child: Opacity(opacity: 0.4, child: clipped),
//   )
//
// `saturation` is a non-separable blend mode, so it mixes with the backdrop
// rather than acting on the child alone. Wrapped around a partly-transparent
// Opacity layer with a not-yet-decoded image inside, it resolved toward the
// hardcoded white source and painted a flat light-grey block. Measured on a
// Pixel 9 Pro mid-fling: every thumbnail came back #A6A6A6 against a #0D1B2A
// page. Against the light theme's white page the same block was invisible,
// which is why it went unnoticed for so long.
//
// After the fix the same measurement returns #162338 — exactly
// `surfaceContainerHighest` on the dark theme.
//
// No DB involvement; ArticleCard is a plain StatelessWidget.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/article_card.dart';

Article _article({required bool isRead}) => Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: 'A headline long enough to wrap onto a second line in the card',
      url: 'https://example.com/1',
      thumbnailUrl: 'https://example.com/thumb.jpg',
      publishedAt: DateTime.now().millisecondsSinceEpoch,
      fetchedAt: 0,
      isRead: isRead,
      feedTitle: 'Example Feed',
    );

Future<void> _pump(WidgetTester tester,
    {required bool isRead, required ThemeData theme}) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: ArticleCard(
        article: _article(isRead: isRead),
        onTap: () {},
        onMarkRead: () {},
        onMarkUnread: () {},
        onShare: () {},
        onBookmark: () {},
      ),
    ),
  ));
  await tester.pump();
}

/// The solid base painted under the image while it decodes.
Color? _thumbBase(WidgetTester tester) {
  final boxes = tester.widgetList<ColoredBox>(find.byType(ColoredBox));
  for (final b in boxes) {
    if (b.color == flashDarkTheme().colorScheme.surfaceContainerHighest ||
        b.color == flashLightTheme().colorScheme.surfaceContainerHighest) {
      return b.color;
    }
  }
  return boxes.isEmpty ? null : boxes.first.color;
}

void main() {
  for (final (name, theme) in [
    ('dark', flashDarkTheme()),
    ('light', flashLightTheme()),
  ]) {
    group('$name theme', () {
      testWidgets('an undecoded thumbnail sits on the theme surface colour, '
          'never a hardcoded light value', (tester) async {
        await _pump(tester, isRead: false, theme: theme);

        expect(_thumbBase(tester), theme.colorScheme.surfaceContainerHighest,
            reason: 'the placeholder must come from the active theme — on the '
                'dark theme this is #162338, which is what stops the '
                'mid-scroll flash of bright rectangles');
      });

      testWidgets('a read thumbnail is desaturated with a matrix filter, not a '
          'backdrop-mixing blend mode', (tester) async {
        await _pump(tester, isRead: true, theme: theme);

        final filters =
            tester.widgetList<ColorFiltered>(find.byType(ColorFiltered));
        expect(filters, isNotEmpty,
            reason: 'read thumbnails are still desaturated');

        for (final f in filters) {
          expect(
            f.colorFilter.toString(),
            contains('matrix'),
            reason: 'ColorFilter.mode(..., BlendMode.saturation) blends with '
                'the backdrop and resolved toward its hardcoded white source '
                'over a transparent child, painting a bright block. A matrix '
                'filter has no backdrop term.',
          );
          expect(
            f.colorFilter.toString(),
            isNot(contains('saturation')),
            reason: 'the non-separable blend mode must not come back',
          );
        }
      });

      testWidgets('the read treatment still visibly dims the thumbnail',
          (tester) async {
        await _pump(tester, isRead: true, theme: theme);

        final opacities = tester
            .widgetList<Opacity>(find.byType(Opacity))
            .where((o) => o.opacity < 1.0);
        expect(opacities, isNotEmpty,
            reason: 'dimming is what distinguishes a read article; the fix '
                'changed how it desaturates, not whether it dims');
      });
    });
  }

  testWidgets('an unread thumbnail is not desaturated at all', (tester) async {
    await _pump(tester, isRead: false, theme: flashDarkTheme());
    expect(find.byType(ColorFiltered), findsNothing,
        reason: 'only read articles get the greyscale treatment');
  });
}
