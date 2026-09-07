/// The three summary lengths the reader can pick between, stored under
/// `summary_length`.
const String kSummaryLengthShort = 'short';
const String kSummaryLengthStandard = 'standard';
const String kSummaryLengthDetailed = 'detailed';

/// What [SummaryFormatter] will let through for a given tier.
///
/// Each figure sits deliberately *above* what the prompt asks for at the
/// same tier, because these two limits have to agree rather than compete.
/// A backstop set equal to the instruction turns every one-bullet overshoot
/// into a visible mid-summary truncation; one set far too loose catches
/// nothing at all — the old flat 8 against an instruction of 5 let a real
/// 8-bullet response through untouched. One tier of slack is the middle
/// ground, applied here to all three tiers rather than to just one.
///
/// The prompt-side figures these shadow live in `GeminiNanoPlugin.kt`'s
/// `writePrompt`. Change one, change the other.
class SummaryTierLimits {
  /// Backstop above the tier's stated word ceiling (100 / 250 / 350).
  final int maxWords;

  /// Backstop above the tier's stated bullet cap (3 / 5 / 8).
  final int maxBullets;

  const SummaryTierLimits({required this.maxWords, required this.maxBullets});
}

const Map<String, SummaryTierLimits> kSummaryTierLimits = {
  kSummaryLengthShort: SummaryTierLimits(maxWords: 130, maxBullets: 4),
  kSummaryLengthStandard: SummaryTierLimits(maxWords: 320, maxBullets: 6),
  kSummaryLengthDetailed: SummaryTierLimits(maxWords: 450, maxBullets: 9),
};

/// Pure-function backstop for the AI summary text. Nano's instruction-following
/// is not reliable enough to trust the prompt's own budget and format rules
/// alone, so this clamps length, strips preambles/markdown the model
/// sometimes echoes, and normalises bullet markers to what the UI renders.
class SummaryFormatter {
  static SummaryTierLimits limitsFor(String tier) =>
      kSummaryTierLimits[tier] ?? kSummaryTierLimits[kSummaryLengthStandard]!;

  static final RegExp _summaryPrefixLine =
      RegExp(r'^summary:?\s*$', caseSensitive: false);
  static final RegExp _summaryInlinePrefix =
      RegExp(r'^summary:\s*', caseSensitive: false);
  static final RegExp _bulletMarker = RegExp(r'^[*•–]\s+');
  static final RegExp _blankRuns = RegExp(r'\n{3,}');

  static String clamp(String input, {String tier = kSummaryLengthStandard}) {
    final limits = limitsFor(tier);
    var text = input.trim();
    if (text.isEmpty) return '';

    text = text.replaceAll('**', '');

    final lines = text.split('\n');
    if (lines.isNotEmpty && _summaryPrefixLine.hasMatch(lines.first.trim())) {
      lines.removeAt(0);
    } else if (lines.isNotEmpty &&
        _summaryInlinePrefix.hasMatch(lines.first.trim())) {
      lines[0] = lines.first.trim().replaceFirst(_summaryInlinePrefix, '');
    }

    final normalised = lines.map((line) {
      final trimmed = line.trim();
      if (_bulletMarker.hasMatch(trimmed)) {
        return '- ${trimmed.replaceFirst(_bulletMarker, '')}';
      }
      return line;
    }).toList();

    text = normalised.join('\n');
    text = text.replaceAll(_blankRuns, '\n\n').trim();
    if (text.isEmpty) return '';

    text = _capBullets(text, limits.maxBullets);
    text = _capWords(text, limits.maxWords);
    text = text.trim();
    return text;
  }

  static String _capBullets(String text, int maxBullets) {
    final lines = text.split('\n');
    var bulletCount = 0;
    final kept = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('- ')) {
        bulletCount++;
        if (bulletCount > maxBullets) continue;
      }
      kept.add(line);
    }
    return kept.join('\n');
  }

  static String _capWords(String text, int maxWords) {
    if (_wordCount(text) <= maxWords) return text;

    final lines = text.split('\n');
    final focal = lines.isNotEmpty ? lines.first : '';

    // If the focal line alone exceeds the ceiling, truncate it at a word
    // boundary and drop everything else.
    if (_wordCount(focal) > maxWords) {
      return _truncateWords(focal, maxWords);
    }

    // Otherwise drop whole trailing lines until the total fits, never
    // cutting a retained line mid-sentence.
    final kept = <String>[];
    var total = 0;
    for (final line in lines) {
      final words = _wordCount(line);
      if (total + words > maxWords && kept.isNotEmpty) break;
      kept.add(line);
      total += words;
    }
    return kept.join('\n');
  }

  static String _truncateWords(String text, int limit) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length <= limit) return text;
    return '${words.take(limit).join(' ')}…';
  }

  static int _wordCount(String s) =>
      s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
}
