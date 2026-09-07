// The prompt, now that two backends send it.
//
// It used to be assembled in `GeminiNanoPlugin.kt`, where it was untestable
// from Dart and, once a cloud fallback existed, would have been one of two
// copies. Both paths now call `buildSummaryPrompt`, so what is pinned here is
// pinned for Nano and the cloud at once.
//
// The tier numbers are the load-bearing part. They shadow `kSummaryTierLimits`
// deliberately — the prompt asks for less than the formatter will allow, so
// the instruction and the backstop cannot compete — and that relationship is
// asserted here rather than left to a comment in two files.

import 'package:flutter_test/flutter_test.dart';

import 'package:flash/services/summary_formatter.dart';
import 'package:flash/services/summary_prompt_builder.dart';

String _prompt({
  String title = 'A headline',
  String content = 'Some article body.',
  String locale = 'en',
  String tier = kSummaryLengthStandard,
}) =>
    buildSummaryPrompt(
      title: title,
      content: content,
      langInstruction: summaryLangInstructionFor(locale),
      lengthTier: tier,
    );

void main() {
  group('tier substitution', () {
    test('each tier asks for its own numbers', () {
      expect(_prompt(tier: kSummaryLengthShort), contains('40-50 words'));
      expect(_prompt(tier: kSummaryLengthStandard), contains('75-100 words'));
      expect(_prompt(tier: kSummaryLengthDetailed), contains('150-200 words'));
    });

    test('each tier states its own hard ceiling', () {
      expect(_prompt(tier: kSummaryLengthShort), contains('100 words is the'));
      expect(
          _prompt(tier: kSummaryLengthStandard), contains('250 words is the'));
      expect(
          _prompt(tier: kSummaryLengthDetailed), contains('350 words is the'));
    });

    test('each tier caps its own bullets', () {
      expect(_prompt(tier: kSummaryLengthShort), contains('up to 3\nbullets'));
      expect(
          _prompt(tier: kSummaryLengthStandard), contains('up to 5\nbullets'));
      expect(
          _prompt(tier: kSummaryLengthDetailed), contains('up to 8\nbullets'));
    });

    test('an unknown tier falls back to standard, not to nothing', () {
      expect(_prompt(tier: 'medium-rare'), _prompt(tier: kSummaryLengthStandard),
          reason: 'a bad setting must degrade to the default tier rather than '
              'producing a prompt with no length instruction at all');
    });
  });

  group('the prompt asks for less than the formatter allows', () {
    // These two limits have to agree rather than compete: a backstop set
    // equal to the instruction turns every one-bullet overshoot into a
    // visible mid-summary truncation. One tier of slack, in both directions.
    for (final tier in const [
      kSummaryLengthShort,
      kSummaryLengthStandard,
      kSummaryLengthDetailed,
    ]) {
      test('$tier: bullet cap sits below the formatter backstop', () {
        final asked = summaryTierPromptFor(tier).bulletCap;
        final allowed = SummaryFormatter.limitsFor(tier).maxBullets;
        expect(asked, lessThan(allowed),
            reason: 'the prompt must ask for fewer bullets than the clamp '
                'permits, or every overshoot is a visible truncation');
      });

      test('$tier: word ceiling sits below the formatter backstop', () {
        final asked = summaryTierPromptFor(tier).ceiling;
        final allowed = SummaryFormatter.limitsFor(tier).maxWords;
        expect(asked, lessThan(allowed),
            reason: 'same reasoning as the bullet cap');
      });
    }
  });

  group('the article reaches the model', () {
    test('title and content are both present', () {
      final p = _prompt(title: 'Valve ships a thing', content: 'Body text.');
      expect(p, contains('Title: Valve ships a thing'));
      expect(p, contains('Content: Body text.'));
    });

    test('content is trimmed to the source limit', () {
      final long = 'x' * (kSummarySourceCharLimit + 500);
      final p = _prompt(content: long);
      expect(p, contains('x' * kSummarySourceCharLimit));
      expect(p, isNot(contains('x' * (kSummarySourceCharLimit + 1))),
          reason: 'sending the whole body costs time-to-first-token for text '
              'past where the substance lives');
    });

    test('content shorter than the limit is not padded or cut', () {
      final p = _prompt(content: 'Short body.');
      expect(p, contains('Content: Short body.\n'));
    });

    test('the trim is the same for both backends', () {
      // Applied inside the builder rather than by each caller, so a
      // difference in output is never quietly a difference in input.
      expect(kSummarySourceCharLimit, 2500);
    });
  });

  group('language', () {
    test('each supported locale names its own language', () {
      expect(summaryLangInstructionFor('es'), contains('Spanish'));
      expect(summaryLangInstructionFor('fr'), contains('French'));
      expect(summaryLangInstructionFor('de'), contains('German'));
      expect(summaryLangInstructionFor('it'), contains('Italian'));
      expect(summaryLangInstructionFor('en'), contains('English'));
    });

    test('an unknown locale falls back to English', () {
      expect(summaryLangInstructionFor('sv'), contains('English'));
    });

    test('the instruction lands in the prompt', () {
      expect(_prompt(locale: 'fr'), contains('Write the summary in French.'));
    });
  });

  group('the rules that make summaries usable are all still there', () {
    // Each of these earned its place in a previous pass; a reworded prompt
    // that quietly drops one would be very hard to notice from output alone.
    final p = _prompt();

    test('resolves the headline tease', () {
      expect(p, contains('the summary must resolve it explicitly'));
    });

    test('bans the filler phrases', () {
      expect(p, contains('"aims to"'));
      expect(p, contains('"remains to be\n   seen"'));
    });

    test('asks for a paragraph first, bullets only when earned', () {
      expect(p, contains('A paragraph in plain readable prose'));
      expect(p, contains('If\nnothing earns a bullet, the paragraph alone is '
          'complete.'));
    });

    test('handles thin source text without inventing detail', () {
      expect(p, contains('IF THE TEXT IS THIN'));
      expect(p, contains('rather than padding with filler'));
    });

    test('ends where the model should start writing', () {
      expect(p.trimRight(), endsWith('Summary:'));
    });

    // Ported from native_summary_contract_test.dart when the prompt moved
    // out of Kotlin. Each of these pinned a real regression there, and they
    // are stronger here: they read the string the model actually receives
    // rather than the source text that produces it.

    test('forbids padding, whichever tier is selected', () {
      for (final tier in const [
        kSummaryLengthShort,
        kSummaryLengthStandard,
        kSummaryLengthDetailed,
      ]) {
        final lower = _prompt(tier: tier).toLowerCase();
        expect(lower, contains('never pad'));
        expect(lower, anyOf(contains('not a floor'), contains('write less')),
            reason: 'the target is something to come in under, not to reach');
      }
    });

    test('the tease must be resolved at every tier, short included', () {
      final lower = p.toLowerCase();
      expect(lower, contains('resolve it explicitly'));
      expect(lower, contains('at every length'),
          reason: 'the short tier must not be treated as an excuse to skip '
              'the one thing the summary is for');
      expect(lower, contains('never leave the tease unresolved'));
    });

    test('bullets are conditional, not assumed', () {
      final lower = p.toLowerCase();
      expect(lower, contains('only if'),
          reason: 'bullets must be earned by the article having distinct '
              'listable points');
      expect(lower, contains('the paragraph alone is complete'),
          reason: 'the model needs telling that no bullets is a correct '
              'outcome, not an incomplete one — otherwise it invents some');
    });

    test('forbids restating the headline', () {
      expect(p.toLowerCase(), contains('do not restate the headline'));
    });

    test('forbids inference and gap-filling', () {
      expect(p.toLowerCase(),
          anyOf(contains('never infer'), contains('do not infer')));
    });

    test('uses the "- " bullet marker the Dart widget renders', () {
      expect(p, contains('"- "'),
          reason: '_SummaryText converts a leading "- " into a bullet glyph. '
              'Any other marker renders as literal text.');
    });
  });
}
