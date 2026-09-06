import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repositories/settings_repository.dart';
import '../services/settings_notifier.dart';

/// The "mark everything read?" gate, shared by Flash, Alerts and Bookmarks.
///
/// Only the *question* is shared. What each screen then marks read is
/// completely different — Flash retires, cleans up and refetches; Alerts
/// touches `alert_matches` and nothing else; Bookmarks writes read state and
/// stops — so the body stays with the screen and only this comes here.
///
/// It existed once, inside FeedScreen. Alerts grew a mark-all-read with no
/// gate at all, which is how the same button came to be guarded on one screen
/// and unguarded on another; Bookmarks was about to be a third copy. The
/// setting is one flag, so a "don't show again" ticked anywhere has to silence
/// it everywhere, and that only holds if there is one implementation.
///
/// Returns whether to proceed. False for a cancel, a dismissed dialog, or an
/// unmounted caller.
Future<bool> confirmMarkAllRead(BuildContext context) async {
  final settingsRepo = SettingsRepository();
  final settings = await settingsRepo.getAll();
  if (!context.mounted) return false;

  if (!settings.markAllReadConfirm) return true;

  final l10n = AppLocalizations.of(context)!;
  var dontAsk = false;
  final confirmed = await showDialog<bool>(
    context: context,
    // StatefulBuilder so ticking the checkbox rebuilds the dialog alone, not
    // the screen behind it.
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(l10n.markAllReadWarningTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.markAllReadWarningBody),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: dontAsk,
              title: Text(l10n.dontShowAgain,
                  style: Theme.of(ctx).textTheme.bodyMedium),
              onChanged: (v) => setDialogState(() => dontAsk = v ?? false),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text(l10n.markAllReadConfirm),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return false;

  // Only on confirm. Ticking the box and then backing out must not disable
  // the warning.
  if (dontAsk) {
    await settingsRepo.set('mark_all_read_confirm', 'false');
    SettingsNotifier.instance.settingsChanged();
  }
  return true;
}
