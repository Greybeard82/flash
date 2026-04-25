import 'dart:async';
import 'package:flutter/services.dart';

/// Thin Flutter wrapper around the native Gemini Nano (Android AICore) bridge.
///
/// All methods degrade gracefully when the device doesn't support AICore.
class GeminiNanoService {
  static const _channel = MethodChannel('io.getflash.app/gemini_nano');

  static GeminiNanoService? _instance;
  static GeminiNanoService get instance => _instance ??= GeminiNanoService._();

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

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'summaryChunk':
        _summaryBuffer += (call.arguments as String? ?? '');
        _summaryController?.add(_summaryBuffer);
      case 'summaryDone':
        await _summaryController?.close();
        _summaryController = null;
      case 'summaryError':
        _summaryController?.addError(call.arguments as String? ?? 'Unknown error');
        await _summaryController?.close();
        _summaryController = null;
    }
  }

  /// Starts streaming a summary. Returns a [Stream<String>] that emits the
  /// accumulated text so far on each new chunk, finishing when generation ends.
  /// Returns null if unavailable.
  Future<Stream<String>?> summarizeStream(String title, String content, {String locale = 'en'}) async {
    if (!await isAvailable) return null;

    // Cancel any in-progress summary
    await _summaryController?.close();
    _summaryBuffer = '';
    _summaryController = StreamController<String>();

    // Fire-and-forget — result is null (acknowledged immediately by native)
    unawaited(_channel.invokeMethod<void>('summarize', {
      'title': title,
      'content': content,
      'locale': locale,
    }).catchError((_) {
      _summaryController?.addError('Failed to start summarization');
      _summaryController?.close();
      _summaryController = null;
    }));

    return _summaryController!.stream;
  }

}
