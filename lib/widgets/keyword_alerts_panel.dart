import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/keyword_alert.dart';
import '../repositories/alert_match_repository.dart';
import '../repositories/keyword_alert_repository.dart';
import '../services/loading_controller.dart';
import 'bubble_panel.dart';
import 'fetching_indicator.dart';
import 'notification_banner.dart';

/// Manages the alert keywords themselves: add, edit, delete, and how many
/// cards each one currently accounts for.
///
/// It used to be a thin skin over [KeywordGroupPanel], expanding each keyword
/// to list its matched articles. That is now the Alerts tab's job, and the two
/// are not the same job: a tab can show a card with a thumbnail, a read state
/// and a bin, where a bubble that grows out of a toolbar button can only ever
/// show a cramped list. This panel is the settings for the feature; the tab is
/// the feature.
///
/// [KeywordGroupPanel] is deliberately not reused. It still backs the keyword
/// blocklist unchanged, and its controller hands back a single
/// `String? keywordOf(Article)` — the wrong shape now that one article can
/// carry several alert keywords at once, which was the whole point of giving
/// matches their own rows.
class KeywordAlertsPanel extends StatefulWidget {
  const KeywordAlertsPanel({super.key});

  @override
  State<KeywordAlertsPanel> createState() => _KeywordAlertsPanelState();
}

class _KeywordAlertsPanelState extends State<KeywordAlertsPanel> {
  final _alertRepo = KeywordAlertRepository();
  final _matchRepo = AlertMatchRepository();
  final _bannerKey = GlobalKey<NotificationBannerState>();

  List<KeywordAlert> _keywords = [];
  Map<String, int> _counts = const {};
  bool _loading = true;

  bool _addingKeyword = false;
  final _addController = TextEditingController();
  final _addFocus = FocusNode();
  bool _addWholeWord = false;

  int? _editingId;
  final _editController = TextEditingController();
  final _editFocus = FocusNode();
  bool _editWholeWord = false;

  /// The pending "this will destroy N cards" confirmation, rendered inline.
  ///
  /// It is a [Completer] rather than a `showDialog` future because the answer
  /// is awaited in the middle of [_delete] and [_submitEdit] but produced by a
  /// button several rebuilds later. See [_confirmLosingEntries] for why the
  /// dialog had to go.
  Completer<bool>? _confirmCompleter;
  String? _confirmKeyword;
  int _confirmOrphans = 0;

  /// Used to scroll the prompt into view once it exists — see
  /// [_confirmLosingEntries].
  final _confirmKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    // The bubble can be dismissed by tapping its scrim while a confirmation
    // is still on screen. Its caller is parked on this future inside
    // LoadingController.run, which would otherwise never return and leave the
    // global busy count stuck at one.
    final pending = _confirmCompleter;
    _confirmCompleter = null;
    if (pending != null && !pending.isCompleted) pending.complete(false);
    _addController.dispose();
    _addFocus.dispose();
    _editController.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final keywords = await _alertRepo.getAll();
    // countsByKeyword() runs from the keyword table outward, so a keyword that
    // has matched nothing still reports 0 rather than dropping out of the map
    // and rendering as a blank where its count should be.
    final counts = await _matchRepo.countsByKeyword();
    if (!mounted) return;
    setState(() {
      _keywords = keywords;
      _counts = counts;
      _loading = false;
    });
  }

  /// The already-configured alert with this exact keyword, if any.
  ///
  /// Compared exactly, because `keyword_alerts.keyword` is UNIQUE without
  /// COLLATE NOCASE — "PS5" and "ps5" really are two separate alerts there, so
  /// treating them as one here would reject an add the table would have
  /// accepted.
  KeywordAlert? _existingKeyword(String keyword) {
    for (final k in _keywords) {
      if (k.keyword == keyword) return k;
    }
    return null;
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
    _resolveConfirm(false);
    _addController.clear();
    setState(() => _addingKeyword = false);
  }

  Future<void> _submitAddKeyword() async {
    final text = _addController.text.trim();
    if (text.isEmpty) return;
    // `insert` uses ConflictAlgorithm.ignore, so re-adding an existing keyword
    // is a no-op on keyword_alerts — the stored whole_word survives untouched
    // and the returned id is 0. Without this guard the backfill below would
    // then run with the whole-word setting the user just typed rather than the
    // one actually stored, permanently writing match rows the configured alert
    // would never have produced ("zelda" whole-word-on matching "Zeldathon").
    if (_existingKeyword(text) != null) {
      _bannerKey.currentState
          ?.show(AppLocalizations.of(context)!.alertKeywordExists(text));
      return;
    }
    final wholeWord = _addWholeWord;
    await LoadingController.instance.run(() async {
      final alert = await _alertRepo.insert(KeywordAlert(
        keyword: text,
        wholeWord: wholeWord,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      // A keyword added today has to find yesterday's articles — matching only
      // at fetch time was the reported bug. The backfill is silent by
      // construction: it writes match rows and returns, and nothing here posts
      // a notification for what it wrote. Notifications come only from
      // genuinely new fetched articles, because a new keyword matching two
      // hundred old ones would otherwise arrive as two hundred pings for
      // articles the user has already scrolled past.
      await _matchRepo.backfillKeyword(alert.keyword, alert.wholeWord);
      HapticFeedback.lightImpact();
      await _load();
    }, label: 'Adding keyword');
    if (!mounted) return;
    _addController.clear();
    setState(() => _addingKeyword = false);
  }

  // ── Edit (long-press) ────────────────────────────────────────────────────

  void _openEdit(KeywordAlert entry) {
    HapticFeedback.lightImpact();
    // Starting a new edit abandons whatever the last one was waiting for.
    _resolveConfirm(false);
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

  /// Closes the edit form, and answers any confirmation it is waiting on.
  ///
  /// Without the [_resolveConfirm], cancelling the form left the prompt on
  /// screen with [_submitEdit] still parked on its future — and answering it
  /// afterwards committed the rename the user had just cancelled. Closing the
  /// form is the user saying no to the whole operation, so the pending answer
  /// is no.
  void _closeEdit() {
    _resolveConfirm(false);
    setState(() => _editingId = null);
  }

  Future<void> _submitEdit(KeywordAlert entry) async {
    final text = _editController.text.trim();
    if (text.isEmpty) return;
    final wholeWord = _editWholeWord;
    if (text == entry.keyword && wholeWord == entry.wholeWord) {
      _closeEdit();
      return;
    }

    // keyword_alerts.keyword is UNIQUE and setKeyword is a bare update, so
    // renaming onto a keyword that already exists raises sqlite error 2067.
    // Nothing catches it — the panel's callbacks are VoidCallbacks and the app
    // installs no global async error handler — so the throw would be silent.
    // Caught here instead, before anything has been written.
    final clash = _existingKeyword(text);
    if (clash != null && clash.id != entry.id) {
      _bannerKey.currentState
          ?.show(AppLocalizations.of(context)!.alertKeywordExists(text));
      return;
    }

    // An edit drops the old keyword's rows and rebuilds from scratch, and the
    // rebuild can only see articles still on the device. A match whose article
    // has since been cleaned up or retired is gone for good — the snapshot was
    // the last copy of it. So the same warning the delete path shows applies
    // here, counted the same way: only the cards whose *only* keyword is this
    // one actually disappear.
    if (!await _confirmLosingEntries(entry.keyword)) return;

    await LoadingController.instance.run(() async {
      // Re-checked here, not just above. The guard before the confirmation is
      // computed and then the panel parks on the user's answer for as long as
      // they like, and it stays interactive throughout — they can add the very
      // keyword being renamed onto while the prompt is on screen, which made
      // the earlier check stale and let the 2067 throw through after all.
      // _load() has rewritten _keywords by then, so asking again is enough.
      final stillClashes = _existingKeyword(text);
      if (stillClashes != null && stillClashes.id != entry.id) {
        if (mounted) {
          _bannerKey.currentState
              ?.show(AppLocalizations.of(context)!.alertKeywordExists(text));
        }
        return;
      }
      // Rename first, delete second. The rename is the step that can fail —
      // and if it ever does, the snapshots are still there. Deleting first
      // meant a failed rename destroyed the matches and changed nothing else,
      // which for an article already retired is unrecoverable: backfillKeyword
      // rebuilds from `articles`, and the snapshot outliving `articles` is the
      // entire reason this table exists.
      await _alertRepo.setKeyword(entry.id!, text);
      await _alertRepo.setWholeWord(entry.id!, wholeWord);
      await _matchRepo.deleteByKeyword(entry.keyword);
      await _matchRepo.backfillKeyword(text, wholeWord);
      await _load();
    }, label: 'Updating keyword');
    if (!mounted) return;
    setState(() => _editingId = null);
  }

  // ── Delete ───────────────────────────────────────────────────────────────

  Future<void> _delete(KeywordAlert entry) async {
    if (!await _confirmLosingEntries(entry.keyword)) return;
    await LoadingController.instance.run(() async {
      // Matches first, then the keyword. Reversed, a failure between the two
      // would leave rows behind with no keyword left to explain them — which
      // is the state the old `matched_alert_keyword` column got stuck in.
      await _matchRepo.deleteByKeyword(entry.keyword);
      await _alertRepo.delete(entry.id!);
      HapticFeedback.lightImpact();
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        _bannerKey.currentState?.show(l10n.keywordRemoved(entry.keyword));
      }
      await _load();
    }, label: 'Removing keyword');
  }

  /// Asks before destroying alert cards, and only when there are any.
  ///
  /// The number quoted is [AlertMatchRepository.orphanCountForKeyword], not
  /// the keyword's entry count: a card that also matched another keyword
  /// survives one badge lighter, and counting it here would warn the user
  /// about losing something they keep. When nothing would be lost the prompt
  /// is skipped entirely — a confirmation with nothing to confirm teaches
  /// people to dismiss confirmations.
  ///
  /// Rendered inline, not with `showDialog`. This panel is presented by
  /// [showBubblePanel] as a raw `Overlay.insert`, which sits *above* every
  /// Navigator route; a dialog pushed from here is therefore painted
  /// underneath the bubble's own BackdropFilter and scrim, and every tap
  /// aimed at Delete is swallowed by the scrim's dismiss handler instead —
  /// so the confirmation was invisible and the keyword could never be
  /// deleted. It is the same rule [_buildKeywordForm] already states: nothing
  /// may stack a new layer above this panel.
  Future<bool> _confirmLosingEntries(String keyword) async {
    final orphans = await _matchRepo.orphanCountForKeyword(keyword);
    if (orphans == 0) return true;
    if (!mounted) return false;
    // Any prompt already on screen loses — the user has moved on to another
    // row, and leaving the old future dangling would hang its caller forever.
    _resolveConfirm(false);
    final completer = Completer<bool>();
    setState(() {
      _confirmCompleter = completer;
      _confirmKeyword = keyword;
      _confirmOrphans = orphans;
    });
    // The prompt replaces its row and is taller than it, so on the last row of
    // a scrolled panel it can extend past the bottom of the bubble's viewport.
    // Being where the user tapped is not enough on its own; it has to be
    // wholly on screen, because a half-visible confirmation is the same dead
    // end as an invisible one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _confirmKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
    return completer.future;
  }

  /// Answers the pending confirmation, if there is one. Safe to call twice.
  void _resolveConfirm(bool value) {
    final completer = _confirmCompleter;
    if (completer == null) return;
    _confirmCompleter = null;
    _confirmKeyword = null;
    if (mounted) {
      setState(() {});
    }
    if (!completer.isCompleted) completer.complete(value);
  }

  /// The inline replacement for the confirmation dialog.
  Widget _buildConfirm(AppLocalizations l10n, ThemeData theme) {
    return Padding(
      key: _confirmKey,
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.deleteAlertKeywordTitle(_confirmKeyword!),
              style: theme.textTheme.bodyLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.deleteAlertKeywordBody(_confirmOrphans),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _resolveConfirm(false),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _resolveConfirm(true),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BubblePanelHeader(
          icon: Icons.notifications_active_outlined,
          title: l10n.keywordAlerts,
        ),
        NotificationBanner(key: _bannerKey),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.keywordAlertsSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: FetchingIndicator(size: 28)),
          )
        else if (_keywords.isEmpty)
          _buildEmptyState(l10n, theme)
        else
          // A plain Column, not a ListView: this panel already sits inside the
          // bubble's own SingleChildScrollView, which is what actually scrolls
          // a long list. Nesting an unbounded ListView inside that would
          // assert.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < _keywords.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                _buildRow(l10n, theme, _keywords[i]),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 48,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text(
              l10n.noKeywordAlerts,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.keywordAlertsEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One keyword. Flat — there is nothing to expand into. Tapping a keyword to
  /// read its articles is what the Alerts tab does, with room to do it
  /// properly.
  Widget _buildRow(
      AppLocalizations l10n, ThemeData theme, KeywordAlert entry) {
    // The confirmation replaces the row it is about, rather than sitting at
    // the top of the panel. The panel is a Column inside the bubble's
    // SingleChildScrollView, height-capped at ~70% of the screen; past about a
    // dozen keywords it scrolls. Putting the prompt at the top then puts it
    // *above the current scroll offset* — to reach the bin on a row below the
    // fold the user has to scroll down first, so the prompt appears entirely
    // off screen and the keyword can never be deleted. That is the same
    // symptom as the showDialog this replaced. Rendered here it is always
    // exactly where the user just tapped.
    if (_confirmKeyword == entry.keyword) return _buildConfirm(l10n, theme);
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

    return InkWell(
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
              l10n.articlesCount(_counts[entry.keyword] ?? 0),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            IconButton(
              icon:
                  Icon(Icons.delete_outline, color: theme.colorScheme.error),
              onPressed: () => _delete(entry),
            ),
          ],
        ),
      ),
    );
  }

  /// The add and edit forms are inline expansions of this panel, not a
  /// `showModalBottomSheet` and not a second stacked bubble. Stacking another
  /// route over this one left the bubble's own `BackdropFilter` actively
  /// blurring the very field being typed into — the text went soft as the user
  /// wrote it. Anything that puts a new layer above this panel reintroduces
  /// that.
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
              hintText: l10n.alertKeywordHint,
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
