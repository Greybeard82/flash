import 'dart:async';

import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'summary_formatter.dart' show kSummaryLengthStandard;
import 'summary_prompt_builder.dart';

/// Which backend a summary should come from.
///
/// One rule, named rather than left inline at the call site: **Nano wins
/// wherever it exists.** It is free, private and works offline, so the cloud
/// is reached only when there is no Nano to use — never as a way to override
/// it, and never when this build cannot reach Firebase.
bool shouldUseCloud({
  required bool nanoAvailable,
  required bool cloudConfigured,
}) =>
    !nanoAvailable && cloudConfigured;

/// Produces the model's output for a prompt, one chunk at a time.
///
/// Each element is a *delta* — the newly generated text — which
/// [GeminiCloudService] accumulates before handing on. Injectable because the
/// real implementation crosses a platform channel and cannot run in a unit
/// test; this is the seam that replaced the injected `http.Client` when the
/// hand-rolled SSE parsing went away.
typedef SummaryChunks = Stream<String> Function(String prompt);

/// Summarising via Firebase AI Logic, for devices that have no Nano.
///
/// Reached only when [GeminiNanoService.isAvailable] is false. Nano is always
/// preferred where it exists: it is free, private and offline, and this path
/// is a fallback rather than an alternative.
///
/// The prompt comes from [buildSummaryPrompt], the same function the Nano
/// path uses, so both backends are asked for the same thing in the same
/// words and `SummaryFormatter` clamps both the same way afterwards.
///
/// ## Why Firebase AI Logic rather than a direct Gemini call
///
/// This used to hold a `String.fromEnvironment('GEMINI_API_KEY')` and POST
/// straight to `generativelanguage.googleapis.com`. A compile-time key is
/// embedded in the binary in clear text and anyone with the APK can extract it
/// in seconds, so that build could never ship. Obfuscating it harder is not a
/// fix: anything inside the app can be extracted. The fix is for no key to
/// ship at all.
///
/// Requests now go to the Firebase AI Logic gateway, which holds the key
/// server-side and verifies an App Check token — Play Integrity, attesting a
/// genuine untampered build — *before* the request reaches the Gemini backend.
/// See app_check_config.dart for the one trap this creates locally.
///
/// Note what did **not** come back with the Firebase dependency: no Google
/// Sign-In, no OAuth, no consent screen, no user account. Flash still asks the
/// user for nothing.
class GeminiCloudService {
  /// The flash-lite tier this project planned around.
  ///
  /// Not `gemini-2.5-flash-lite`, which the pass that added this asked for:
  /// it still appeared in the models list but the API refused it outright for
  /// keys created since it was retired --
  ///
  ///   404: This model models/gemini-2.5-flash-lite is no longer available
  ///   to new users. Please update your code to use
  ///   models/gemini-3.5-flash-lite
  ///
  /// -- so it was never going to work on this build. Same tier, current
  /// generation, and the replacement Google's own error names. 2.5 Flash and
  /// 2.5 Flash-Lite shut down entirely on 16 October 2026, so the old string
  /// is now doubly dead.
  static const String _model = 'gemini-3.5-flash-lite';

  /// Exposed so the test suite can pin the model without reaching the network.
  @visibleForTesting
  static const String modelId = _model;

  /// A whole generation, not just the connection. A hung request must not
  /// leave the sheet on "Writing…" indefinitely.
  static const Duration _deadline = Duration(seconds: 15);

  /// True when Firebase has initialised, which is what "the cloud is reachable"
  /// now means — there is no key to look for any more.
  ///
  /// Guarded because reading [Firebase.apps] before the platform side is set up
  /// throws, and "cannot tell" has to resolve to "not available" rather than
  /// taking the app down at startup.
  bool get isConfigured {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Seam for tests: lets the routing be exercised without Firebase, since
  /// [isConfigured] depends on platform state a unit test has no way to create.
  static bool? configuredOverrideForTesting;

  bool get configured => configuredOverrideForTesting ?? isConfigured;

  final SummaryChunks _chunks;

  GeminiCloudService({SummaryChunks? chunks}) : _chunks = chunks ?? _liveChunks;

  /// The real backend: Gemini Developer API through Firebase AI Logic.
  ///
  /// No generation config is set. The prompt carries the length tier in words,
  /// and the sampling parameters that would otherwise go here — `temperature`,
  /// `topP`, `topK` — are deprecated on current Gemini models, so setting them
  /// would be adding a knob that is on its way out.
  static Stream<String> _liveChunks(String prompt) {
    final model = FirebaseAI.googleAI().generativeModel(model: _model);
    return model
        .generateContentStream([Content.text(prompt)])
        .map((r) => r.text ?? '');
  }

  /// Mirrors [GeminiNanoService.summarizeStream]: emits the accumulated text
  /// so far on each chunk, and closes when generation ends. Null when the
  /// cloud is not reachable, which is the caller's signal to fall through.
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
    var buffer = '';
    try {
      final chunks = _chunks(prompt).timeout(_deadline);

      await for (final delta in chunks) {
        // A text-free chunk — a safety verdict, a usage-metadata frame — is
        // normal mid-generation and must not be re-emitted as a duplicate
        // event or mistaken for a failure.
        if (delta.isEmpty) continue;
        buffer += delta;
        if (!out.isClosed) out.add(buffer);
      }

      if (buffer.isEmpty) out.addError('Empty response from the model');
      await out.close();
    } on TimeoutException {
      if (buffer.isNotEmpty) {
        // Partial text is still worth keeping — the formatter will clamp it,
        // and half a summary reads better than an error over nothing.
        //
        // Nothing is re-sent here: every non-empty delta was already emitted
        // inside the loop, so the sheet is holding the latest text and closing
        // simply leaves it on screen. The old http implementation added the
        // buffer again at this point, which emitted a value the consumer
        // already had — invisible in the UI, since the sheet keeps only the
        // last value, but a duplicate event all the same. It had no test
        // covering a timeout *after* partial text, which is why it survived.
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
}
