import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../models/keyword_block.dart';
import '../repositories/article_repository.dart';
import '../repositories/keyword_repository.dart';
import 'keyword_group_panel.dart';

/// Keyword blocklist, rendered by the shared [KeywordGroupPanel] — one
/// collapsible group per keyword, showing the articles it hid. This file
/// only supplies the [KeywordGroupController] that talks to
/// [KeywordRepository] / [ArticleRepository.getBlocked] and the labels that
/// distinguish this from [KeywordAlertsPanel].
class KeywordBlocklistPanel extends StatelessWidget {
  const KeywordBlocklistPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return KeywordGroupPanel(
      controller: _BlocklistGroupController(),
      icon: Icons.block_rounded,
      title: l10n.keywordBlocklist,
      subtitle: l10n.keywordBlocklistSubtitle,
      matchIcon: Icons.block_rounded,
      addFieldHint: l10n.keywordHint,
      emptyIcon: Icons.block_rounded,
      emptyTitle: l10n.noBlockedKeywords,
      emptyBody: l10n.keywordBlocklistEmpty,
    );
  }
}

class _BlocklistGroupController implements KeywordGroupController {
  final _keywordRepo = KeywordRepository();
  final _articleRepo = ArticleRepository();

  @override
  Future<List<KeywordGroupEntry>> loadKeywords() async {
    final keywords = await _keywordRepo.getAll();
    return [
      for (final k in keywords)
        KeywordGroupEntry(id: k.id!, keyword: k.keyword, wholeWord: k.wholeWord),
    ];
  }

  @override
  Future<List<Article>> loadArticles() => _articleRepo.getBlocked();

  @override
  String? keywordOf(Article article) => article.blockedKeyword;

  @override
  Future<void> addKeyword(String keyword, bool wholeWord) async {
    final kw = await _keywordRepo.insert(KeywordBlock(
      keyword: keyword,
      wholeWord: wholeWord,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await _articleRepo.retroactivelyBlock(kw.keyword, kw.wholeWord);
  }

  @override
  Future<void> deleteKeyword(KeywordGroupEntry entry) async {
    await _keywordRepo.delete(entry.id);
    await _articleRepo.unblockByKeyword(entry.keyword);
  }

  @override
  Future<void> editKeyword(
      KeywordGroupEntry entry, String newKeyword, bool newWholeWord) async {
    // Old matches are invalidated before the new text is written, and the
    // new text is matched retroactively — same shape as adding a fresh
    // keyword, just against the old text's leftovers instead of nothing.
    await _articleRepo.unblockByKeyword(entry.keyword);
    await _keywordRepo.setKeyword(entry.id, newKeyword);
    await _keywordRepo.setWholeWord(entry.id, newWholeWord);
    await _articleRepo.retroactivelyBlock(newKeyword, newWholeWord);
  }
}
