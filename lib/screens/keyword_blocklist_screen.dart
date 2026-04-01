import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/keyword_block.dart';
import '../repositories/article_repository.dart';
import '../repositories/keyword_repository.dart';

class KeywordBlocklistScreen extends StatefulWidget {
  const KeywordBlocklistScreen({super.key});

  @override
  State<KeywordBlocklistScreen> createState() => _KeywordBlocklistScreenState();
}

class _KeywordBlocklistScreenState extends State<KeywordBlocklistScreen> {
  final _keywordRepo = KeywordRepository();
  final _articleRepo = ArticleRepository();
  List<KeywordBlock> _keywords = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keywords = await _keywordRepo.getAll();
    if (mounted) setState(() { _keywords = keywords; _loading = false; });
  }

  Future<void> _addKeyword() async {
    final result = await showModalBottomSheet<({String keyword, bool wholeWord})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddKeywordSheet(),
    );
    if (result == null) return;

    final kw = await _keywordRepo.insert(KeywordBlock(
      keyword: result.keyword,
      wholeWord: result.wholeWord,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
    // Retroactively block matching articles already in the DB
    await _articleRepo.retroactivelyBlock(kw.keyword, kw.wholeWord);
    HapticFeedback.lightImpact();
    _load();
  }

  Future<void> _delete(KeywordBlock kw) async {
    await _keywordRepo.delete(kw.id!);
    await _articleRepo.unblockByKeyword(kw.keyword);
    HapticFeedback.lightImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${kw.keyword}" removed')),
      );
    }
    _load();
  }

  Future<void> _toggleWholeWord(KeywordBlock kw) async {
    final updated = kw.copyWith(wholeWord: !kw.wholeWord);
    await _keywordRepo.setWholeWord(kw.id!, updated.wholeWord);
    // Unblock old matches, then re-apply with new whole-word setting
    await _articleRepo.unblockByKeyword(kw.keyword);
    await _articleRepo.retroactivelyBlock(updated.keyword, updated.wholeWord);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keyword Blocklist'),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addKeyword,
        icon: const Icon(Icons.add),
        label: const Text('Add keyword'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _keywords.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block_rounded,
                          size: 64,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text(
                        'No blocked keywords.',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Articles matching a blocked keyword\nwill be hidden from your feed.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: _keywords.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) {
                    final kw = _keywords[i];
                    return Dismissible(
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
                            ? Text('Whole word only',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ))
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: kw.wholeWord
                                  ? 'Matching whole word only'
                                  : 'Matching anywhere in text',
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
                    );
                  },
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Block keyword', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Keyword or phrase',
              hintText: 'e.g. sponsored, celebrity name…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _wholeWord,
            onChanged: (v) => setState(() => _wholeWord = v ?? false),
            title: const Text('Whole word only'),
            subtitle: const Text('"crypto" won\'t block "cryptocurrency"'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _submit,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
