import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin Flutter wrapper around the native Gemini Nano (Android AICore) bridge.
///
/// All methods degrade gracefully when the device doesn't support AICore.
class GeminiNanoService {
  static const _channel = MethodChannel('io.getflash.app/gemini_nano');

  static GeminiNanoService? _instance;
  static GeminiNanoService get instance => _instance ??= GeminiNanoService._();

  /// Test-only: clears the singleton (and its cached availability) so each
  /// test starts from a clean state. No-op impact on production code paths.
  @visibleForTesting
  static void resetForTesting() {
    _instance = null;
  }

  GeminiNanoService._() {
    // Handle native→Flutter calls (streaming summary chunks)
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  // ── Availability ─────────────────────────────────────────────────────────

  bool? _available;
  String? _unavailableReason;

  String? get unavailableReason => _unavailableReason;

  Future<bool> get isAvailable async {
    if (_available != null) return _available!;
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      _available = result ?? false;
    } on PlatformException catch (e) {
      // Don't cache DOWNLOADING — let it retry next open
      _available = e.code == 'NANO_DOWNLOADING' ? null : false;
      _unavailableReason = e.code == 'NANO_DOWNLOADING' ? e.message : '${e.code}: ${e.message}';
    } catch (e) {
      _available = false;
      _unavailableReason = e.toString();
    }
    return _available ?? false;
  }

  // ── Streaming summarise ───────────────────────────────────────────────────

  StreamController<String>? _summaryController;
  String _summaryBuffer = '';

  /// Monotonic id for the current generation. Dismissing the sheet and
  /// opening another article cannot stop the native coroutine already in
  /// flight (GeminiNanoPlugin runs it under a 20s withTimeout), so every
  /// callback carries the id of the request that produced it and anything
  /// from a superseded request is dropped. Without this, a stale generation's
  /// chunks were appended to the new article's buffer and its summaryDone
  /// closed the new article's stream.
  int _requestId = 0;

  /// Native sends `{'requestId': int, 'value': ...}`.
  Future<void> _handleNativeCall(MethodCall call) async {
    final args = call.arguments;
    final int? id;
    final Object? value;
    if (args is Map) {
      id = args['requestId'] as int?;
      value = args['value'];
    } else {
      id = null;
      value = args;
    }

    // Drop anything that isn't from the request currently on screen.
    if (id != null && id != _requestId) return;

    switch (call.method) {
      case 'summaryChunk':
        _summaryBuffer += (value as String? ?? '');
        _summaryController?.add(_summaryBuffer);
      case 'summaryDone':
        await _summaryController?.close();
        _summaryController = null;
      case 'summaryError':
        _summaryController?.addError(value as String? ?? 'Unknown error');
        await _summaryController?.close();
        _summaryController = null;
    }
  }

  /// Starts streaming a summary. Returns a [Stream<String>] that emits the
  /// accumulated text so far on each new chunk, finishing when generation ends.
  /// Returns null if unavailable.
  Future<Stream<String>?> summarizeStream(String title, String content, {String locale = 'en'}) async {
    if (!await isAvailable) return null;

    // Retire any in-progress summary: bumping the id makes every remaining
    // callback from it a no-op, so it can't write into what follows.
    final id = ++_requestId;
    await _summaryController?.close();
    _summaryBuffer = '';
    final controller = StreamController<String>();
    _summaryController = controller;

    // Fire-and-forget — result is null (acknowledged immediately by native)
    unawaited(_channel.invokeMethod<void>('summarize', {
      'requestId': id,
      'title': title,
      'content': content,
      'locale': locale,
    }).catchError((_) {
      if (id != _requestId) return;
      controller.addError('Failed to start summarization');
      controller.close();
      if (identical(_summaryController, controller)) _summaryController = null;
    }));

    return controller.stream;
  }

}
