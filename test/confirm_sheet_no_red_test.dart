// No destructive confirmation in this app is painted red.
//
// The confirm button used to take `error` under `onError` behind an
// `isDestructive` flag, and both call sites passed `isDestructive: true`. The
// flag drove nothing else, so it went with the colour.
//
// The argument, kept because it is the whole rationale: nothing in this app
// needs red to say "this deletes things" when the sentence above the button
// already does. `deleteFolderMessage` names the category, `removeFeedMessage`
// names the feed, and that sentence is where the consequence is actually
// stated. Red on top of it read as an error — as though something had gone
// wrong, when the user is being asked a question.
//
// **Why this needed a refactor to test at all.** `_ConfirmSheet` was private
// to feeds_screen.dart, so the only way to reach it was to drive the whole
// screen — which builds its own repositories, favicon service and Feedly
// client on init, and needs a database on a real isolate before it renders a
// single row. An assertion about a colour is not worth that apparatus, and a
// widget two screens share is a shared component anyway, so it moved to
// lib/widgets/confirm_sheet.dart and became public. This file constructs it
// directly.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/theme/app_theme.dart';
import 'package:flash/widgets/confirm_sheet.dart';

const String _message =
    'Delete "Gaming"? Its 3 feeds move to Uncategorised. Articles are kept.';

Future<void> _pump(WidgetTester tester, ThemeData theme) async {
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
    home: const Scaffold(
      body: ConfirmSheet(
        title: 'Delete category',
        message: _message,
        confirmLabel: 'Delete',
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Every colour anything in the sheet actually resolves to.
///
/// Deliberately broad — fills, glyphs and text alike — because the claim is
/// that red is gone from the sheet entirely, not that one known node stopped
/// using it.
Set<Color> _coloursIn(WidgetTester tester) {
  final found = <Color>{};
  for (final w in tester.allWidgets) {
    if (w is Icon && w.color != null) found.add(w.color!);
    if (w is Text && w.style?.color != null) found.add(w.style!.color!);
    if (w is Material && w.color != null) found.add(w.color!);
    if (w is ColoredBox) found.add(w.color);
    if (w is Container) {
      final d = w.decoration;
      if (d is BoxDecoration && d.color != null) found.add(d.color!);
    }
  }
  return found;
}

void main() {
  for (final (name, theme) in [
    ('Quiet Ink light', flashQuietInkTheme(brightness: Brightness.light)),
    ('Quiet Ink dark', flashQuietInkTheme(brightness: Brightness.dark)),
    ('Newspaper', flashNewspaperTheme()),
  ]) {
    group(name, () {
      testWidgets('nothing in the sheet resolves to error', (tester) async {
        await _pump(tester, theme);

        final scheme = theme.colorScheme;
        final colours = _coloursIn(tester);

        expect(colours, isNot(contains(scheme.error)),
            reason: '$name: something in the confirmation is painted in '
                'colorScheme.error');

        // `error` only, deliberately. `onError` is plain white and
        // `errorContainer` a pale tint, and both collide with perfectly
        // ordinary surfaces — asserting on them fails on a sheet that has no
        // red in it at all, which is worse than not asserting. The red itself
        // is the distinctive value and the one that was actually painted.
      });

      testWidgets('the confirm button takes no colour override at all',
          (tester) async {
        await _pump(tester, theme);

        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.style?.backgroundColor, isNull,
            reason: 'not "a different colour" but no override — it falls to '
                'FilledButton\'s default, which is primary');
        expect(button.style?.foregroundColor, isNull);
      });

      testWidgets('the sentence that does the warning is intact',
          (tester) async {
        // The half that matters. Dropping the colour is only defensible
        // because the copy names what is about to happen; if a later edit
        // trims the message to fit the sheet, the warning goes with it and
        // nothing is left doing the job.
        await _pump(tester, theme);
        expect(find.text(_message), findsOneWidget);
      });

      testWidgets('it offers a way out as well as a way through',
          (tester) async {
        await _pump(tester, theme);
        expect(find.byType(OutlinedButton), findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
      });
    });
  }

  testWidgets('confirming returns true, cancelling returns false',
      (tester) async {
    // The sheet's contract, which the de-redding must not have disturbed:
    // both call sites branch on `confirmed == true`.
    for (final (finder, expected) in [
      (find.byType(FilledButton), true),
      (find.byType(OutlinedButton), false),
    ]) {
      bool? result;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        theme: flashQuietInkTheme(brightness: Brightness.light),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showModalBottomSheet<bool>(
                    context: context,
                    builder: (_) => const ConfirmSheet(
                      title: 'Delete category',
                      message: _message,
                      confirmLabel: 'Delete',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();

      expect(result, expected);
    }
  });
}
