import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../models/keyword_block.dart';
import '../repositories/article_repository.dart';
import '../repositories/keyword_repository.dart';
import '../services/loading_controller.dart';
import 'bubble_panel.dart';
import 'fetching_indicator.dart';
import 'notification_banner.dart';

/// Keyword blocklist, extracted from the old full-screen
/// `KeywordBlocklistScreen` into a Scaffold-less panel so it can open as a
/// bubble the same way `FilterBubble` and `QuickSettingsBubble` do, rather
/// than a `Navigator.push` away from the feed. All the actual list/add/
/// remove logic is unchanged from the screen it replaces.
///
/// The add-keyword form is an inline expansion (`_addingKeyword`), not a
/// second `showModalBottomSheet` stacked on top of this panel's own bubble —
/// the bubble's backdrop blur (`bubble_panel.dart`) stays live under a
/// stacked sheet, which put the very field being typed into in front of a
/// layer that was still blurring what's behind it. Same "+ New category"
/// inline-reveal pattern `feeds_screen.dart` already uses.
class KeywordBlocklistPanel extends StatefulWidget {
  const KeywordBlocklistPanel({super.key});

  @override
  State<KeywordBlocklistPanel> createState() => _KeywordBlocklistPanelState();
}

class _KeywordBlocklistPanelState extends State<KeywordBlocklistPanel> {
  final _bannerKey = GlobalKey<NotificationBannerState>();
  final _keywordRepo = KeywordRepository();
  final _articleRepo = ArticleRepository();
  List<KeywordBlock> _keywords = [];
  List<Article> _blockedArticles = [];
  bool _loading = true;

  bool _addingKeyword = false;
  final _keywordController = TextEditingController();
  final _keywordFocus = FocusNode();
  bool _wholeWord = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _keywordFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final keywords = await _keywordRepo.getAll();
    final blocked = await _articleRepo.getBlocked();
    if (mounted) {
      setState(() {
        _keywords = keywords;
        _blockedArticles = blocked;
        _loading = false;
      });
    }
  }

  void _openAddKeyword() {
    setState(() {
      _addingKeyword = true;
      _wholeWord = false;
    });
    // The list/empty-state above owns initial focus. Requesting it after this
    // frame is the reliable way to move the caret into the new field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keywordFocus.requestFocus();
    });
  }

  void _closeAddKeyword() {
    _keywordController.clear();
    setState(() => _addingKeyword = false);
  }

  Future<void> _submitAddKeyword() async {
    final text = _keywordController.text.trim();
    if (text.isEmpty) return;
    final wholeWord = _wholeWord;
    await LoadingController.instance.run(() async {
      final kw = await _keywordRepo.insert(KeywordBlock(
        keyword: text,
        wholeWord: wholeWord,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      await _articleRepo.retroactivelyBlock(kw.keyword, kw.wholeWord);
      HapticFeedback.lightImpact();
      await _load();
    }, label: 'Adding keyword');
    if (!mounted) return;
    _keywordController.clear();
    setState(() => _addingKeyword = false);
  }

  Future<void> _delete(KeywordBlock kw) async {
    await LoadingController.instance.run(() async {
      await _keywordRepo.delete(kw.id!);
      await _articleRepo.unblockByKeyword(kw.keyword);
      HapticFeedback.lightImpact();
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        _bannerKey.currentState?.show(l10n.keywordRemoved(kw.keyword));
      }
      await _load();
    }, label: 'Removing keyword');
  }

  Future<void> _toggleWholeWord(KeywordBlock kw) async {
    await LoadingController.instance.run(() async {
      final updated = kw.copyWith(wholeWord: !kw.wholeWord);
      await _keywordRepo.setWholeWord(kw.id!, updated.wholeWord);
      await _articleRepo.unblockByKeyword(kw.keyword);
      await _articleRepo.retroactivelyBlock(updated.keyword, updated.wholeWord);
      await _load();
    }, label: 'Updating keyword');
  }

  Future<void> _openArticle(Article article) async {
    final uri = Uri.tryParse(article.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BubblePanelHeader(
          icon: Icons.block_rounded,
          title: l10n.keywordBlocklist,
        ),
        NotificationBanner(key: _bannerKey),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.keywordBlocklistSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        if (_addingKeyword)
          _buildAddForm(l10n, theme)
        else
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _openAddKeyword,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.addKeyword),
            ),
          ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: FetchingIndicator(size: 28)),
          )
        else if (_keywords.isEmpty && _blockedArticles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.block_rounded,
                      size: 48,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    l10n.noBlockedKeywords,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.keywordBlocklistEmpty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          // A plain Column, not a ListView: this panel already sits inside the
          // bubble's own SingleChildScrollView (capped at 70% of the screen
          // height), which is what actually scrolls a long list. Nesting an
          // unbounded ListView inside that would assert.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_keywords.isNotEmpty) ...[
                _sectionHeader(l10n.keywordBlocklist, theme),
                ...List.generate(_keywords.length, (i) {
                  final kw = _keywords[i];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                      Dismissible(
                        key: ValueKey(kw.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          color: theme.colorScheme.error,
                          child: Icon(Icons.delete_outline,
                              color: theme.colorScheme.onError),
                        ),
                        onDismissed: (_) => _delete(kw),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            kw.keyword,
                            style: theme.textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w500),
                          ),
                          subtitle: kw.wholeWord
                              ? Text(l10n.wholeWordOnly,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ))
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Tooltip(
                                message: kw.wholeWord
                                    ? l10n.matchingWholeWord
                                    : l10n.matchingAnywhere,
                                child: IconButton(
                                  icon: Icon(
                                    kw.wholeWord
                                        ? Icons.text_fields_rounded
                                        : Icons.format_quote_rounded,
                                    color: kw.wholeWord
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurface
                                            .withValues(alpha: 0.4),
                                  ),
                                  onPressed: () => _toggleWholeWord(kw),
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: theme.colorScheme.error),
                                onPressed: () => _delete(kw),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
              if (_blockedArticles.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Divider(height: 1),
                _sectionHeader(
                  '${l10n.blockedArticles}  (${_blockedArticles.length})',
                  theme,
                ),
                ...List.generate(_blockedArticles.length, (i) {
                  final article = _blockedArticles[i];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.block_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        title: Text(
                          article.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: Text(
                          '${article.feedTitle ?? ''}'
                          '${article.blockedKeyword != null ? "  ·  ${l10n.blockedByKeyword(article.blockedKeyword!)}" : ""}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        onTap: () => _openArticle(article),
                      ),
                    ],
                  );
                }),
              ],
            ],
          ),
      ],
    );
  }

  Widget _sectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
      child: Text(
        title.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildAddForm(AppLocalizations l10n, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _keywordController,
            focusNode: _keywordFocus,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submitAddKeyword(),
            decoration: InputDecoration(
              labelText: l10n.keywordOrPhrase,
              hintText: l10n.keywordHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: _wholeWord,
            onChanged: (v) => setState(() => _wholeWord = v ?? false),
            title: Text(l10n.wholeWordOnly),
            subtitle: Text(l10n.wholeWordSubtitle),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: _closeAddKeyword, child: Text(l10n.cancel)),
              const SizedBox(width: 8),
              FilledButton(onPressed: _submitAddKeyword, child: Text(l10n.add)),
            ],
          ),
        ],
      ),
    );
  }
}
