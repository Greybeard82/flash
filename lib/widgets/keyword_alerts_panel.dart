import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../models/keyword_alert.dart';
import '../repositories/article_repository.dart';
import '../repositories/keyword_alert_repository.dart';
import 'keyword_group_panel.dart';

/// Keyword alerts, rendered by the shared [KeywordGroupPanel] — one
/// collapsible group per keyword, showing the articles it matched. This file
/// only supplies the [KeywordGroupController] that talks to
/// [KeywordAlertRepository] / [ArticleRepository.getAlertMatches] and the
/// labels that distinguish this from [KeywordBlocklistPanel].
class KeywordAlertsPanel extends StatelessWidget {
  const KeywordAlertsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return KeywordGroupPanel(
      controller: _AlertsGroupController(),
      icon: Icons.notifications_active_outlined,
      title: l10n.keywordAlerts,
      subtitle: l10n.keywordAlertsSubtitle,
      matchIcon: Icons.notifications_active_outlined,
      addFieldHint: l10n.alertKeywordHint,
      emptyIcon: Icons.notifications_none_rounded,
      emptyTitle: l10n.noKeywordAlerts,
      emptyBody: l10n.keywordAlertsEmpty,
    );
  }
}

class _AlertsGroupController implements KeywordGroupController {
  final _alertRepo = KeywordAlertRepository();
  final _articleRepo = ArticleRepository();

  @override
  Future<List<KeywordGroupEntry>> loadKeywords() async {
    final keywords = await _alertRepo.getAll();
    return [
      for (final k in keywords)
        KeywordGroupEntry(id: k.id!, keyword: k.keyword, wholeWord: k.wholeWord),
    ];
  }

  @override
  Future<List<Article>> loadArticles() => _articleRepo.getAlertMatches();

  @override
  String? keywordOf(Article article) => article.matchedAlertKeyword;

  @override
  Future<void> addKeyword(String keyword, bool wholeWord) async {
    final kw = await _alertRepo.insert(KeywordAlert(
      keyword: keyword,
      wholeWord: wholeWord,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    await _articleRepo.retroactivelyMatchAlert(kw.keyword, kw.wholeWord);
  }

  @override
  Future<void> deleteKeyword(KeywordGroupEntry entry) async {
    await _alertRepo.delete(entry.id);
    // Deleting an alert used to leave matched_alert_keyword dangling on every
    // article it had matched — they stayed bookmarked forever with no
    // keyword left to explain why, and getAlertMatches() kept returning them
    // under a group that no longer existed.
    await _articleRepo.clearAlertMatchesByKeyword(entry.keyword);
  }

  @override
  Future<void> editKeyword(
      KeywordGroupEntry entry, String newKeyword, bool newWholeWord) async {
    // Old matches are invalidated before the new text is written, and the
    // new text is matched retroactively — same shape as adding a fresh
    // alert, just against the old text's leftovers instead of nothing.
    await _articleRepo.clearAlertMatchesByKeyword(entry.keyword);
    await _alertRepo.setKeyword(entry.id, newKeyword);
    await _alertRepo.setWholeWord(entry.id, newWholeWord);
    await _articleRepo.retroactivelyMatchAlert(newKeyword, newWholeWord);
  }
}
