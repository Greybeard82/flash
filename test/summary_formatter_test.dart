import 'package:flutter_test/flutter_test.dart';
import 'package:flash/services/summary_formatter.dart';

int _wordCount(String s) =>
    s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

List<String> _bullets(String s) => s
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.startsWith('- '))
    .toList();

void main() {
  group('backstop ceilings', () {
    // The reader picks a tier, the prompt is told that tier's numbers, and
    // this is the backstop for the same tier. The two have to agree rather
    // than compete, so each backstop sits one step above what the prompt
    // asked for — see the note on kSummaryTierLimits.
    test('standard is unchanged, for anyone who never touches the setting',
        () {
      final s = SummaryFormatter.limitsFor(kSummaryLengthStandard);
      expect(s.maxWords, 320);
      expect(s.maxBullets, 6);
    });

    test('every tier backstops above the prompt ceiling it shadows', () {
      // Prompt-side figures, from GeminiNanoPlugin's writePrompt.
      const promptWords = {
        kSummaryLengthShort: 100,
        kSummaryLengthStandard: 250,
        kSummaryLengthDetailed: 350,
      };
      const promptBullets = {
        kSummaryLengthShort: 3,
        kSummaryLengthStandard: 5,
        kSummaryLengthDetailed: 8,
      };
      for (final tier in kSummaryTierLimits.keys) {
        final l = SummaryFormatter.limitsFor(tier);
        expect(l.maxWords, greaterThan(promptWords[tier]!),
            reason: '$tier: a backstop at or under the prompt ceiling would '
                'truncate output that obeyed the instruction');
        expect(l.maxBullets, promptBullets[tier]! + 1,
            reason: '$tier: one bullet of slack — equal punishes every small '
                'overshoot, far looser catches nothing');
      }
    });

    test('tiers get progressively roomier', () {
      final short = SummaryFormatter.limitsFor(kSummaryLengthShort);
      final standard = SummaryFormatter.limitsFor(kSummaryLengthStandard);
      final detailed = SummaryFormatter.limitsFor(kSummaryLengthDetailed);
      expect(short.maxWords, lessThan(standard.maxWords));
      expect(standard.maxWords, lessThan(detailed.maxWords));
      expect(short.maxBullets, lessThan(standard.maxBullets));
      expect(standard.maxBullets, lessThan(detailed.maxBullets));
    });

    test('an unknown tier falls back to standard rather than throwing', () {
      final s = SummaryFormatter.limitsFor(kSummaryLengthStandard);
      final unknown = SummaryFormatter.limitsFor('nonsense');
      expect(unknown.maxWords, s.maxWords);
      expect(unknown.maxBullets, s.maxBullets);
    });
  });

  group('the tier actually changes what clamp does', () {
    String clampTwelveBullets(String tier) {
      final input = [
        'Twelve items were announced.',
        for (var i = 1; i <= 12; i++) '- Item $i',
      ].join('\n');
      return SummaryFormatter.clamp(input, tier: tier);
    }

    test('each tier keeps its own number of bullets', () {
      expect(_bullets(clampTwelveBullets(kSummaryLengthShort)), hasLength(4));
      expect(_bullets(clampTwelveBullets(kSummaryLengthStandard)), hasLength(6));
      expect(_bullets(clampTwelveBullets(kSummaryLengthDetailed)), hasLength(9));
    });

    test('short clamps words harder than detailed', () {
      final long = List.generate(400, (i) => 'word$i').join(' ');
      final short = SummaryFormatter.clamp(long, tier: kSummaryLengthShort);
      final detailed =
          SummaryFormatter.clamp(long, tier: kSummaryLengthDetailed);
      expect(_wordCount(short), lessThan(_wordCount(detailed)));
      expect(_wordCount(short), lessThanOrEqualTo(130));
      expect(_wordCount(detailed), lessThanOrEqualTo(450));
    });

    test('omitting the tier behaves as standard', () {
      final input = [
        'Twelve items were announced.',
        for (var i = 1; i <= 12; i++) '- Item $i',
      ].join('\n');
      expect(SummaryFormatter.clamp(input),
          SummaryFormatter.clamp(input, tier: kSummaryLengthStandard));
    });
  });

  group('empty and degenerate input', () {
    test('empty string returns empty', () {
      expect(SummaryFormatter.clamp(''), isEmpty);
    });

    test('whitespace-only returns empty', () {
      expect(SummaryFormatter.clamp('   \n\n  \t '), isEmpty);
    });

    test('a single short sentence passes through unchanged', () {
      const input = 'Sony confirmed the PS5 Pro ships on 7 November for 799 euro.';
      expect(SummaryFormatter.clamp(input), input);
    });
  });

  group('preamble and markdown stripping', () {
    test('strips a leading "Summary:" line', () {
      const input = 'Summary:\nThe deal closed at 4.2 billion euro.';
      expect(SummaryFormatter.clamp(input), 'The deal closed at 4.2 billion euro.');
    });

    test('strips a bare leading "Summary" line', () {
      const input = 'Summary\nThe deal closed at 4.2 billion euro.';
      expect(SummaryFormatter.clamp(input), 'The deal closed at 4.2 billion euro.');
    });

    test('strips "Summary:" used as an inline prefix', () {
      const input = 'Summary: The deal closed at 4.2 billion euro.';
      expect(SummaryFormatter.clamp(input), 'The deal closed at 4.2 billion euro.');
    });

    test('strips markdown bold anywhere', () {
      const input = 'The **PS5 Pro** ships in **November**.';
      expect(SummaryFormatter.clamp(input), 'The PS5 Pro ships in November.');
    });

    test('leaves ordinary hyphenation alone', () {
      const input = 'The state-of-the-art chip runs at 2.5 GHz.';
      expect(SummaryFormatter.clamp(input), input);
    });
  });

  group('bullet normalisation', () {
    test('normalises "*" markers', () {
      const input = 'Four games are free.\n* Hogwarts Legacy\n* Sifu';
      expect(_bullets(SummaryFormatter.clamp(input)),
          ['- Hogwarts Legacy', '- Sifu']);
    });

    test('normalises bullet-glyph markers', () {
      const input = 'Four games are free.\n• Hogwarts Legacy\n• Sifu';
      expect(_bullets(SummaryFormatter.clamp(input)),
          ['- Hogwarts Legacy', '- Sifu']);
    });

    test('normalises en-dash markers', () {
      const input = 'Four games are free.\n– Hogwarts Legacy\n– Sifu';
      expect(_bullets(SummaryFormatter.clamp(input)),
          ['- Hogwarts Legacy', '- Sifu']);
    });

    test('leaves correct "- " markers alone', () {
      const input = 'Four games are free.\n- Hogwarts Legacy\n- Sifu';
      expect(SummaryFormatter.clamp(input), input);
    });
  });

  group('bullet ceiling', () {
    test('keeps the first six bullets in order and drops the rest', () {
      final input = [
        'Twelve items were announced.',
        for (var i = 1; i <= 12; i++) '- Item $i',
      ].join('\n');

      expect(_bullets(SummaryFormatter.clamp(input)),
          [for (var i = 1; i <= 6; i++) '- Item $i']);
    });

    test('the focal line survives bullet truncation', () {
      final input = [
        'Twelve items were announced.',
        for (var i = 1; i <= 12; i++) '- Item $i',
      ].join('\n');

      expect(SummaryFormatter.clamp(input),
          startsWith('Twelve items were announced.'));
    });

    test('a compliant five-bullet summary is untouched', () {
      final input = [
        'Five items were announced.',
        for (var i = 1; i <= 5; i++) '- Item $i',
      ].join('\n');

      expect(SummaryFormatter.clamp(input), input);
    });
  });

  group('word ceiling', () {
    test('a 250-word summary is never clamped', () {
      final input = List.generate(250, (i) => 'word$i').join(' ');
      expect(SummaryFormatter.clamp(input), input,
          reason: 'The prompt budget must sit comfortably inside the backstop.');
    });

    test('drops whole trailing lines until the ceiling is met', () {
      final long = List.generate(70, (i) => 'word$i').join(' ');
      final input = [
        'The company reported record revenue across every regional market.',
        '- $long',
        '- $long',
        '- $long',
        '- $long',
        '- $long',
      ].join('\n');

      final out = SummaryFormatter.clamp(input);
      expect(_wordCount(out), lessThanOrEqualTo(320));
      expect(out, isNot(input), reason: 'the input exceeds the ceiling, so something must be dropped');
      expect(_bullets(out), isNotEmpty);
    });

    test('never cuts a retained bullet mid-sentence', () {
      final long = List.generate(70, (i) => 'word$i').join(' ');
      final input = [
        'Focal sentence here.',
        '- $long',
        '- $long',
        '- $long',
        '- $long',
        '- $long',
      ].join('\n');

      final bullets = _bullets(SummaryFormatter.clamp(input));
      expect(bullets.length, lessThan(5),
          reason: 'the input exceeds the ceiling, so at least one whole '
              'bullet must be dropped rather than truncated');
      for (final b in bullets) {
        expect(b, '- $long',
            reason: 'Retained bullets must be whole, not truncated.');
      }
    });

    test('truncates at a word boundary when the focal line alone runs away', () {
      final runaway = List.generate(400, (i) => 'word$i').join(' ');
      final out = SummaryFormatter.clamp(runaway);

      expect(_wordCount(out), lessThanOrEqualTo(320));
      expect(out, endsWith('…'));
      expect(out, isNot(contains('word320')));
      expect(out, isNot(matches(RegExp(r'word\d*[a-z]…$'))));
    });

    test('a summary exactly at the ceiling is left intact', () {
      final exact = List.generate(320, (i) => 'word$i').join(' ');
      final out = SummaryFormatter.clamp(exact);

      expect(_wordCount(out), 320);
      expect(out, isNot(endsWith('…')));
    });
  });

  group('whitespace', () {
    test('collapses runs of blank lines', () {
      const input = 'Focal fact.\n\n\n\n- One bullet.';
      expect(SummaryFormatter.clamp(input), isNot(contains('\n\n\n')));
    });

    test('trims leading and trailing whitespace', () {
      const input = '\n\n  Focal fact.  \n\n';
      expect(SummaryFormatter.clamp(input), 'Focal fact.');
    });
  });

  group('idempotence', () {
    test('clamping an already-clamped summary changes nothing', () {
      final input = [
        'Twelve items were announced today by the manufacturer.',
        for (var i = 1; i <= 12; i++) '- Item $i with some descriptive text',
      ].join('\n');

      final once = SummaryFormatter.clamp(input);
      expect(SummaryFormatter.clamp(once), once);
    });
  });
}
