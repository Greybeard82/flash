import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../services/article_opener.dart';
import '../services/loading_controller.dart';
import 'bubble_panel.dart';
import 'spinning_refresh_icon.dart';
import 'notification_banner.dart';
import '../theme/app_theme.dart';

/// One keyword row's identity and matching settings, independent of whether
/// it backs a [KeywordBlock] or a [KeywordAlert] — the two models have the
/// same shape for everything this panel needs.
class KeywordGroupEntry {
  final int id;
  final String keyword;
  final bool wholeWord;

  const KeywordGroupEntry({
    required this.id,
    required this.keyword,
    required this.wholeWord,
  });
}

/// Bridges [KeywordGroupPanel] to either the blocklist or the alerts
/// repositories, which differ in method names and in whether a match also
/// bookmarks the article. The panel itself knows nothing about
/// `KeywordRepository` / `KeywordAlertRepository` / which article column
/// holds the match — only this.
abstract class KeywordGroupController {
  Future<List<KeywordGroupEntry>> loadKeywords();

  /// Every article this kind of keyword has matched, across all keywords —
  /// the panel groups them client-side by [keywordOf]. Realistic volumes for
  /// a personal RSS reader make this cheaper than a query per keyword.
  Future<List<Article>> loadArticles();

  /// The keyword text [article] matched under this controller's scheme, or
  /// null if it doesn't belong to this list at all (shouldn't happen for
  /// anything [loadArticles] returns, but keeps the grouping total).
  String? keywordOf(Article article);

  Future<void> addKeyword(String keyword, bool wholeWord);
  Future<void> deleteKeyword(KeywordGroupEntry entry);

  /// Changes [entry]'s text and/or whole-word setting. Every match the old
  /// text produced is invalidated and the new text is matched retroactively,
  /// so counts and article lists never show a stale spelling.
  Future<void> editKeyword(
      KeywordGroupEntry entry, String newKeyword, bool newWholeWord);
}

/// Shared UI for the Keyword Blocklist and Keyword Alerts panels: one
/// collapsible group per keyword, each showing a live match count, expanding
/// on tap to list its own articles, and opening an inline edit form on
/// long-press. The two panels differ only in [controller] and in the labels
/// passed here — the interaction model, layout, and match-invalidation
/// behaviour all live in one place.
///
/// The add-keyword and edit-keyword forms are inline expansions, not a
/// `showModalBottomSheet` or a second stacked bubble — stacking a second
/// route on top of this panel's own bubble left its `BackdropFilter`
/// actively blurring the very field being typed into.
class KeywordGroupPanel extends StatefulWidget {
  final KeywordGroupController controller;
  final IconData icon;
  final String title;
  final String subtitle;
  final IconData matchIcon;
  final String addFieldHint;
  final IconData emptyIcon;
  final String emptyTitle;
  final String emptyBody;

  const KeywordGroupPanel({
    super.key,
    required this.controller,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.matchIcon,
    required this.addFieldHint,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.emptyBody,
  });

  @override
  State<KeywordGroupPanel> createState() => _KeywordGroupPanelState();
}

class _KeywordGroupPanelState extends State<KeywordGroupPanel> {
  final _bannerKey = GlobalKey<NotificationBannerState>();
  List<KeywordGroupEntry> _keywords = [];
  List<Article> _articles = [];
  bool _loading = true;

  final Set<int> _expanded = {};

  bool _addingKeyword = false;
  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  bool _addWholeWord = false;

  int? _editingId;
  final _editController = TextEditingController();
  final _editFocus = FocusNode();
  bool _editWholeWord = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _addController.dispose();
    _addFocus.dispose();
    _editController.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final keywords = await widget.controller.loadKeywords();
    final articles = await widget.controller.loadArticles();
    if (mounted) {
      setState(() {
        _keywords = keywords;
        _articles = articles;
        _loading = false;
      });
    }
  }

  // ── Add ──────────────────────────────────────────────────────────────────

  void _openAddKeyword() {
    setState(() {
      _editingId = null;
      _addingKeyword = true;
      _addWholeWord = false;
    });
    // The list/empty-state above owns initial focus. Requesting it after this
    // frame is the reliable way to move the caret into the new field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addFocus.requestFocus();
    });
  }

  void _closeAddKeyword() {
    _addController.clear();
    setState(() => _addingKeyword = false);
  }

  Future<void> _submitAddKeyword() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    final wholeWord = _addWholeWord;
    await LoadingController.instance.run(() async {
      await widget.controller.addKeyword(text, wholeWord);
      HapticFeedback.lightImpact();
      await _load();
    }, label: 'Adding keyword');
    if (!mounted) return;
    _addController.clear();
    setState(() => _addingKeyword = false);
  }

  // ── Edit (long-press) ────────────────────────────────────────────────────

  void _openEdit(KeywordGroupEntry entry) {
    HapticFeedback.lightImpact();
    _addController.clear();
    _editController.text = entry.keyword;
    setState(() {
      _addingKeyword = false;
      _editingId = entry.id;
      _editWholeWord = entry.wholeWord;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  void _closeEdit() => setState(() => _editingId = null);

  Future<void> _submitEdit(KeywordGroupEntry entry) async {
    final text = _editController.text.trim();
    if (text.isEmpty) return;
    final wholeWord = _editWholeWord;
    await LoadingController.instance.run(() async {
      await widget.controller.editKeyword(entry, text, wholeWord);
      await _load();
    }, label: 'Updating keyword');
    if (!mounted) return;
    setState(() => _editingId = null);
  }

  // ── Delete / expand / open ───────────────────────────────────────────────

  Future<void> _delete(KeywordGroupEntry entry) async {
    await LoadingController.instance.run(() async {
      await widget.controller.deleteKeyword(entry);
      HapticFeedback.lightImpact();
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        _bannerKey.currentState?.show(l10n.keywordRemoved(entry.keyword));
      }
      _expanded.remove(entry.id);
      await _load();
    }, label: 'Removing keyword');
  }

  void _toggleExpanded(int id) {
    setState(() {
      if (!_expanded.remove(id)) _expanded.add(id);
    });
  }

  Future<void> _openArticle(Article article) async {
    await openArticle(context, article);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final byKeyword = <String, List<Article>>{};
    for (final article in _articles) {
      final kw = widget.controller.keywordOf(article);
      if (kw != null) (byKeyword[kw] ??= []).add(article);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BubblePanelHeader(icon: widget.icon, title: widget.title),
        NotificationBanner(key: _bannerKey),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            widget.subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_addingKeyword)
          _buildKeywordForm(
            l10n,
            controller: _addController,
            focus: _addFocus,
            wholeWord: _addWholeWord,
            onWholeWordChanged: (v) => setState(() => _addWholeWord = v),
            onCancel: _closeAddKeyword,
            onSubmit: _submitAddKeyword,
            submitLabel: l10n.add,
          )
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
                child: SpinningRefreshIcon(
                    size: 28, color: theme.colorScheme.primary)),
          )
        else if (_keywords.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.emptyIcon,
                      size: 48, color: theme.flashColors.illustration),
                  const SizedBox(height: 12),
                  Text(
                    widget.emptyTitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.emptyBody,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.flashColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          // A plain Column, not a ListView: this panel already sits inside the
          // bubble's own SingleChildScrollView, which is what actually scrolls
          // a long list. Nesting an unbounded ListView inside that would assert.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < _keywords.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _buildGroup(
                  l10n,
                  theme,
                  _keywords[i],
                  byKeyword[_keywords[i].keyword] ?? const [],
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildGroup(
    AppLocalizations l10n,
    ThemeData theme,
    KeywordGroupEntry entry,
    List<Article> articles,
  ) {
    if (_editingId == entry.id) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: _buildKeywordForm(
          l10n,
          controller: _editController,
          focus: _editFocus,
          wholeWord: _editWholeWord,
          onWholeWordChanged: (v) => setState(() => _editWholeWord = v),
          onCancel: _closeEdit,
          onSubmit: () => _submitEdit(entry),
          submitLabel: l10n.save,
        ),
      );
    }

    final isExpanded = _expanded.contains(entry.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _toggleExpanded(entry.id),
          onLongPress: () => _openEdit(entry),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.keyword,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      if (entry.wholeWord)
                        Text(l10n.wholeWordOnly,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.primary)),
                    ],
                  ),
                ),
                Text(
                  l10n.articlesCount(articles.length),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.flashColors.onSurfaceMuted,
                  ),
                ),
                // Neutral, as in the alerts panel and the Categories
                // header. This one is the blocklist, which handoff 4's
                // Alerts sentence does not reach at all.
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: theme.colorScheme.onSurfaceVariant),
                  onPressed: () => _delete(entry),
                ),
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  // Explicit, because ImplicitlyAnimatedWidget defaults to
                  // Curves.linear: without it the chevron turns at a steady
                  // rate while the section below eases, so the two agree only
                  // at the first and last frame.
                  curve: Curves.easeInOut,
                  child: Icon(Icons.expand_more_rounded,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        // Was an `AnimatedSize` with the same two faults reported on the
        // Categories screen on 17 September: centre-aligned, so it opened
        // outward from the middle, and handed a `SizedBox.shrink()` the
        // moment `isExpanded` went false, so a collapse had nothing left to
        // animate. See [_Collapsible].
        _Collapsible(
          key: ValueKey(entry.id),
          expanded: isExpanded,
          builder: () => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < articles.length; i++) ...[
                      if (i > 0)
                        const Divider(height: 1, indent: 16, endIndent: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          widget.matchIcon,
                          size: 20,
                          // 6.4: onSurfaceMuted. It is a repeated row tick,
                          // not an illustration — the Batch 6 line putting it
                          // under the illustration role is superseded.
                          color: theme.flashColors.onSurfaceMuted,
                        ),
                        title: Text(
                          articles[i].title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: articles[i].feedTitle != null
                            ? Text(
                                articles[i].feedTitle!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            : null,
                        onTap: () => _openArticle(articles[i]),
                      ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeywordForm(
    AppLocalizations l10n, {
    required TextEditingController controller,
    required FocusNode focus,
    required bool wholeWord,
    required ValueChanged<bool> onWholeWordChanged,
    required VoidCallback onCancel,
    required VoidCallback onSubmit,
    required String submitLabel,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: controller,
            focusNode: focus,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmit(),
            decoration: InputDecoration(
              labelText: l10n.keywordOrPhrase,
              hintText: widget.addFieldHint,
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          CheckboxListTile(
            value: wholeWord,
            onChanged: (v) => onWholeWordChanged(v ?? false),
            title: Text(l10n.wholeWordOnly),
            subtitle: Text(l10n.wholeWordSubtitle),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: onCancel, child: Text(l10n.cancel)),
              const SizedBox(width: 8),
              FilledButton(onPressed: onSubmit, child: Text(submitLabel)),
            ],
          ),
        ],
      ),
    );
  }
}

/// A vertical expand/collapse that animates in **both** directions and takes
/// its child back out of the tree once it is closed.
///
/// `AnimatedSize` cannot do the second of those. It animates between the sizes
/// of whatever child it is handed, so a caller that drops the child on the
/// toggling frame leaves it shrinking a box that is already empty: the content
/// disappears at once and only whitespace closes behind it. It also aligns on
/// `Alignment.center`, so growing from a zero-WIDTH `SizedBox.shrink()` opens
/// the content outward from the middle as well as downward.
///
/// Both faults were reported on the Categories screen on 17 September 2026 and
/// this panel had the identical pair. `_FolderSectionState` in
/// `feeds_screen.dart` fixes them inline because it already owns an
/// `AnimationController` for its chevron and the two must share one. Here a
/// single state object drives N keyword rows, so the controller belongs per
/// row — which is this widget.
class _Collapsible extends StatefulWidget {
  final bool expanded;

  /// A builder, not a `Widget`, so a closed row does not pay to describe rows
  /// it is not showing. The `AnimatedSize` this replaced got that for free
  /// from the ternary in its caller; taking the decision in here would
  /// otherwise have quietly given it up.
  final Widget Function() builder;

  const _Collapsible({
    super.key,
    required this.expanded,
    required this.builder,
  });

  @override
  State<_Collapsible> createState() => _CollapsibleState();
}

class _CollapsibleState extends State<_Collapsible>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _reveal;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Matches the AnimatedRotation on the row's chevron, so the turn and
      // the unroll start and stop on the same frame.
      duration: const Duration(milliseconds: 200),
      value: widget.expanded ? 1.0 : 0.0,
    );
    _reveal = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(_Collapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (widget.expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _reveal.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// The one rebuild that unmounts the child, fired when the collapse ends
  /// rather than when it starts.
  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Held until the controller is fully dismissed, so the collapse has
    // something to show; dropped exactly then, because a zero-height
    // SizeTransition still lays its child out.
    final mounted =
        widget.expanded || _controller.status != AnimationStatus.dismissed;
    return SizeTransition(
      sizeFactor: _reveal,
      axisAlignment: -1.0,
      child: mounted ? widget.builder() : const SizedBox.shrink(),
    );
  }
}
