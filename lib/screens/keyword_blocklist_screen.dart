import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../models/keyword_block.dart';
import '../repositories/article_repository.dart';
import '../repositories/keyword_repository.dart';
import '../services/loading_controller.dart';

class KeywordBlocklistScreen extends StatefulWidget {
  const KeywordBlocklistScreen({super.key});

  @override
  State<KeywordBlocklistScreen> createState() => _KeywordBlocklistScreenState();
}

class _KeywordBlocklistScreenState extends State<KeywordBlocklistScreen> {
  final _keywordRepo = KeywordRepository();
  final _articleRepo = ArticleRepository();
  List<KeywordBlock> _keywords = [];
  List<Article> _blockedArticles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _addKeyword() async {
    final result = await showModalBottomSheet<({String keyword, bool wholeWord})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddKeywordSheet(),
    );
    if (result == null) return;

    await LoadingController.instance.run(() async {
      final kw = await _keywordRepo.insert(KeywordBlock(
        keyword: result.keyword,
        wholeWord: result.wholeWord,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      await _articleRepo.retroactivelyBlock(kw.keyword, kw.wholeWord);
      HapticFeedback.lightImpact();
      await _load();
    }, label: 'Adding keyword');
  }

  Future<void> _delete(KeywordBlock kw) async {
    await LoadingController.instance.run(() async {
      await _keywordRepo.delete(kw.id!);
      await _articleRepo.unblockByKeyword(kw.keyword);
      HapticFeedback.lightImpact();
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.keywordRemoved(kw.keyword))),
        );
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

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.keywordBlocklist), centerTitle: false),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isEmpty = _keywords.isEmpty && _blockedArticles.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.keywordBlocklist),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addKeyword,
        icon: const Icon(Icons.add),
        label: Text(l10n.addKeyword),
      ),
      body: isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.block_rounded,
                      size: 64,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noBlockedKeywords,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.keywordBlocklistEmpty,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                // ── Keywords section ──
                _sectionHeader(l10n.keywordBlocklist, theme),
                if (_keywords.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      l10n.noBlockedKeywords,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                else
                  ..._keywords.asMap().entries.map((entry) {
                    final i = entry.key;
                    final kw = entry.value;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i > 0)
                          const Divider(height: 1, indent: 16, endIndent: 16),
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
                            title: Text(
                              kw.keyword,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
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

                const SizedBox(height: 8),
                const Divider(height: 1),

                // ── Blocked Articles section ──
                _sectionHeader(
                  '${l10n.blockedArticles}'
                  '${_blockedArticles.isNotEmpty ? "  (${_blockedArticles.length})" : ""}',
                  theme,
                ),
                if (_blockedArticles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Text(
                      l10n.noBlockedArticles,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                else
                  ..._blockedArticles.asMap().entries.map((entry) {
                    final i = entry.key;
                    final article = entry.value;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i > 0)
                          const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
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
            ),
    );
  }

  Widget _sectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
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
}

class _AddKeywordSheet extends StatefulWidget {
  const _AddKeywordSheet();

  @override
  State<_AddKeywordSheet> createState() => _AddKeywordSheetState();
}

class _AddKeywordSheetState extends State<_AddKeywordSheet> {
  final _controller = TextEditingController();
  bool _wholeWord = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.pop(context, (keyword: text, wholeWord: _wholeWord));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.blockKeyword,
              style:
                  theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.keywordOrPhrase,
              hintText: l10n.keywordHint,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _wholeWord,
            onChanged: (v) => setState(() => _wholeWord = v ?? false),
            title: Text(l10n.wholeWordOnly),
            subtitle: Text(l10n.wholeWordSubtitle),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _submit,
            child: Text(l10n.add),
          ),
        ],
      ),
    );
  }
}
