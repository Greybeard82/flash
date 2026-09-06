import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/l10n/app_localizations.dart';
import 'package:flash/models/article.dart';
import 'package:flash/screens/article_summary_sheet.dart';
import 'package:flash/services/article_extractor.dart';
import 'package:flash/services/gemini_nano_service.dart';
import 'package:flash/services/summary_cache.dart';

const _channelName = 'io.getflash.app/gemini_nano';
const _codec = StandardMethodCodec();

const _loading = ValueKey('summaryLoading');
const _text = ValueKey('summaryText');
const _unavailable = ValueKey('summaryUnavailable');

const _url = 'https://example.com/a';

Article _article() => const Article(
      feedId: 1,
      guid: 'guid-1',
      title: 'These 4 Games Are Free This Month',
      url: _url,
      description: 'Some article body text.',
      fetchedAt: 0,
    );

/// `methods` records every native method invoked, so a test can assert that
/// inference was skipped entirely.
void _mockNative(WidgetTester tester,
    {bool available = true, List<String>? methods}) {
  tester.binding.defaultBinaryMessenger
      .setMockMessageHandler(_channelName, (ByteData? message) async {
    final call = _codec.decodeMethodCall(message);
    methods?.add(call.method);
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
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GeminiNanoService.resetForTesting();
    SummaryCache.instance.clear();
  });

  group('extraction timeout', () {
    test('extraction has exactly one ceiling: the extractor\'s own', () {
      expect(ArticleExtractor.networkTimeout, const Duration(seconds: 8),
          reason: 'This used to race a second, tighter timeout in '
              'ArticleSummarySheet, which fired first almost every time and '
              'silently discarded every real fetch in favour of the RSS '
              'teaser. There must be exactly one clock on this operation '
              'now, owned by the extractor.');
    });
  });

  group('cache short-circuit', () {
    testWidgets('a cached summary renders without any inference call',
        (tester) async {
      SummaryCache.instance.put(_url, 'Four games are free.\n- Sifu');

      final methods = <String>[];
      _mockNative(tester, methods: methods);
      await _pumpSheet(tester);

      expect(find.byKey(_text), findsOneWidget);
      expect(find.byKey(_loading), findsNothing);
      expect(find.textContaining('Four games are free.'), findsOneWidget);
      expect(methods, isNot(contains('summarize')),
          reason: 'A cache hit must not reach the model.');
    });

    testWidgets('an uncached article does reach the model', (tester) async {
      final methods = <String>[];
      _mockNative(tester, methods: methods);
      await _pumpSheet(tester);

      expect(methods, contains('summarize'));
      expect(find.byKey(_loading), findsOneWidget);
    });

    testWidgets('a completed summary is cached', (tester) async {
      _mockNative(tester);
      await _pumpSheet(tester);

      await _fromNative(tester, 'summaryChunk', 'Four games are free.');
      await _fromNative(tester, 'summaryDone', null);
      await tester.pump();

      expect(SummaryCache.instance.get(_url), 'Four games are free.');
    });

    testWidgets('the cached value is the clamped text, not the raw stream',
        (tester) async {
      _mockNative(tester);
      await _pumpSheet(tester);

      await _fromNative(
          tester, 'summaryChunk', 'Summary:\nFour **games** are free.');
      await _fromNative(tester, 'summaryDone', null);
      await tester.pump();

      expect(SummaryCache.instance.get(_url), 'Four games are free.',
          reason: 'Clamp runs before caching, so preamble and markdown are '
              'stripped once rather than on every read.');
    });

    testWidgets('an errored summary is not cached', (tester) async {
      _mockNative(tester);
      await _pumpSheet(tester);

      await _fromNative(tester, 'summaryError', 'Inference failed');
      await tester.pump();

      expect(find.byKey(_unavailable), findsOneWidget);
      expect(SummaryCache.instance.contains(_url), isFalse,
          reason: 'A failure must not poison the cache for the session.');
    });

    testWidgets('an empty stream result is not cached', (tester) async {
      _mockNative(tester);
      await _pumpSheet(tester);

      await _fromNative(tester, 'summaryDone', null);
      await tester.pump();

      expect(SummaryCache.instance.contains(_url), isFalse);
    });

    testWidgets('an unavailable model does not cache anything', (tester) async {
      _mockNative(tester, available: false);
      await _pumpSheet(tester);

      expect(find.byKey(_unavailable), findsOneWidget);
      expect(SummaryCache.instance.contains(_url), isFalse);
    });
  });

  group('clamping is applied to displayed output', () {
    testWidgets('a runaway stream result is clamped before display',
        (tester) async {
      final runaway = List.generate(400, (i) => 'word$i').join(' ');

      _mockNative(tester);
      await _pumpSheet(tester);
      await _fromNative(tester, 'summaryChunk', runaway);
      await _fromNative(tester, 'summaryDone', null);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('word320'), findsNothing);
    });
  });
}
