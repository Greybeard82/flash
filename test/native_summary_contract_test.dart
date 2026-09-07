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
    // This has been through two corrections. First the prompt was all
    // brevity, which produced a restated headline and clipped fragments.
    // Then it asked for ~100 words of prose unconditionally, which fixed
    // that but padded short factual items — a release date does not have
    // 100 words in it — into sounding longer than the article was.
    //
    // So length is now a judgement the model makes per article, between two
    // named cases, and that branch is what needs pinning: a single stated
    // target would collapse it straight back to one tier.
    test('asks the model to pick a length case, not one fixed length', () {
      final lower = _source.toLowerCase();
      expect(lower, contains('case a'),
          reason: 'the short-factual case has to be named to be chosen');
      expect(lower, contains('case b'),
          reason: 'the substantive case has to be named to be chosen');
      expect(lower, contains('75–100 words'),
          reason: 'only the substantive case carries a length target');
      expect(lower, anyOf(contains('match the length'), contains('far less')),
          reason: 'the model must be told to fit length to the article, or '
              'it defaults to one size for everything');
    });

    test('forbids padding a short article out to look substantial', () {
      final lower = _source.toLowerCase();
      expect(lower, contains('never pad'),
          reason: 'padding a spec sheet into a paragraph is the regression '
              'this case split exists to prevent');
      expect(lower, contains("don't stretch to fill it"),
          reason: 'the ceiling is a limit, not a target');
    });

    // A headline that withholds something — a count, a name, an answer — is
    // the case a summary most has to earn its place on. Gesturing at the
    // tease without resolving it is worse than useless.
    test('requires the headline\'s tease to be resolved explicitly', () {
      final lower = _source.toLowerCase();
      expect(lower, contains('resolve it explicitly'));
      expect(lower, contains('name the actual'),
          reason: 'the instruction has to be to name the thing, not to '
              'mention that a thing exists');
    });

    test('makes bullets conditional rather than mandatory', () {
      final lower = _source.toLowerCase();
      expect(lower, contains('up to 5 bullets'),
          reason: 'bullets stay capped');
      expect(lower, anyOf(contains("don't force one"),
          contains('do not add bullets')),
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
