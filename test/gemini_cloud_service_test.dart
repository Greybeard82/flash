// The cloud fallback, and the one rule that decides when it is used.
//
// Nano wins wherever it exists. The cloud is for devices that have none — a
// Samsung, a Lenovo tablet — and never a way to override Nano on a Pixel.
// That rule is a named predicate rather than an inline `&&` at the call site
// precisely so it can be stated once and asserted here.
//
// ── What changed when the API key went away ──────────────────────────────
//
// This file used to inject an `http.Client` and assert against hand-rolled
// server-sent-event parsing: `data:` frames, malformed frames, usage-metadata
// frames. None of that code exists any more. Requests now go through Firebase
// AI Logic, which holds the key server-side and gates access with App Check,
// and the SDK owns the wire format — so tests of *our* SSE parser would now be
// tests of deleted code.
//
// What survives is the part that was never about the transport: the streaming
// contract the sheet depends on (accumulated text, not deltas), errors arriving
// on the stream rather than as exceptions, the deadline, and prompt parity with
// the Nano path. Those are pinned here through an injected chunk stream, which
// is the seam that replaced the http.Client — see `SummaryChunks`.
//
// The SDK call itself crosses a platform channel and cannot run here. That gap
// is covered by the device pass in MANUAL_QA.md.

import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/app_check_config.dart';
import 'package:flash/services/gemini_cloud_service.dart';
import 'package:flash/services/summary_formatter.dart';
import 'package:flash/services/summary_prompt_builder.dart';

/// A seam that replays canned chunks, the way the SDK hands them over:
/// each one a *delta*, which the service is responsible for accumulating.
SummaryChunks _chunks(List<String> parts) =>
    (prompt) => Stream.fromIterable(parts);

/// Captures the prompt it was handed, then replays [parts].
class _Recorder {
  String? prompt;
  final List<String> parts;
  _Recorder(this.parts);

  Stream<String> call(String p) {
    prompt = p;
    return Stream.fromIterable(parts);
  }
}

Future<List<String>> _collect(Stream<String> s) => s.toList();

void main() {
  setUp(() => GeminiCloudService.configuredOverrideForTesting = true);
  tearDown(() => GeminiCloudService.configuredOverrideForTesting = null);

  group('which backend runs a summary', () {
    test('Nano available: the cloud is never reached, configured or not', () {
      expect(shouldUseCloud(nanoAvailable: true, cloudConfigured: true), isFalse,
          reason: 'the cloud must never override Nano on a device that has '
              'it — Nano is free, private and offline');
      expect(
          shouldUseCloud(nanoAvailable: true, cloudConfigured: false), isFalse);
    });

    test('Nano unavailable and Firebase ready: the cloud runs', () {
      expect(
          shouldUseCloud(nanoAvailable: false, cloudConfigured: true), isTrue);
    });

    test('Nano unavailable and Firebase not ready: nothing runs', () {
      expect(
          shouldUseCloud(nanoAvailable: false, cloudConfigured: false), isFalse,
          reason: 'a build that cannot reach Firebase has to behave exactly '
              'as a keyless build did before this migration');
    });
  });

  group('an unconfigured build', () {
    test('hands back null so the caller falls through', () async {
      GeminiCloudService.configuredOverrideForTesting = false;
      final stream = await GeminiCloudService(chunks: _chunks(['x']))
          .summarizeStream('t', 'c');
      expect(stream, isNull);
    });
  });

  group('streaming', () {
    test('emits the accumulated text, matching the Nano contract', () async {
      // The sheet keeps only the latest value it is handed, so each event has
      // to be the whole summary so far — not the delta the SDK gives us.
      final stream =
          await GeminiCloudService(chunks: _chunks(['The Bank ', 'of England ', 'warned.']))
              .summarizeStream('Title', 'Body');

      expect(await _collect(stream!),
          ['The Bank ', 'The Bank of England ', 'The Bank of England warned.']);
    });

    test('empty chunks are skipped rather than re-emitting the same text',
        () async {
      // The SDK yields text-free chunks — a safety verdict, a usage-metadata
      // frame — and those must not show up as duplicate events.
      final stream =
          await GeminiCloudService(chunks: _chunks(['Real text.', '', '']))
              .summarizeStream('Title', 'Body');

      expect(await _collect(stream!), ['Real text.']);
    });

    test('an empty response is an error, not a blank summary', () async {
      final stream = await GeminiCloudService(chunks: _chunks([]))
          .summarizeStream('t', 'c');
      expect(_collect(stream!), throwsA(contains('Empty response')));
    });

    test('an SDK failure reaches the UI as a stream error, never a crash',
        () async {
      final stream = await GeminiCloudService(
              chunks: (_) => Stream.error(StateError('App Check rejected')))
          .summarizeStream('t', 'c');
      expect(_collect(stream!), throwsA(contains('App Check rejected')));
    });

    test('a hung request gives up rather than writing forever', () async {
      // Never emits, never closes — the deadline is the only thing that can
      // end this, and without it the sheet sits on "Writing…" indefinitely.
      final stream =
          await GeminiCloudService(chunks: (_) => StreamController<String>().stream)
              .summarizeStream('t', 'c');
      expect(_collect(stream!), throwsA(contains('Timed out')));
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('partial text survives a timeout rather than becoming an error',
        () async {
      // Half a summary reads better than an error over nothing, and the
      // formatter clamps it the same way either way.
      final controller = StreamController<String>();
      controller.add('Half a summary');
      final stream = await GeminiCloudService(chunks: (_) => controller.stream)
          .summarizeStream('t', 'c');

      expect(await _collect(stream!), ['Half a summary']);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('prompt parity with the Nano path', () {
    test('the cloud is asked for byte-for-byte what Nano would be asked for',
        () async {
      // Both backends call buildSummaryPrompt with the same arguments. If one
      // drifts, the two produce differently-shaped summaries for the same
      // article and nothing else would catch it.
      final rec = _Recorder(['x']);
      final stream = await GeminiCloudService(chunks: rec.call).summarizeStream(
          'A headline', 'Body text',
          locale: 'es', lengthTier: kSummaryLengthDetailed);
      await _collect(stream!);

      expect(
        rec.prompt,
        buildSummaryPrompt(
          title: 'A headline',
          content: 'Body text',
          langInstruction: summaryLangInstructionFor('es'),
          lengthTier: kSummaryLengthDetailed,
        ),
      );
    });

    test('the tier reaches the prompt', () async {
      final rec = _Recorder(['x']);
      final stream = await GeminiCloudService(chunks: rec.call).summarizeStream(
          'A headline', 'Body text',
          lengthTier: kSummaryLengthDetailed);
      await _collect(stream!);

      expect(rec.prompt, contains('Title: A headline'));
      expect(rec.prompt, contains('Content: Body text'));
      expect(rec.prompt, contains('150-200 words'),
          reason: 'the cloud must be asked for the same tier as Nano would be');
    });
  });

  group('the model', () {
    test('is the flash-lite tier this project planned around', () {
      // Not gemini-2.5-flash-lite: the API refused it for keys created since
      // it was retired, naming this as the replacement — and 2.5 Flash and
      // 2.5 Flash-Lite shut down entirely on 16 October 2026.
      expect(GeminiCloudService.modelId, 'gemini-3.5-flash-lite');
    });
  });

  group('App Check provider selection', () {
    // The trap this guards: local device builds are *release* builds, so
    // keying off kDebugMode would pick Play Integrity for a sideloaded APK
    // that Play cannot attest — and every cloud summary would fail on exactly
    // the devices used for testing.
    test('an ordinary build attests with Play Integrity', () {
      expect(appCheckProviderFor(debug: false),
          isA<AndroidPlayIntegrityProvider>());
    });

    test('a build with APP_CHECK_DEBUG uses the debug provider', () {
      expect(appCheckProviderFor(debug: true), isA<AndroidDebugProvider>());
    });

    test('the shipped default follows the compile-time flag', () {
      // Nothing sets APP_CHECK_DEBUG when the suite runs, so the default must
      // be the attesting one. A default that silently fell back to debug would
      // ship an app that accepts unattested requests.
      expect(kAppCheckDebug, isFalse);
      expect(appCheckAndroidProvider, isA<AndroidPlayIntegrityProvider>());
    });
  });
}
