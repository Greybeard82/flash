import 'package:html/parser.dart' as html_parser;

String stripHtml(String? input) {
  if (input == null || input.isEmpty) return '';
  final doc = html_parser.parse(input);
  return doc.body?.text ?? '';
}
