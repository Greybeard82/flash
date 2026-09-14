import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// The confirmation every destructive action in this app goes through.
///
/// A bottom sheet, never a dialog. Lifted out of `feeds_screen.dart`, where it
/// was a private class two call sites shared and nothing could test — the
/// assertion that matters here is about what it does *not* paint, and a test
/// cannot assert that about a widget it cannot construct.
///
/// **No red.** The confirm button used to take `error` under `onError` behind
/// an `isDestructive` flag, and the flag did nothing else, so it went with the
/// colour. Nothing in this app needs red to say "this deletes things" when the
/// sentence above the button already does: [message] is the full ARB string,
/// naming the category or the feed, and that is where the consequence is
/// actually stated. Red on top of it was decoration that read as an error —
/// as though something had gone wrong, when the user is being asked a
/// question.
///
/// Pinned in `confirm_sheet_no_red_test.dart`.
class ConfirmSheet extends StatelessWidget {
  /// The heading. Short — "Delete category", "Remove feed".
  final String title;

  /// The sentence that does the actual warning. Keep it whole.
  final String message;

  /// The affirmative button's label.
  final String confirmLabel;

  const ConfirmSheet({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // No style override at all: FilledButton's default is
                // `primary`, which is the teal every other confirm in the app
                // already carries.
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
