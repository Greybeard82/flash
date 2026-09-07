import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/screens/article_summary_sheet.dart';
import 'package:flash/services/summary_formatter.dart';
import 'package:flash/services/gemini_nano_service.dart';
import 'package:flash/services/summary_cache.dart';

const _channelName = 'io.getflash.app/gemini_nano';
const _codec = StandardMethodCodec();

const _loading = ValueKey('summaryLoading');
const _text = ValueKey('summaryText');
const _unavailable = ValueKey('summaryUnavailable');

Article _article() => const Article(
      feedId: 1,
      guid: 'guid-1',
      title: "You Won't Believe What This Startup Did",
      url: 'https://example.com/a',
      description: 'Some article body text.',
      fetchedAt: 0,
    );

/// Mocks the native side of the platform channel.
/// `summarizeCalls` collects the arguments the widget sends to `summarize`.
void _mockNative(WidgetTester tester,
    {bool available = true, List<Map<Object?, Object?>>? summarizeCalls}) {
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(_channelName,
      (ByteData? message) async {
    final call = _codec.decodeMethodCall(message);
    switch (call.method) {
      case 'isAvailable':
        if (!available) {
          return _codec.encodeErrorEnvelope(
              code: 'NANO_UNAVAILABLE', message: 'Feature status: 0');
        }
        return _codec.encodeSuccessEnvelope(true);
      case 'summarize':
        summarizeCalls?.add(call.arguments as Map<Object?, Object?>);
        return _codec.encodeSuccessEnvelope(null);
    }
    return null;
  });
}

/// Simulates a native -> Flutter call (summaryChunk / summaryDone / summaryError).
Future<void> _fromNative(WidgetTester tester, String method, Object? args) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    _channelName,
    _codec.encodeMethodCall(MethodCall(method, args)),
    (_) {},
  );
}

Future<void> _pumpSheet(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
        // Tier supplied directly: these tests have no database, and
        // the real read would hang rather than fail under FakeAsync.
        body: ArticleSummarySheet(
            article: _article(),
            summaryLengthForTesting: kSummaryLengthStandard)),
  ));
  // Let the isAvailable + summarize method-channel round-trips complete.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// The longest realistic output shape: the ~100-word prose paragraph the
/// prompt asks for, plus the maximum 5 bullets, ~270 words total. The
/// paragraph is one line with no internal breaks, which is what the prompt
/// specifies and what [SummaryFormatter] assumes when it trims.
String _maxLengthSummary() {
  const focal =
      'The startup actually shut down after losing its largest client, '
      'which accounted for most of its recurring annual revenue stream, '
      'and executives spent the following weeks quietly notifying investors '
      'and remaining staff before any public statement or regulatory filing '
      'about the closure appeared anywhere online for customers or press to '
      'find on their own.'; // 54 words
  final bullets = List.generate(
      5,
      (i) => '- Point number ${i + 1} covers one additional relevant reported '
          'fact with names and figures attached for context, drawn directly '
          'from internal financial statements and confirmed independently by '
          'two people familiar with the matter who both requested anonymity '
          'given the sensitivity of ongoing negotiations'); // 42 words each
  return '$focal\n${bullets.join('\n')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GeminiNanoService.resetForTesting();
    SummaryCache.instance.clear();
  });

  testWidgets(
      'shows only loading animation while chunks stream in — '
      'partial text is never rendered', (tester) async {
    _mockNative(tester);
    await _pumpSheet(tester);

    expect(find.byKey(_loading), findsOneWidget);

    await _fromNative(tester, 'summaryChunk', 'The actual answer is 42.');
    await tester.pump();
    await _fromNative(tester, 'summaryChunk', ' More facts follow.');
    await tester.pump();

    // Chunks arrived, but nothing textual is displayed yet.
    expect(find.textContaining('42'), findsNothing);
    expect(find.byKey(_text), findsNothing);
    expect(find.byKey(_loading), findsOneWidget);
  });

  testWidgets('reveals the complete summary in a single step on done',
      (tester) async {
    _mockNative(tester);
    await _pumpSheet(tester);

    await _fromNative(tester, 'summaryChunk', 'The actual answer is 42.');
    await _fromNative(tester, 'summaryChunk', '\n- supporting fact');
    await tester.pump();
    expect(find.byKey(_text), findsNothing); // still hidden pre-done

    await _fromNative(tester, 'summaryDone', null);
    await tester.pump();

    expect(find.byKey(_text), findsOneWidget);
    expect(find.textContaining('The actual answer is 42.'), findsOneWidget);
    expect(find.textContaining('supporting fact'), findsOneWidget);
    expect(find.byKey(_loading), findsNothing);
  });

  testWidgets('a short summary does not scroll', (tester) async {
    _mockNative(tester);
    await _pumpSheet(tester);
    await _fromNative(tester, 'summaryChunk', 'One short focal fact.');
    await _fromNative(tester, 'summaryDone', null);
    await tester.pump();

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.maxScrollExtent, 0,
        reason: 'Content fits, so there is nothing to scroll.');
  });

  testWidgets('an oversized summary becomes scrollable instead of clipping',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _mockNative(tester);
    await _pumpSheet(tester);
    // At the formatter's backstop ceiling — well beyond the prompt's budget.
    await _fromNative(
        tester, 'summaryChunk', List.generate(320, (i) => 'word$i').join(' '));
    await _fromNative(tester, 'summaryDone', null);
    await tester.pump();

    expect(tester.takeException(), isNull,
        reason: 'Overflow must scroll, not throw or clip.');

    final scrollable = find.byType(Scrollable);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.physics, isNot(isA<NeverScrollableScrollPhysics>()));

    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pump();
    expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(0),
        reason: 'The user must actually be able to reach the bottom.');
  });

  // NB: this used to assert that a maximum-budget summary fits on one
  // Pixel-class page with no scrolling, per an earlier PRD sentence. It was
  // red on main: a compliant summary (one focal line + five bullets, ~270
  // words) lays out well past a ~914px logical page at the body
  // density this sheet uses. The PRD has been amended to say scrolling is
  // the normal case — readability of the summary text was chosen over
  // fitting it above the fold — so what actually needs guarding is that the
  // whole summary stays *reachable*, which is asserted here and by the
  // 'oversized summary becomes scrollable' test above.
  testWidgets(
      'a maximum-budget summary lays out without overflow and stays fully '
      'reachable by scrolling', (tester) async {
    // Pixel-class portrait: 1080x2400 physical @ 2.625 dpr = ~412x914 logical.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    _mockNative(tester);
    await _pumpSheet(tester);
    await _fromNative(tester, 'summaryChunk', _maxLengthSummary());
    await _fromNative(tester, 'summaryDone', null);
    await tester.pump();

    // No RenderFlex overflow or any other layout exception — it scrolls
    // rather than clipping.
    expect(tester.takeException(), isNull);

    final scrollable = find.byType(Scrollable);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0),
        reason: 'a full-budget summary is expected to exceed one page');

    // The copy button at the very bottom must be reachable. A large,
    // deliberately oversized drag — clamped by the scrollable's own physics
    // at its true end — is more robust than sizing this to one fixture's
    // exact height, which is what broke when the fixture grew.
    await tester.drag(scrollable, const Offset(0, -5000));
    await tester.pumpAndSettle();

    final copyButton = find.byIcon(Icons.copy_rounded);
    expect(copyButton, findsOneWidget);
    const logicalHeight = 2400 / 2.625;
    expect(tester.getBottomRight(copyButton).dy, lessThan(logicalHeight),
        reason: 'after scrolling to the end, the last control is on-screen');
  });

  testWidgets('the article reaches the native call inside the prompt',
      (tester) async {
    // The sheet used to hand the native side a title and a body to build a
    // prompt from. It now hands over a finished prompt, because the cloud
    // fallback shares the same builder and a second copy of those rules on
    // the Kotlin side is how the two would drift apart.
    final calls = <Map<Object?, Object?>>[];
    _mockNative(tester, summarizeCalls: calls);
    await _pumpSheet(tester);

    expect(calls, hasLength(1));
    final prompt = calls.single['prompt'] as String;
    expect(prompt, contains("Title: You Won't Believe What This Startup Did"));
    expect(prompt, contains('Content: Some article body text.'));
  });

  testWidgets('shows unavailable message on native summaryError',
      (tester) async {
    _mockNative(tester);
    await _pumpSheet(tester);

    await _fromNative(tester, 'summaryError', 'Inference failed');
    await tester.pump();

    expect(find.byKey(_unavailable), findsOneWidget);
    expect(find.byKey(_loading), findsNothing);
    expect(find.byKey(_text), findsNothing);
  });

  testWidgets('shows unavailable message when the stream completes empty',
      (tester) async {
    _mockNative(tester);
    await _pumpSheet(tester);

    await _fromNative(tester, 'summaryDone', null); // no chunks at all
    await tester.pump();

    expect(find.byKey(_unavailable), findsOneWidget);
    expect(find.byKey(_text), findsNothing);
  });

  testWidgets('shows unavailable message when Gemini Nano is not supported',
      (tester) async {
    _mockNative(tester, available: false);
    await _pumpSheet(tester);

    expect(find.byKey(_unavailable), findsOneWidget);
    expect(find.byKey(_loading), findsNothing);
  });

  testWidgets('a real error survives the stream closing after it',
      (tester) async {
    // A stream that errors also closes, so onError and onDone both run. The
    // generic "empty" message used to overwrite the real reason a moment
    // after it arrived -- which is how a 404 naming the exact problem
    // ("this model is no longer available to new users") reached the sheet
    // as "Empty summary returned", with the useful half thrown away.
    _mockNative(tester);
    await _pumpSheet(tester);

    await _fromNative(tester, 'summaryError', 'HTTP 404: model retired');
    await tester.pump();

    expect(find.byKey(_unavailable), findsOneWidget);
    expect(find.text('Show details'), findsOneWidget);
    await tester.tap(find.text('Show details'));
    await tester.pumpAndSettle();

    expect(find.text('HTTP 404: model retired'), findsOneWidget,
        reason: 'the detail behind "Show details" has to be the reason it '
            'actually failed, not a generic stand-in');
    expect(find.text('Empty summary returned'), findsNothing);
  });
}
