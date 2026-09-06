// The radial row has to fit on a narrow phone in every language.
//
// The geometry comment in `radial_menu.dart` computes the row's width from the
// 64dp circles alone, but a `_RadialButton` is a Column whose width is
// `max(64, labelWidth)`, so the real width is driven by the labels. German's
// labels are far wider than their circles, and a row that once held four
// buttons overflowed a 360dp screen with the last one clipped. Summary has
// since moved to its own button on the card and the row is down to three, but
// the labels are still what decide the width, so this stays pinned.
//
// These tests pin the fix — a `FittedBox(scaleDown)` around the whole layout —
// by asserting the thing the user actually cares about: every action is fully
// on screen, in the longest language, on the narrowest phone the app targets.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/widgets/radial_menu.dart';

Article _article() => const Article(
      id: 1,
      feedId: 1,
      guid: 'g1',
      title: 'T',
      url: 'https://example.com/1',
      publishedAt: 0,
      fetchedAt: 0,
      isRead: false,
      feedTitle: 'Feed A',
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool withDelete,
  required Locale locale,
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: RadialMenu(
      onShare: () {},
      onDismiss: () {},
      onBookmark: () {},
      article: _article(),
      onDelete: withDelete ? () {} : null,
    ),
  ));
  await tester.pumpAndSettle();
}

/// Every 64x64 action circle's rect, in global coordinates.
///
/// Read off the painted geometry rather than the widget tree, so the
/// FittedBox's scale is included — a row that only fits because it was scaled
/// down still counts as fitting, and one that was not scaled enough does not.
List<Rect> _circleRects(WidgetTester tester) {
  final rects = <Rect>[];
  for (final element in find.byType(Container).evaluate()) {
    final box = element.renderObject as RenderBox;
    if (!box.hasSize) continue;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    // The circles are the only 64x64 Containers in this tree; scaling makes
    // the painted size smaller, so match on the pre-scale size instead.
    if (box.size.width == 64 && box.size.height == 64) rects.add(rect);
  }
  return rects;
}

// Note: the 20dp-vs-12dp gap between three and four actions is deliberately
// not asserted here. flutter_test's default font gives every glyph identical
// metrics, so a button is wider than its 64dp circle by an amount that has
// nothing to do with the real font, and the four-action row is scaled by the
// FittedBox on top of that — a spacing comparison comes out "correct" for any
// value of the constant. A test that cannot fail is worse than no test.

void main() {
  // 360x800 logical pixels is the narrow end of the phones this ships to.
  const narrowPhone = Size(360, 800);

  for (final locale in const [Locale('en'), Locale('de')]) {
    final tag = locale.languageCode;

    testWidgets('$tag: all three actions are fully on screen at 360dp',
        (tester) async {
      await _pump(tester,
          withDelete: true, locale: locale, size: narrowPhone);

      final rects = _circleRects(tester);
      expect(rects, hasLength(4),
          reason: 'Bookmark, Share, Delete, plus the close button');

      for (final rect in rects) {
        expect(rect.left, greaterThanOrEqualTo(0.0),
            reason: '$tag: an action is off the left edge');
        expect(rect.right, lessThanOrEqualTo(narrowPhone.width),
            reason: '$tag: an action is off the right edge — this is exactly '
                'how the Delete button disappeared in German');
      }
    });

    testWidgets('$tag: two actions still fit, unchanged', (tester) async {
      await _pump(tester,
          withDelete: false, locale: locale, size: narrowPhone);

      final rects = _circleRects(tester);
      expect(rects, hasLength(3),
          reason: 'Bookmark and Share, plus the close button');
      for (final rect in rects) {
        expect(rect.left, greaterThanOrEqualTo(0.0));
        expect(rect.right, lessThanOrEqualTo(narrowPhone.width));
      }
    });
  }

  testWidgets('no layout overflow is reported in German with three actions',
      (tester) async {
    await _pump(tester,
        withDelete: true, locale: const Locale('de'), size: narrowPhone);

    // A RenderFlex overflow paints a stripe and logs an exception rather than
    // throwing, so it has to be asked for explicitly.
    expect(tester.takeException(), isNull);
  });
}
