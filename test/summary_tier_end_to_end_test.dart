// The summary-length tier has to survive the whole trip: the value the
// reader picks in Quick Settings must be the value the native side is asked
// for, and the same value the formatter backstops against.
//
// This is the failure mode worth guarding. The tier is threaded through four
// places — the settings row, the sheet, GeminiNanoService, and the method
// channel — and a break anywhere in that chain is silent: summaries keep
// working, they are just the wrong length, or the prompt asks for one tier
// while the formatter trims to another. Nothing throws, so only a test that
// watches what actually crosses the channel catches it.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/gemini_nano_service.dart';
import 'package:flash/services/summary_formatter.dart';

const _channelName = 'io.getflash.app/gemini_nano';
const _codec = StandardMethodCodec();

/// Records the arguments of every `summarize` call the Dart side makes.
List<Map<Object?, Object?>> _captureSummarizeCalls(WidgetTester tester) {
  final calls = <Map<Object?, Object?>>[];
  tester.binding.defaultBinaryMessenger
      .setMockMessageHandler(_channelName, (ByteData? message) async {
    final call = _codec.decodeMethodCall(message);
    switch (call.method) {
      case 'isAvailable':
        return _codec.encodeSuccessEnvelope(true);
      case 'summarize':
        calls.add(call.arguments as Map<Object?, Object?>);
        return _codec.encodeSuccessEnvelope(null);
    }
    return null;
  });
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(GeminiNanoService.resetForTesting);

  group('the chosen tier reaches the native side', () {
    for (final tier in [
      kSummaryLengthShort,
      kSummaryLengthStandard,
      kSummaryLengthDetailed,
    ]) {
      testWidgets('$tier is sent as lengthTier', (tester) async {
        final calls = _captureSummarizeCalls(tester);

        await GeminiNanoService.instance
            .summarizeStream('Title', 'Body text', lengthTier: tier);
        await tester.pump();

        expect(calls, hasLength(1));
        expect(calls.single['lengthTier'], tier,
            reason: 'the tier the reader picked has to be what the prompt '
                'is built from');
      });
    }

    testWidgets('the default is standard when no tier is given',
        (tester) async {
      final calls = _captureSummarizeCalls(tester);

      await GeminiNanoService.instance.summarizeStream('Title', 'Body text');
      await tester.pump();

      expect(calls.single['lengthTier'], kSummaryLengthStandard);
    });

    testWidgets('the other arguments are still sent alongside it',
        (tester) async {
      // Guards against the tier being threaded in by replacing something
      // rather than adding to it.
      final calls = _captureSummarizeCalls(tester);

      await GeminiNanoService.instance.summarizeStream('The Title', 'The body',
          locale: 'fr', lengthTier: kSummaryLengthDetailed);
      await tester.pump();

      final args = calls.single;
      expect(args['title'], 'The Title');
      expect(args['content'], 'The body');
      expect(args['locale'], 'fr');
      expect(args['lengthTier'], kSummaryLengthDetailed);
      expect(args['requestId'], isA<int>());
    });
  });

  group('the settings value and the formatter agree', () {
    // The sheet reads one tier and hands it to both the request and the
    // clamp. If the stored strings and the formatter's table ever drift
    // apart, the clamp silently falls back to standard while the prompt
    // asks for something else.
    test('every storable tier has its own limits', () {
      for (final tier in [
        kSummaryLengthShort,
        kSummaryLengthStandard,
        kSummaryLengthDetailed,
      ]) {
        expect(kSummaryTierLimits.containsKey(tier), isTrue,
            reason: '"$tier" is a value the settings row can store, so the '
                'formatter must know it rather than silently defaulting');
      }
    });

    test('the tier table holds exactly the three storable tiers', () {
      expect(kSummaryTierLimits.keys, hasLength(3),
          reason: 'three fixed tiers — no fourth tier, no free-form value');
    });
  });
}
