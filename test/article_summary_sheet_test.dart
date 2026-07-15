import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/screens/article_summary_sheet.dart';
import 'package:flash/services/gemini_nano_service.dart';

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
    home: Scaffold(body: ArticleSummarySheet(article: _article())),
  ));
  // Let the isAvailable + summarize method-channel round-trips complete.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// A summary at the prompt's maximum budget: 1 focal sentence + 3 bullets,
/// under 60 words total. If this fits on one page, any compliant output fits.
String _maxLengthSummary() {
  const focal =
      'The startup actually shut down after losing its largest client, '
      'which accounted for most of its recurring annual revenue stream.'; // 20 words
  final bullets = List.generate(
      3,
      (i) =>
          '- Point number ${i + 1} covers one additional relevant reported '
          'fact with names and figures'); // 12 words each
  return '$focal\n${bullets.join('\n')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(GeminiNanoService.resetForTesting);

  testWidgets('shows only loading animation while chunks stream in — '
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

  testWidgets('summary area is not user-scrollable', (tester) async {
    _mockNative(tester);
    await _pumpSheet(tester);
    await _fromNative(tester, 'summaryChunk', _maxLengthSummary());
    await _fromNative(tester, 'summaryDone', null);
    await tester.pump();

    final scrollView = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    expect(scrollView.physics, isA<NeverScrollableScrollPhysics>());
  });

  testWidgets('a maximum-budget summary fits on one Pixel-class page '
      'with no overflow and no scrolling', (tester) async {
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

    // No RenderFlex overflow or any other layout exception.
    expect(tester.takeException(), isNull);

    // The last interactive element (copy button, below the summary) must be
    // fully on-screen — i.e. the whole summary fits without scrolling.
    final copyButton = find.byIcon(Icons.copy_rounded);
    expect(copyButton, findsOneWidget);
    final logicalHeight = 2400 / 2.625;
    expect(tester.getBottomRight(copyButton).dy, lessThan(logicalHeight));
  });

  testWidgets('passes title and content to the native summarize call',
      (tester) async {
    final calls = <Map<Object?, Object?>>[];
    _mockNative(tester, summarizeCalls: calls);
    await _pumpSheet(tester);

    expect(calls, hasLength(1));
    expect(calls.single['title'], "You Won't Believe What This Startup Did");
    expect(calls.single['content'], 'Some article body text.');
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
}
