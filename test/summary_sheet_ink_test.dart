// Pass 8, section 2: verification of the summary sheet's ink, not a rewrite.
//
// Every state this sheet can be in took its roles in passes 2 and 4. This file
// walks the ones a widget test can actually reach and pins what it finds, so
// "verified in pass 8" survives as an assertion rather than as a sentence in a
// report.
//
// **Two states are deliberately absent, and the reason is a refusal rather
// than an oversight.** `aiSummaryFailed` and `aiSummaryDisclaimerCloud` both
// hang off `useCloud`, which is resolved inside the widget from the summary
// tier and has no test seam. Adding one would be a production change made for
// a test's convenience, which this project has turned down before. They are
// verified by reading: both take `onSurfaceMuted`, on the same two lines as
// their on-device counterparts — 331-333 for the message and 587-592 for the
// disclaimer — so a drift in either would have to be written deliberately into
// a ternary whose other half is pinned below.
//
// The header, the status line and the disclaimer are asserted in all three
// themes; the interaction states in one, because what they prove is that the
// control resolves at all and that is not a per-theme fact.


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/screens/article_summary_sheet.dart';
import 'package:flash/services/gemini_nano_service.dart';
import 'package:flash/services/summary_cache.dart';
import 'package:flash/services/settings_notifier.dart';
import 'package:flash/theme/app_theme.dart';

const String _channelName = 'io.getflash.app/gemini_nano';
const StandardMethodCodec _codec = StandardMethodCodec();

Article _article() => const Article(
      id: 1,
      feedId: 1,
      guid: 'guid-1',
      title: 'A headline to summarise',
      url: 'https://example.com/a',
      description: 'Some article body text worth summarising.',
      fetchedAt: 0,
    );

void _mockNative(WidgetTester tester, {bool available = true}) {
  tester.binding.defaultBinaryMessenger
      .setMockMessageHandler(_channelName, (ByteData? message) async {
    final call = _codec.decodeMethodCall(message);
    switch (call.method) {
      case 'isAvailable':
        if (!available) {
          return _codec.encodeErrorEnvelope(
              code: 'NANO_UNAVAILABLE', message: 'Feature status: 0');
        }
        return _codec.encodeSuccessEnvelope(true);
      case 'summarize':
        return _codec.encodeSuccessEnvelope(null);
    }
    return null;
  });
}

Future<void> _fromNative(WidgetTester tester, String method, Object? args) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      _channelName,
      _codec.encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );

Future<void> _pump(WidgetTester tester, ThemeData theme) async {
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ArticleSummarySheet(
        article: _article(),
        summaryLengthForTesting: 'standard',
      ),
    ),
  ));
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GeminiNanoService.resetForTesting();
    SummaryCache.instance.clear();
    SettingsNotifier.instance;
  });

  final themes = <String, ThemeData>{
    'light': flashQuietInkTheme(brightness: Brightness.light),
    'dark': flashQuietInkTheme(brightness: Brightness.dark),
    'Newspaper': flashNewspaperTheme(),
  };

  themes.forEach((name, theme) {
    group(name, () {
      testWidgets('in progress: the status line is muted ink', (tester) async {
        // Reading and writing are one status line with two strings and one
        // style, and which is on screen depends on how fast extraction
        // finished — with a description-only article it is instant, so the
        // sheet is usually already writing by the third pump. The assertion
        // is the role, which both share, rather than the race.
        _mockNative(tester);
        await _pump(tester, theme);

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(find.byKey(const ValueKey('summaryLoading')), findsOneWidget);

        final onScreen = [l10n.aiSummaryReading, l10n.aiSummaryWriting]
            .where((t) => find.text(t).evaluate().isNotEmpty)
            .toList();
        expect(onScreen, hasLength(1),
            reason: '$name: exactly one progress line should be up, and '
                '${onScreen.length} were');

        expect(_styleOf(tester, onScreen.single).color,
            theme.flashColors.onSurfaceMuted,
            reason: '$name: a progress line is the quietest thing on the '
                'sheet, and the one role below onSurfaceVariant is where it '
                'belongs');
      });

      testWidgets('the header sparkle is the interactive teal', (tester) async {
        // Not `secondary`. The sheet is opened from the rail's teal half and
        // the glyph repeats it; orange here would make a summary look like
        // unread state.
        _mockNative(tester);
        await _pump(tester, theme);

        final icon = tester.widget<Icon>(
            find.byIcon(Icons.auto_awesome_rounded).first);
        expect(icon.color, theme.colorScheme.primary);
      });

      testWidgets('unavailable: muted glyph, variant message', (tester) async {
        _mockNative(tester, available: false);
        await _pump(tester, theme);
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byKey(const ValueKey('summaryUnavailable')), findsOneWidget,
            reason: '$name: the unavailable branch did not render');

        final icon =
            tester.widget<Icon>(find.byIcon(Icons.info_outline_rounded));
        expect(icon.color, theme.flashColors.onSurfaceMuted);

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(_styleOf(tester, l10n.aiSummaryUnavailable).color,
            theme.colorScheme.onSurfaceVariant,
            reason: '$name: the message is the content of this state, so it '
                'takes the first role and the glyph beside it stays muted');
      });

      testWidgets('done: the on-device disclaimer is muted and italic',
          (tester) async {
        _mockNative(tester);
        await _pump(tester, theme);
        await _fromNative(tester, 'summaryChunk', 'A one line summary.');
        await _fromNative(tester, 'summaryDone', null);
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        final style = _styleOf(tester, l10n.aiSummaryDisclaimer);
        expect(style.color, theme.flashColors.onSurfaceMuted);
        expect(style.fontStyle, FontStyle.italic,
            reason: '$name: the disclaimer is set apart by slant rather than '
                'by a colour of its own');
      });

      testWidgets('it renders without throwing', (tester) async {
        _mockNative(tester);
        await _pump(tester, theme);
        expect(tester.takeException(), isNull);
      });
    });
  });

  group('the interaction states, in one theme', () {
    final theme = flashQuietInkTheme(brightness: Brightness.light);

    testWidgets('writing: the status line changes text, not role',
        (tester) async {
      // The state that separates "reading the article" from "writing the
      // summary" is one bool, and both lines share a style. Asserted because
      // a future edit that gives writing its own colour would be a change
      // nobody asked for and nobody would see in review.
      _mockNative(tester);
      await _pump(tester, theme);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await _fromNative(tester, 'summaryChunk', 'First chunk.');
      await tester.pump();

      expect(find.text(l10n.aiSummaryWriting), findsOneWidget,
          reason: 'a chunk should have moved it from reading to writing');
      expect(_styleOf(tester, l10n.aiSummaryWriting).color,
          theme.flashColors.onSurfaceMuted);
    });

    testWidgets('show details is onSurfaceVariant, not the orange',
        (tester) async {
      // **The reason this assertion exists, in full.**
      //
      // `article_summary_sheet.dart:449` reads
      // `final secondary = theme.colorScheme.onSurfaceVariant;` — a local
      // named `secondary` that is NOT `colorScheme.secondary`, in an app where
      // handoff 1.6 reserves `secondary` for exactly two meanings, unread and
      // saved. The role is correct; the name is a trap, and "fixing" it to
      // `theme.colorScheme.secondary` would turn this control orange while
      // looking like a tidy-up.
      //
      // Pinning the resolved colour means that edit fails here rather than
      // shipping.
      // The control belongs to `_UnavailableMessage`, not to a finished
      // summary: it reveals the technical reason behind a failure. So the
      // route to it is the unavailable state, not the done one — which is
      // worth knowing, because "show details" sounds like it belongs to the
      // summary and does not.
      _mockNative(tester, available: false);
      await _pump(tester, theme);
      await tester.pump(const Duration(milliseconds: 50));

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final toggle = find.text(l10n.aiSummaryShowDetails);
      if (toggle.evaluate().isEmpty) {
        // It only renders when a debug reason came back. If the native side
        // ever stops supplying one this test is measuring nothing, and says
        // so rather than passing quietly.
        fail('no show-details control rendered — this test has stopped '
            'covering the colour it was written for');
      }

      final style = _styleOf(tester, l10n.aiSummaryShowDetails);
      expect(style.color, theme.colorScheme.onSurfaceVariant);
      expect(style.color, isNot(theme.colorScheme.secondary),
          reason: 'kept explicit: the local that carries this value is called '
              '`secondary` and is not');
    });
  });
}
