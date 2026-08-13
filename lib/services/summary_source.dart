import '../models/content_block.dart';

/// Turns extracted [ContentBlock]s into the plain text handed to the model.
class SummarySource {
  static const int defaultMaxChars = 2500;

  static String fromBlocks(
    List<ContentBlock>? blocks, {
    String? fallback,
    int maxChars = defaultMaxChars,
  }) {
    if (blocks == null || blocks.isEmpty) return fallback ?? '';

    final parts = <String>[];
    for (final block in blocks) {
      switch (block) {
        case HeadingBlock():
          parts.add(block.text);
        case ParagraphBlock():
          parts.add(block.text);
        case QuoteBlock():
          parts.add(block.text);
        case ListBlock():
          parts.add(block.items.join('\n'));
        case ImageBlock():
          break;
      }
    }

    var text = parts.join('\n\n');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    if (text.isEmpty) return fallback ?? '';
    if (text.length > maxChars) text = _truncate(text, maxChars);
    return text;
  }

  static String _truncate(String text, int maxChars) {
    const ellipsis = '…';
    final limit = maxChars - ellipsis.length;
    if (limit <= 0) return ellipsis.substring(0, maxChars);

    var cut = text.substring(0, limit);
    final lastSpace = cut.lastIndexOf(RegExp(r'\s'));
    if (lastSpace > 0) cut = cut.substring(0, lastSpace);
    return cut.trimRight() + ellipsis;
  }

  /// Roughly: is there enough text here to be worth summarising?
  static bool isSubstantial(String text) => text.trim().length >= 400;
}
