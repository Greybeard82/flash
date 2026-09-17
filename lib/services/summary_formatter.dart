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

/// The text a summary produces when it leaves the app, for **both** copy and
/// share.
///
/// **One function because the two payloads must be byte-identical**, and that
/// is the invariant rather than a tidiness preference. Copy used to put the
/// bare summary on the clipboard: no title, no link, no sign a machine wrote
/// it. Pasted into a chat it read as the publisher's own words. If share
/// carried attribution and copy did not, copy would become the button people
/// use to strip it, and the inconsistency would be the bug rather than the
/// feature. `summary_share_payload_test.dart` pins the equality.
///
/// The shape:
///
/// ```
/// <article title>
///
/// <summary>
///
/// <AI disclaimer>
/// <url>
/// ```
///
/// Neither the link nor the disclaimer is decoration. Flash's entire supply
/// depends on publishers continuing to offer feeds, and an app that circulates
/// their content with no traffic back is the thing publishers close feeds
/// over. And these summaries are sometimes wrong — without the label the
/// mistake is attributed to the publisher rather than to the app that
/// generated it.
///
/// The disclaimer arrives already resolved because only the sheet knows
/// whether the summary came from the cloud or from the device. It is
/// `aiSummaryDisclaimer` or `aiSummaryDisclaimerCloud` verbatim: both were
/// written to sit under a summary on screen and both survive the move into a
/// message unchanged, because neither uses deixis — no "this", no "above", no
/// "the summary below" — so neither needs the UI around it to make sense.
///
/// Pure, and deliberately takes strings rather than an `Article` and an
/// `AppLocalizations`: it is the one piece of this feature worth testing
/// exhaustively, and it should not need a widget tree or a database to do it.
String buildSummaryShareText({
  required String title,
  required String summary,
  required String disclaimer,
  required String url,
}) {
  // Trimmed because the model's own output routinely carries a trailing
  // newline, and an extra blank line before the disclaimer reads as a mistake
  // in a chat message where it did not on screen.
  return '${title.trim()}\n\n${summary.trim()}\n\n${disclaimer.trim()}\n$url';
}
