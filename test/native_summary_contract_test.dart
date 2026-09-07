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
    // This has been through three corrections. All-brevity produced a
    // restated headline and clipped fragments. An unconditional ~100 words
    // fixed that but padded short factual items. Then the model was asked to
    // judge which of two cases an article was — and that judgement was the
    // least predictable part of the whole feature.
    //
    // So the length is the reader's choice now, and the prompt is built from
    // the tier they picked. What needs pinning is that the numbers are
    // parameterised at all, and that no trace of the old self-judgement
    // survives to compete with them.
    test('is parameterised by tier rather than judging the article itself',
        () {
      expect(_code, contains('lengthTier'),
          reason: 'the tier has to reach writePrompt to be used');
      expect(_code, contains(RegExp(r'fun\s+writePrompt\([^)]*lengthTier',
          dotAll: true)),
          reason: 'writePrompt must take the tier, not infer a length');
    });

    test('no trace of the old case-judgement survives', () {
      final lower = _source.toLowerCase();
      expect(lower, isNot(contains('case a')));
      expect(lower, isNot(contains('case b')));
      expect(lower, isNot(contains('first, judge what kind of article')),
          reason: 'this pass replaced that judgement rather than layering '
              'the tiers on top of it');
    });

    test('defines all three tiers, each roomier than the last', () {
      // Targets, ceilings and bullet caps live in tierFor(). Their Dart-side
      // backstops are asserted in summary_formatter_test.
      for (final tier in ['short', 'detailed']) {
        expect(_code, contains('"$tier"'),
            reason: 'tierFor must recognise "$tier" by name');
      }
      for (final target in ['40-50', '75-100', '150-200']) {
        expect(_code, contains(target),
            reason: 'each tier needs its own word target');
      }
      for (final ceiling in ['100', '250', '350']) {
        expect(_code, contains(ceiling),
            reason: 'each tier needs its own hard ceiling');
      }
    });

    test('an unrecognised tier falls back rather than failing', () {
      expect(_code, contains(RegExp(r'else\s*->\s*LengthTier')),
          reason: 'a missing or unknown tier must still produce a prompt');
    });

    test('forbids padding, whichever tier is selected', () {
      final lower = _source.toLowerCase();
      expect(lower, contains('never pad'));
      expect(lower, anyOf(contains('not a floor'), contains('write less')),
          reason: 'the target is something to come in under, not to reach');
    });

    // A headline that withholds something — a count, a name, an answer — is
    // what a summary most has to earn its place on. Gesturing at the tease
    // without resolving it is worse than useless, and that holds at the
    // shortest tier too: tersely resolved is still resolved.
    test('requires the headline\'s tease to be resolved at every tier', () {
      final lower = _source.toLowerCase();
      expect(lower, contains('resolve it explicitly'));
      expect(lower, contains('at every length'),
          reason: 'the short tier must not be treated as an excuse to skip '
              'the one thing the summary is for');
      expect(lower, contains('never leave the tease unresolved'));
    });

    test('makes bullets conditional, and capped by the tier', () {
      final lower = _source.toLowerCase();
      expect(_code, contains(r'${tier.bulletCap}'),
          reason: 'the bullet cap has to come from the tier, not be fixed');
      expect(lower, contains('only if'),
          reason: 'bullets must be earned by the article having distinct '
              'listable points');
      expect(lower, contains('the paragraph alone is complete'),
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
