import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

const _pluginPath =
    'android/app/src/main/kotlin/io/getflash/app/GeminiNanoPlugin.kt';

late String _source;

/// Source with comments removed, so an assertion can't be satisfied — or
/// broken — by commented-out code.
late String _code;

String _stripComments(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i == -1 ? l : l.substring(0, i);
    })
    .join('\n');

void main() {
  setUpAll(() {
    final file = File(_pluginPath);
    expect(file.existsSync(), isTrue,
        reason: 'Expected the native plugin at $_pluginPath. If it moved, '
            'update this test rather than deleting it.');
    _source = file.readAsStringSync();
    _code = _stripComments(_source);
  });

  group('single model pass', () {
    test('streams exactly once per summary', () {
      final streamCalls =
          RegExp(r'generateContentStream\s*\(').allMatches(_code).length;
      expect(streamCalls, 1,
          reason: 'One streaming call per summary. Found $streamCalls.');
    });

    test('makes no blocking generateContent call', () {
      final blocking = RegExp(r'generateContent\s*\(').allMatches(_code).length;
      expect(blocking, 0,
          reason: 'The read-then-write second pass was the main source of '
              'latency and must not return. Found $blocking.');
    });

    test('no key-points intermediate step remains', () {
      expect(_code.toLowerCase(), isNot(contains('keypoints')),
          reason: 'Pass one was deleted, not merely bypassed.');
    });
  });

  group('latency budget', () {
    test('there is exactly one generation timeout', () {
      final timeouts = RegExp(r'withTimeout\s*\(').allMatches(_code).length;
      expect(timeouts, 1, reason: 'One pass, one timeout. Found $timeouts.');
    });

    test('the timeout is 20 seconds', () {
      expect(_code, contains(RegExp(r'withTimeout\s*\(\s*20_?000')));
    });

    test('no 45-second timeout survives anywhere', () {
      expect(_code, isNot(contains(RegExp(r'45_?000'))));
    });

    test('the old 6000-character trim is gone', () {
      expect(_code, isNot(contains('6000')));
    });
  });

  // ── What used to live here ───────────────────────────────────────────────
  //
  // The prompt, the tier table, the language map and the 2500-character trim
  // were all assembled in this file's subject until the cloud fallback
  // existed. Two backends cannot each own a copy of those rules and stay in
  // step, so they moved to `summary_prompt_builder.dart` and are asserted in
  // `summary_prompt_builder_test.dart` — against the string the model
  // actually receives, which is a stronger check than the source text that
  // produces it.
  //
  // What is left here is the half that is genuinely native: how the model is
  // driven, and the fact that it no longer shapes what it is asked.

  group('the native side no longer builds prompts', () {
    test('it takes a finished prompt off the channel', () {
      expect(_code, contains('call.argument<String>("prompt")'),
          reason: 'Dart assembles the prompt; this side receives it whole');
    });

    test('the arguments it used to assemble a prompt from are gone', () {
      for (final arg in const ['"title"', '"content"', '"lengthTier"', '"locale"']) {
        expect(_code, isNot(contains('call.argument<String>($arg)')),
            reason: 'reading $arg here means this side is shaping the prompt '
                'again, which is the drift the move was meant to prevent');
      }
    });

    test('no prompt text survives, commented out or otherwise', () {
      final lower = _source.toLowerCase();
      for (final fragment in const [
        'ruthless news summariser',
        'writeprompt',
        'lengthtier(',
        'langinstructionfor',
      ]) {
        expect(lower, isNot(contains(fragment)),
            reason: 'a second copy of the prompt rules left behind here — '
                'even dead or commented — is how the two backends drift');
      }
    });

    test('it does not trim the article either', () {
      expect(_code, isNot(contains('2500')),
          reason: 'the trim is part of building the prompt, so it moved with '
              'it — both backends must send the same article');
    });
  });

  group('no new dependencies', () {
    test('still uses the ML Kit GenAI client', () {
      expect(_code, contains('com.google.mlkit.genai'));
    });
  });
}
