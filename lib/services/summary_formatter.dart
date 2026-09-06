/// Pure-function backstop for the AI summary text. Nano's instruction-following
/// is not reliable enough to trust the prompt's own budget and format rules
/// alone, so this clamps length, strips preambles/markdown the model
/// sometimes echoes, and normalises bullet markers to what the UI renders.
class SummaryFormatter {
  static const int maxWords = 320;
  static const int maxBullets = 8;

  static final RegExp _summaryPrefixLine =
      RegExp(r'^summary:?\s*$', caseSensitive: false);
  static final RegExp _summaryInlinePrefix =
      RegExp(r'^summary:\s*', caseSensitive: false);
  static final RegExp _bulletMarker = RegExp(r'^[*•–]\s+');
  static final RegExp _blankRuns = RegExp(r'\n{3,}');

  static String clamp(String input) {
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

    text = _capBullets(text);
    text = _capWords(text);
    text = text.trim();
    return text;
  }

  static String _capBullets(String text) {
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

  static String _capWords(String text) {
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
