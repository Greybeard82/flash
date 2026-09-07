// The cloud fallback, and the one rule that decides when it is used.
//
// Nano wins wherever it exists. The cloud is for devices that have none — a
// Samsung, a Lenovo tablet — and never a way to override Nano on a Pixel.
// That rule is a named predicate rather than an inline `&&` at the call site
// precisely so it can be stated once and asserted here.
//
// The transport is exercised through an injected client: no network, no key,
// but the real SSE parsing, the real error shapes and the real timeout.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:flash/services/gemini_cloud_service.dart';
import 'package:flash/services/summary_formatter.dart';

/// One `data:` frame as the API sends them.
String _frame(String text) => 'data: ${jsonEncode({
      'candidates': [
        {
          'content': {
            'parts': [
              {'text': text}
            ]
          }
        }
      ]
    })}\n\n';

/// A client that replays a canned response body.
class _FakeClient extends http.BaseClient {
  final int status;
  final String body;
  http.BaseRequest? seen;

  _FakeClient({this.status = 200, required this.body});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    seen = request;
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      request: request,
    );
  }
}

/// A client whose response never arrives.
class _HangingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}

Future<List<String>> _collect(Stream<String> s) => s.toList();

void main() {
  setUp(() => GeminiCloudService.configuredOverrideForTesting = true);
  tearDown(() => GeminiCloudService.configuredOverrideForTesting = null);

  group('which backend runs a summary', () {
    test('Nano available: the cloud is never reached, key or no key', () {
      expect(shouldUseCloud(nanoAvailable: true, cloudConfigured: true), isFalse,
          reason: 'the cloud must never override Nano on a device that has '
              'it — Nano is free, private and offline');
      expect(
          shouldUseCloud(nanoAvailable: true, cloudConfigured: false), isFalse);
    });

    test('Nano unavailable and a key compiled in: the cloud runs', () {
      expect(shouldUseCloud(nanoAvailable: false, cloudConfigured: true), isTrue);
    });

    test('Nano unavailable and no key: nothing runs, so the old message shows',
        () {
      expect(shouldUseCloud(nanoAvailable: false, cloudConfigured: false), isFalse,
          reason: 'a build without a key has to behave exactly as it did '
              'before this feature existed');
    });
  });

  group('an unconfigured build', () {
    test('hands back null so the caller falls through', () async {
      GeminiCloudService.configuredOverrideForTesting = false;
      final stream = await GeminiCloudService(client: _FakeClient(body: ''))
          .summarizeStream('t', 'c');
      expect(stream, isNull);
    });
  });

  group('streaming', () {
    test('emits the accumulated text, matching the Nano contract', () async {
      // The sheet keeps only the latest value it is handed, so each event has
      // to be the whole summary so far — not the delta.
      final client = _FakeClient(
          body: _frame('The Bank ') + _frame('of England ') + _frame('warned.'));
      final stream = await GeminiCloudService(client: client)
          .summarizeStream('Title', 'Body');

      expect(await _collect(stream!),
          ['The Bank ', 'The Bank of England ', 'The Bank of England warned.']);
    });

    test('frames carrying no text are skipped, not treated as failure',
        () async {
      // Usage-metadata and safety-verdict frames arrive mid-stream and carry
      // no candidate text.
      const meta = 'data: {"usageMetadata":{"totalTokenCount":9}}\n\n';
      final client = _FakeClient(body: _frame('Real text.') + meta);
      final stream = await GeminiCloudService(client: client)
          .summarizeStream('Title', 'Body');

      expect(await _collect(stream!), ['Real text.']);
    });

    test('a malformed frame does not sink the whole generation', () async {
      // A frame the parser cannot read, between two it can.
      const junk = 'data: {not json\n\n';
      final client = _FakeClient(
          body: '${_frame('Good. ')}$junk${_frame('Still good.')}');
      final stream = await GeminiCloudService(client: client)
          .summarizeStream('Title', 'Body');

      expect(await _collect(stream!), ['Good. ', 'Good. Still good.']);
    });

    test('the request carries the prompt and the tier it was asked for',
        () async {
      final client = _FakeClient(body: _frame('x'));
      final stream = await GeminiCloudService(client: client).summarizeStream(
          'A headline', 'Body text',
          lengthTier: kSummaryLengthDetailed);
      await _collect(stream!);

      final body = jsonDecode((client.seen as http.Request).body) as Map;
      final sent = ((body['contents'] as List).first as Map)['parts'];
      final text = ((sent as List).first as Map)['text'] as String;

      expect(text, contains('Title: A headline'));
      expect(text, contains('Content: Body text'));
      expect(text, contains('150-200 words'),
          reason: 'the cloud must be asked for the same tier as Nano would be');
    });

    test('the model is the tier this project planned around', () async {
      final client = _FakeClient(body: _frame('x'));
      final stream =
          await GeminiCloudService(client: client).summarizeStream('t', 'c');
      await _collect(stream!);
      // Not 2.5: the API refuses that one for keys created since it was
      // retired, naming this as the replacement. Same flash-lite tier.
      expect(client.seen!.url.toString(), contains('gemini-3.5-flash-lite'));
      expect(client.seen!.url.toString(), contains('streamGenerateContent'));
    });
  });

  group('failures reach the UI as errors, never as crashes', () {
    test('a non-200 surfaces the API message, not the raw body', () async {
      final client = _FakeClient(
          status: 400,
          body: jsonEncode({
            'error': {'message': 'API key not valid. Please pass a valid API key.'}
          }));
      final stream =
          await GeminiCloudService(client: client).summarizeStream('t', 'c');

      expect(_collect(stream!),
          throwsA(allOf(contains('HTTP 400'), contains('API key not valid'))));
    });

    test('an empty response is an error, not a blank summary', () async {
      final client = _FakeClient(body: '');
      final stream =
          await GeminiCloudService(client: client).summarizeStream('t', 'c');
      expect(_collect(stream!), throwsA(contains('Empty response')));
    });

    test('a hung request gives up rather than writing forever', () async {
      final stream = await GeminiCloudService(client: _HangingClient())
          .summarizeStream('t', 'c');
      expect(_collect(stream!), throwsA(contains('Timed out')));
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
