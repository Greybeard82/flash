import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'summary_formatter.dart' show kSummaryLengthStandard;
import 'summary_prompt_builder.dart';

/// Which backend a summary should come from.
///
/// One rule, named rather than left inline at the call site: **Nano wins
/// wherever it exists.** It is free, private and works offline, so the cloud
/// is reached only when there is no Nano to use — never as a way to override
/// it, and never when this build carries no key.
bool shouldUseCloud({
  required bool nanoAvailable,
  required bool cloudConfigured,
}) =>
    !nanoAvailable && cloudConfigured;

/// Summarising via the Gemini API, for devices that have no Nano.
///
/// Reached only when [GeminiNanoService.isAvailable] is false. Nano is always
/// preferred where it exists: it is free, private and offline, and this path
/// is a fallback rather than an alternative.
///
/// The prompt comes from [buildSummaryPrompt], the same function the Nano
/// path uses, so both backends are asked for the same thing in the same
/// words and `SummaryFormatter` clamps both the same way afterwards.
class GeminiCloudService {
  /// ---------------------------------------------------------------------
  /// TEST BUILD ONLY — NOT A SHIPPABLE WAY TO HOLD A KEY.
  ///
  /// This is a compile-time key, baked into one APK with
  /// `--dart-define=GEMINI_API_KEY=...` for testing on David's own three
  /// devices. A `String.fromEnvironment` value is embedded in the binary in
  /// clear text: anyone with the APK can extract it in seconds. That is
  /// acceptable for a build that never leaves his hands and unacceptable for
  /// one that does.
  ///
  /// Shipping this to real users needs a backend holding the real key, with
  /// the app calling that instead — a separate problem this pass does not
  /// touch and does not answer. If you are reading this while preparing a
  /// release, this is the thing that is not done.
  /// ---------------------------------------------------------------------
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// The flash-lite tier this project planned around.
  ///
  /// Not `gemini-2.5-flash-lite`, which the pass that added this asked for:
  /// it still appears in the models list but the API refuses it outright for
  /// keys created since it was retired --
  ///
  ///   404: This model models/gemini-2.5-flash-lite is no longer available
  ///   to new users. Please update your code to use
  ///   models/gemini-3.5-flash-lite
  ///
  /// -- so it was never going to work on this build. Same tier, current
  /// generation, and the replacement Google's own error names.
  static const String _model = 'gemini-3.5-flash-lite';

  /// A whole generation, not just the connection. A hung request must not
  /// leave the sheet on "Writing…" indefinitely.
  static const Duration _deadline = Duration(seconds: 15);

  /// True when a key was compiled into this build.
  bool get isConfigured => _apiKey.isNotEmpty;

  /// Seam for tests: lets the routing be exercised without a real key or a
  /// network, since [_apiKey] is a compile-time constant and cannot be set.
  static bool? configuredOverrideForTesting;

  bool get configured => configuredOverrideForTesting ?? isConfigured;

  final http.Client _client;

  GeminiCloudService({http.Client? client}) : _client = client ?? http.Client();

  /// Mirrors [GeminiNanoService.summarizeStream]: emits the accumulated text
  /// so far on each chunk, and closes when generation ends. Null when no key
  /// is configured, which is the caller's signal to fall through.
  ///
  /// Errors arrive on the stream rather than as exceptions, again matching
  /// the Nano path, so the sheet has one way of handling failure.
  Future<Stream<String>?> summarizeStream(String title, String content,
      {String locale = 'en',
      String lengthTier = kSummaryLengthStandard}) async {
    if (!configured) return null;

    final prompt = buildSummaryPrompt(
      title: title,
      content: content,
      langInstruction: summaryLangInstructionFor(locale),
      lengthTier: lengthTier,
    );

    final controller = StreamController<String>();
    unawaited(_run(prompt, controller));
    return controller.stream;
  }

  Future<void> _run(String prompt, StreamController<String> out) async {
    // `alt=sse` turns the streaming endpoint into ordinary server-sent
    // events — one `data: {json}` line per chunk — which is a few lines to
    // parse. Without it the same endpoint returns a JSON array that only
    // becomes valid once the last byte arrives, which would mean waiting for
    // the whole response and giving up the live-text behaviour Nano has.
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$_model:streamGenerateContent?alt=sse');

    var buffer = '';
    try {
      final request = http.Request('POST', uri)
        ..headers['content-type'] = 'application/json'
        ..headers['x-goog-api-key'] = _apiKey
        ..body = jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
        });

      final response = await _client.send(request).timeout(_deadline);

      if (response.statusCode != 200) {
        // Read the body for the message Google puts in it — "API key not
        // valid", a quota name — which is the part worth showing under
        // "Show details".
        final body = await response.stream.bytesToString().timeout(_deadline);
        out.addError('HTTP ${response.statusCode}: ${_apiError(body)}');
        await out.close();
        return;
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_deadline);

      await for (final line in lines) {
        if (!line.startsWith('data:')) continue;
        final payload = line.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        final text = _textFrom(payload);
        if (text == null || text.isEmpty) continue;
        buffer += text;
        if (!out.isClosed) out.add(buffer);
      }

      if (buffer.isEmpty) out.addError('Empty response from the model');
      await out.close();
    } on TimeoutException {
      if (buffer.isNotEmpty) {
        // Partial text is still worth keeping — the formatter will clamp it,
        // and half a summary reads better than an error over nothing.
        if (!out.isClosed) out.add(buffer);
        await out.close();
        return;
      }
      out.addError('Timed out after ${_deadline.inSeconds}s');
      await out.close();
    } catch (e) {
      out.addError(e.toString());
      if (!out.isClosed) await out.close();
    }
  }

  /// The text of one SSE chunk, or null if this chunk carries none — a
  /// safety-block verdict or a usage-metadata-only frame, both of which are
  /// normal and must not be mistaken for a failure.
  static String? _textFrom(String jsonLine) {
    try {
      final decoded = jsonDecode(jsonLine);
      if (decoded is! Map) return null;
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) return null;
      final content = (candidates.first as Map)['content'];
      if (content is! Map) return null;
      final parts = content['parts'];
      if (parts is! List || parts.isEmpty) return null;
      final buf = StringBuffer();
      for (final part in parts) {
        if (part is Map && part['text'] is String) buf.write(part['text']);
      }
      return buf.toString();
    } catch (_) {
      // A malformed frame mid-stream is not worth failing the whole
      // generation over; the ones around it still carry text.
      return null;
    }
  }

  /// Pulls Google's own message out of an error body, falling back to the
  /// raw body when the shape is not what we expect.
  static String _apiError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final message = (decoded['error'] as Map)['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // fall through
    }
    return body.length > 200 ? '${body.substring(0, 200)}…' : body;
  }
}
