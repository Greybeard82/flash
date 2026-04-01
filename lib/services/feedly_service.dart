import 'dart:convert';
import 'package:http/http.dart' as http;

class FeedlyResult {
  final String feedUrl;
  final String title;
  final String? website;
  final int? subscribers;
  final String? description;
  final String? faviconUrl;

  const FeedlyResult({
    required this.feedUrl,
    required this.title,
    this.website,
    this.subscribers,
    this.description,
    this.faviconUrl,
  });
}

class FeedlyService {
  static const String _searchBase =
      'https://cloud.feedly.com/v3/search/feeds?query=';

  Future<List<FeedlyResult>> search(String query) async {
    try {
      final url = Uri.parse('$_searchBase${Uri.encodeComponent(query)}&count=10');
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];

      return results.map((r) {
        final map = r as Map<String, dynamic>;
        // feedId is like "feed/https://example.com/rss"
        final feedId = map['feedId'] as String? ?? '';
        final feedUrl = feedId.startsWith('feed/')
            ? feedId.substring(5)
            : feedId;

        return FeedlyResult(
          feedUrl: feedUrl,
          title: map['title'] as String? ?? feedUrl,
          website: map['website'] as String?,
          subscribers: map['subscribers'] as int?,
          description: map['description'] as String?,
          faviconUrl: map['iconUrl'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  bool looksLikeUrl(String query) {
    return query.startsWith('http://') ||
        query.startsWith('https://') ||
        query.contains('.') && !query.contains(' ');
  }
}
