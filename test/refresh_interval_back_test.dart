// Back-press handling for the interval dropdown, on a PUSHED ROUTE.
//
// This is the regression the refresh-settings move introduced and nothing
// caught. The widget registered its dismiss handler with
// `registerBackDismiss`, whose stack is only ever read by
// `dismissTopBubblePanel()` — and the only callers of that are three back
// handlers in the app shell (lib/app.dart). Those run when the shell answers
// back, which was true while the field lived in the Quick Settings bubble (an
// overlay ABOVE the shell) and is false now that it lives on SettingsScreen (a
// pushed route, whose own pop answers back first). The handler was unreachable,
// so the first back press popped Settings with the menu still open.
//
// The route here is the point of the test. Pumping the field as `home:` would
// pass against the broken build, because there is no route to pop.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/widgets/refresh_interval_field.dart';

const _home = ValueKey('homeScreen');
const _pushed = ValueKey('pushedScreen');

/// Pumps a two-route app and pushes the second, which hosts the field —
/// the shape SettingsScreen has.
Future<int> _pumpPushed(WidgetTester tester, {int value = 180}) async {
  var current = value;

  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Builder(
      builder: (context) => Scaffold(
        key: _home,
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  key: _pushed,
                  body: StatefulBuilder(
                    builder: (context, setState) => RefreshIntervalField(
                      value: current,
                      onChanged: (v) => setState(() => current = v),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('open settings'),
          ),
        ),
      ),
    ),
  ));

  await tester.tap(find.text('open settings'));
  await tester.pumpAndSettle();
  expect(find.byKey(_pushed), findsOneWidget);
  return current;
}

/// The menu is open when more than one option label is on screen — the field
/// itself only ever shows the selected one.
bool _menuOpen() => find.text('Every 6 hours').evaluate().isNotEmpty;

void main() {
  testWidgets('back closes the open menu and does NOT pop the route',
      (tester) async {
    await _pumpPushed(tester);

    await tester.tap(find.text('Every 3 hours'));
    await tester.pumpAndSettle();
    expect(_menuOpen(), isTrue, reason: 'menu should be open');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(_menuOpen(), isFalse, reason: 'back should have closed the menu');
    expect(find.byKey(_pushed), findsOneWidget,
        reason: 'back must NOT pop the hosting route while the menu is open — '
            'this is the assertion that fails on the pre-fix build');
  });

  testWidgets('a second back then pops the route normally', (tester) async {
    await _pumpPushed(tester);

    await tester.tap(find.text('Every 3 hours'));
    await tester.pumpAndSettle();
    expect(_menuOpen(), isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_pushed), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(_pushed), findsNothing,
        reason: 'with the menu closed the route must pop as usual — the fix '
            'must not trap the user on the screen');
    expect(find.byKey(_home), findsOneWidget);
  });

  testWidgets('back pops immediately when no menu is open', (tester) async {
    await _pumpPushed(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(_pushed), findsNothing);
  });

  testWidgets('selecting an option closes the menu and frees back',
      (tester) async {
    await _pumpPushed(tester);

    await tester.tap(find.text('Every 3 hours'));
    await tester.pumpAndSettle();
    // Deliberately NOT "Every 6 hours": that is the label _menuOpen() keys on,
    // so choosing it would make the field's own text look like an open menu.
    await tester.tap(find.text('Every hour').last);
    await tester.pumpAndSettle();

    expect(_menuOpen(), isFalse, reason: 'menu closes on selection');
    expect(find.text('Every hour'), findsOneWidget,
        reason: 'the field now shows the chosen value');

    // canPop has to go back to true, or the screen becomes a trap.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_pushed), findsNothing);
  });

  testWidgets('tapping the dismiss layer also frees back', (tester) async {
    await _pumpPushed(tester);

    await tester.tap(find.text('Every 3 hours'));
    await tester.pumpAndSettle();
    expect(_menuOpen(), isTrue);

    // The full-screen dismiss layer sits behind the option list; the top-left
    // corner is clear of it.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_menuOpen(), isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(_pushed), findsNothing);
  });
}
