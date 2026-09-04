import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/keyword_alert.dart';
import '../repositories/keyword_alert_repository.dart';
import '../services/loading_controller.dart';
import 'bubble_panel.dart';
import 'fetching_indicator.dart';
import 'notification_banner.dart';

/// Keyword alerts, extracted from the old full-screen `KeywordAlertsScreen`
/// into a Scaffold-less panel so it can open as a bubble the same way
/// `FilterBubble` and `QuickSettingsBubble` do, rather than a
/// `Navigator.push` away from the feed. All the actual list/add/remove logic
/// is unchanged from the screen it replaces.
class KeywordAlertsPanel extends StatefulWidget {
  const KeywordAlertsPanel({super.key});

  @override
  State<KeywordAlertsPanel> createState() => _KeywordAlertsPanelState();
}

class _KeywordAlertsPanelState extends State<KeywordAlertsPanel> {
  final _bannerKey = GlobalKey<NotificationBannerState>();
  final _repo = KeywordAlertRepository();
  List<KeywordAlert> _keywords = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keywords = await _repo.getAll();
    if (mounted) setState(() { _keywords = keywords; _loading = false; });
  }

  Future<void> _addKeyword() async {
    final result = await showModalBottomSheet<({String keyword, bool wholeWord})>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const AddAlertSheet(),
    );
    if (result == null) return;
    await LoadingController.instance.run(() async {
      await _repo.insert(KeywordAlert(
        keyword: result.keyword,
        wholeWord: result.wholeWord,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ));
      HapticFeedback.lightImpact();
      await _load();
    }, label: 'Adding keyword');
  }

  Future<void> _delete(KeywordAlert kw) async {
    await LoadingController.instance.run(() async {
      await _repo.delete(kw.id!);
      HapticFeedback.lightImpact();
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        _bannerKey.currentState?.show(l10n.keywordRemoved(kw.keyword));
      }
      await _load();
    }, label: 'Removing keyword');
  }

  Future<void> _toggleWholeWord(KeywordAlert kw) async {
    await LoadingController.instance.run(() async {
      await _repo.setWholeWord(kw.id!, !kw.wholeWord);
      await _load();
    }, label: 'Updating keyword');
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
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _addKeyword,
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
          Padding(
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
          )
        else
          // A plain Column, not a ListView.builder: this panel already sits
          // inside the bubble's own SingleChildScrollView (capped at 70% of
          // the screen height), which is what actually scrolls a long list.
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(_keywords.length, (i) {
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
                      child: Icon(Icons.delete_outline, color: theme.colorScheme.onError),
                    ),
                    onDismissed: (_) => _delete(kw),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.notifications_active_outlined,
                          color: theme.colorScheme.primary),
                      title: Text(kw.keyword,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w500)),
                      subtitle: kw.wholeWord
                          ? Text(l10n.wholeWordOnly,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary))
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
          ),
      ],
    );
  }
}

class AddAlertSheet extends StatefulWidget {
  const AddAlertSheet({super.key});

  @override
  State<AddAlertSheet> createState() => _AddAlertSheetState();
}

class _AddAlertSheetState extends State<AddAlertSheet> {
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.addAlertKeyword,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(l10n.addAlertKeywordSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.keywordOrPhrase,
              hintText: l10n.alertKeywordHint,
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
          FilledButton(onPressed: _submit, child: Text(l10n.add)),
        ],
      ),
    );
  }
}
