import 'package:share_plus/share_plus.dart';
import '../models/article.dart';

class ShareService {
  Future<void> shareArticle(Article article) async {
    final text = '${article.title}\n${article.url}';
    // share_plus 10 deprecated the static Share.share and 11 removed it;
    // SharePlus.instance.share(ShareParams(...)) is the current form. Same
    // behaviour, same share sheet — see the pubspec note for why the bump was
    // forced rather than chosen.
    await SharePlus.instance
        .share(ShareParams(text: text, subject: article.title));
  }
}
