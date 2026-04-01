import 'package:html/parser.dart' as html_parser;

String stripHtml(String? input) {
  if (input == null || input.isEmpty) return '';
  final doc = html_parser.parse(input);
  return doc.body?.text ?? '';
}

String truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}…';
}

String? extractOgImage(String htmlContent) {
  try {
    final doc = html_parser.parse(htmlContent);
    final metas = doc.querySelectorAll('meta');
    for (final meta in metas) {
      final property = meta.attributes['property'] ?? '';
      final name = meta.attributes['name'] ?? '';
      if (property == 'og:image' || name == 'og:image') {
        return meta.attributes['content'];
      }
    }
    // Fallback: first img tag
    final img = doc.querySelector('img');
    return img?.attributes['src'];
  } catch (_) {
    return null;
  }
}

String? resolveUrl(String? url, String baseUrl) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http://') || url.startsWith('https://')) return url;
  try {
    final base = Uri.parse(baseUrl);
    if (url.startsWith('//')) return '${base.scheme}:$url';
    if (url.startsWith('/')) return '${base.scheme}://${base.host}$url';
    return '${base.scheme}://${base.host}/$url';
  } catch (_) {
    return url;
  }
}
