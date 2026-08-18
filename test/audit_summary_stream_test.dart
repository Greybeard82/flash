// Regression cover for audit finding B1.
//
// GeminiNanoService used to route every native summary callback through one
// set of mutable fields (_summaryBuffer / _summaryController) with no notion
// of which generation a chunk belonged to. Starting a second summary does not
// stop the first — GeminiNanoPlugin.summarize() launches a coroutine that
// keeps emitting for up to its 20s withTimeout — so a stale generation's
// chunks were appended to the new article's buffer and its summaryDone closed
// the new article's stream.
//
// Real-world trigger: open the AI summary sheet on article A, dismiss it,
// open it on article B within ~20s. B showed A's text, or ended empty.
//
// Every callback now carries the requestId it belongs to (see the `reply()`
// helper in GeminiNanoPlugin.kt) and anything from a superseded request is
// dropped. These tests speak that envelope.
//
// No DB involvement — this drives the method channel directly.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/gemini_nano_service.dart';

const _channelName = 'io.getflash.app/gemini_nano';
const _codec = StandardMethodCodec();

/// Simulates the native side calling back into Dart, in the same
/// `{requestId, value}` envelope GeminiNanoPlugin.reply() sends.
Future<void> _nativeCall(String method, int requestId, Object? value) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _channelName,
    _codec.encodeMethodCall(
        MethodCall(method, {'requestId': requestId, 'value': value})),
    (_) {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GeminiNanoService.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(_channelName),
            (call) async {
      // Native acknowledges both calls; generation itself is async and is
      // simulated by the _nativeCall() callbacks in each test.
      if (call.method == 'isAvailable') return true;
      if (call.method == 'summarize') return null;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(_channelName), null);
    GeminiNanoService.resetForTesting();
  });

  test('baseline: a single summary streams its own chunks through', () async {
    final service = GeminiNanoService.instance;
    final stream = await service.summarizeStream('Article A', 'body A');
    expect(stream, isNotNull);

    final received = <String>[];
    final sub = stream!.listen(received.add);

    await _nativeCall('summaryChunk', 1, 'Hello ');
    await _nativeCall('summaryChunk', 1, 'world');
    await _nativeCall('summaryDone', 1, null);
    await Future<void>.delayed(Duration.zero);

    expect(received.last, 'Hello world');
    await sub.cancel();
  });

  test('a still-running generation cannot leak its chunks into the next '
      'article\'s stream', () async {
    final service = GeminiNanoService.instance;

    // Article A is request 1; it starts generating and emits one chunk.
    final streamA = await service.summarizeStream('Article A', 'body A');
    final receivedA = <String>[];
    final subA = streamA!.listen(receivedA.add, onError: (_) {});
    await _nativeCall('summaryChunk', 1, 'A-CONTENT ');
    await Future<void>.delayed(Duration.zero);

    // User dismisses A and opens B (request 2) before A's coroutine finishes.
    final streamB = await service.summarizeStream('Article B', 'body B');
    final receivedB = <String>[];
    final subB = streamB!.listen(receivedB.add, onError: (_) {});

    // A's native coroutine is still alive and emits its remaining chunk,
    // still stamped with request 1.
    await _nativeCall('summaryChunk', 1, 'A-LEFTOVER');
    await Future<void>.delayed(Duration.zero);

    expect(
      receivedB.join(),
      isNot(contains('A-LEFTOVER')),
      reason: 'chunks stamped with a superseded requestId must be dropped, '
          'not appended to the current article\'s buffer',
    );

    // B's own chunk still lands.
    await _nativeCall('summaryChunk', 2, 'B-CONTENT');
    await Future<void>.delayed(Duration.zero);
    expect(receivedB.last, 'B-CONTENT');

    await subA.cancel();
    await subB.cancel();
  });

  test('the previous generation finishing does not close the current '
      'article\'s stream', () async {
    final service = GeminiNanoService.instance;

    final streamA = await service.summarizeStream('Article A', 'body A');
    final subA = streamA!.listen((_) {}, onError: (_) {});

    final streamB = await service.summarizeStream('Article B', 'body B');
    var bClosed = false;
    final subB =
        streamB!.listen((_) {}, onError: (_) {}, onDone: () => bClosed = true);

    // A (request 1) completes — this must not terminate B's stream.
    await _nativeCall('summaryDone', 1, null);
    await Future<void>.delayed(Duration.zero);

    expect(bClosed, isFalse,
        reason: 'a superseded generation finishing must not close whatever '
            'controller happens to be installed, or B ends before it has '
            'produced anything and the sheet renders "Empty summary returned"');

    // B's own completion does close it.
    await _nativeCall('summaryDone', 2, null);
    await Future<void>.delayed(Duration.zero);
    expect(bClosed, isTrue);

    await subA.cancel();
    await subB.cancel();
  });
}
