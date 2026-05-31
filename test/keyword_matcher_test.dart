import 'package:flutter_test/flutter_test.dart';
import 'package:flash/utils/keyword_matcher.dart';

void main() {
  // ── buildHaystack ────────────────────────────────────────────────────────────

  group('buildHaystack', () {
    test('combines title and description', () {
      expect(KeywordMatcher.buildHaystack('Hello', 'world'), 'Hello world');
    });

    test('handles null description', () {
      expect(KeywordMatcher.buildHaystack('Only title', null), 'Only title ');
    });
  });

  // ── matches — default (partial, case-insensitive) ─────────────────────────

  group('matches default (partial, case-insensitive)', () {
    test('matches exact case', () {
      expect(KeywordMatcher.matches('crypto', 'crypto prices surge'), isTrue);
    });

    test('matches uppercase keyword against lowercase haystack', () {
      expect(KeywordMatcher.matches('CRYPTO', 'crypto prices surge'), isTrue);
    });

    test('matches lowercase keyword against uppercase haystack', () {
      expect(KeywordMatcher.matches('crypto', 'CRYPTO PRICES SURGE'), isTrue);
    });

    test('matches mixed case', () {
      expect(KeywordMatcher.matches('Elon Musk', 'elon musk buys company'), isTrue);
    });

    test('partial match within word', () {
      expect(KeywordMatcher.matches('crypto', 'cryptocurrency rises'), isTrue);
    });

    test('returns false when not present', () {
      expect(KeywordMatcher.matches('crypto', 'stock market news'), isFalse);
    });

    test('matches in description part of haystack', () {
      final haystack = KeywordMatcher.buildHaystack('Stock News', 'crypto gains 10%');
      expect(KeywordMatcher.matches('crypto', haystack), isTrue);
    });

    test('matches in title part of haystack', () {
      final haystack = KeywordMatcher.buildHaystack('Crypto crashes', 'market update');
      expect(KeywordMatcher.matches('crypto', haystack), isTrue);
    });
  });

  // ── matches — whole-word mode ─────────────────────────────────────────────

  group('matches whole-word mode', () {
    test('does not match partial word', () {
      expect(
        KeywordMatcher.matches('crypto', 'cryptocurrency rises', wholeWord: true),
        isFalse,
      );
    });

    test('matches standalone word', () {
      expect(
        KeywordMatcher.matches('crypto', 'crypto prices surge', wholeWord: true),
        isTrue,
      );
    });

    test('whole-word match is case-insensitive', () {
      expect(
        KeywordMatcher.matches('CRYPTO', 'crypto prices surge', wholeWord: true),
        isTrue,
      );
    });

    test('whole-word does not match substring of compound word', () {
      expect(
        KeywordMatcher.matches('sport', 'sports news today', wholeWord: true),
        isFalse,
      );
    });

    test('whole-word matches at start of string', () {
      expect(
        KeywordMatcher.matches('breaking', 'breaking news today', wholeWord: true),
        isTrue,
      );
    });

    test('whole-word matches at end of string', () {
      expect(
        KeywordMatcher.matches('today', 'breaking news today', wholeWord: true),
        isTrue,
      );
    });
  });
}
