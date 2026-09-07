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

    test('input is trimmed to 2500 characters', () {
      expect(_code, contains(RegExp(r'\.take\s*\(\s*2500\s*\)')),
          reason: 'Nano time-to-first-token scales with prompt length.');
    });

    test('the old 6000-character trim is gone', () {
      expect(_code, isNot(contains(RegExp(r'\.take\s*\(\s*6000\s*\)'))));
    });
  });

  group('prompt content', () {
    // The prompt used to open with "deliver the headline's promise in the
    // first line", and everything after it was terse fact-fragments. That
    // produced summaries that restated the headline and stopped. The shape
    // asked for now is a readable prose paragraph carrying the article's
    // substance, with bullets as an optional extra — so what needs pinning
    // is the paragraph instruction and the conditionality of the bullets.
    test('asks for a prose paragraph, not a lead fact-fragment', () {
      final lower = _source.toLowerCase();
      expect(lower, contains('paragraph'),
          reason: 'the primary output shape is a paragraph now');
      expect(lower, contains('100 words'),
          reason: 'the paragraph needs a stated target length, or the model '
              'reverts to one terse sentence');
      expect(lower, anyOf(contains('complete, natural sentences'),
          contains('natural sentences')),
          reason: 'prose, explicitly — not a list of fragments');
    });

    test('makes bullets conditional rather than mandatory', () {
      final lower = _source.toLowerCase();
      expect(lower, contains('only if'),
          reason: 'bullets must be earned by the article actually having '
              'distinct listable points');
      expect(lower, contains('do not add bullets'),
          reason: 'the model needs telling that no bullets is a correct '
              'outcome, not an incomplete one — otherwise it invents some');
    });

    test('still forbids restating the headline', () {
      expect(_source.toLowerCase(), contains('do not restate the headline'));
    });

    test('bans the filler register seen in the reported bad output', () {
      for (final phrase in ['aims to', 'is expected to', 'will likely']) {
        expect(_source.toLowerCase(), contains(phrase),
            reason: 'The prompt must name "$phrase" as banned. A generic '
                '"be concise" instruction is what failed before.');
      }
    });

    test('forbids inference and gap-filling', () {
      expect(_source.toLowerCase(),
          anyOf(contains('never infer'), contains('do not infer')));
    });

    test('states the 250-word budget', () {
      expect(_source, contains('250'));
    });

    test('uses the "- " bullet marker the Dart widget renders', () {
      expect(_source, contains('"- "'),
          reason: '_SummaryText converts a leading "- " into a bullet glyph. '
              'Any other marker renders as literal text.');
    });
  });

  group('localisation is preserved', () {
    test('all five supported languages still map', () {
      for (final lang in ['Spanish', 'French', 'German', 'Italian', 'English']) {
        expect(_code, contains(lang));
      }
    });

    test('the language instruction is still injected into the prompt', () {
      expect(_code, contains(r'$langInstruction'),
          reason: 'Rewriting the prompt must not silently drop localisation.');
    });
  });

  group('no new dependencies', () {
    test('still uses the ML Kit GenAI client', () {
      expect(_code, contains('com.google.mlkit.genai'));
    });
  });
}
