import 'package:html/parser.dart' as html_parser;

/// Returns a human-readable reading time estimate, e.g. "3 min read".
/// Strips HTML tags, counts words, assumes 230 wpm average reading speed.
String readingTime(String? htmlContent) {
  if (htmlContent == null || htmlContent.isEmpty) return '';
  final text = html_parser.parse(htmlContent).body?.text ?? '';
  final words = text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  if (words < 50) return '';
  final minutes = (words / 230).ceil();
  return '$minutes min read';
}
