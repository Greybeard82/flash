import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../utils/html_utils.dart';

class ThumbnailService {
  Future<String?> fetchOgImage(String articleUrl) async {
    try {
      final response = await http.get(Uri.parse(articleUrl)).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;
      return extractOgImage(response.body);
    } catch (_) {
      return null;
    }
  }

  Future<String?> downloadAndCache(String imageUrl, int articleId) async {
    try {
      final response = await http.get(Uri.parse(imageUrl)).timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) return null;

      final bytes = response.bodyBytes;
      if (bytes.isEmpty) return null;

      final path = await _saveThumbnail(bytes, articleId);
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _saveThumbnail(Uint8List bytes, int articleId) async {
    final dir = await getApplicationCacheDirectory();
    final thumbDir = Directory(p.join(dir.path, 'thumbnails'));
    if (!thumbDir.existsSync()) {
      thumbDir.createSync(recursive: true);
    }
    final file = File(p.join(thumbDir.path, 'article_$articleId.jpg'));
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
