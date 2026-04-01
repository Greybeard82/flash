import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class FaviconService {
  static const String _googleFaviconBase =
      'https://www.google.com/s2/favicons?sz=64&domain=';

  Future<String?> fetchAndCache(String domain, int feedId) async {
    try {
      final url = '$_googleFaviconBase$domain';
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) return null;

      final bytes = response.bodyBytes;
      if (bytes.isEmpty) return null;

      final path = await _saveFavicon(bytes, feedId);
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<String> _saveFavicon(Uint8List bytes, int feedId) async {
    final dir = await getApplicationCacheDirectory();
    final faviconDir = Directory(p.join(dir.path, 'favicons'));
    if (!faviconDir.existsSync()) {
      faviconDir.createSync(recursive: true);
    }
    final file = File(p.join(faviconDir.path, 'feed_$feedId.png'));
    await file.writeAsBytes(bytes);
    return file.path;
  }
}
