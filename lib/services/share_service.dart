import 'package:share_plus/share_plus.dart';
import '../models/article.dart';

class ShareService {
  Future<void> shareArticle(Article article) async {
    final text = '${article.title}\n${article.url}';
    await Share.share(text, subject: article.title);
  }
}
