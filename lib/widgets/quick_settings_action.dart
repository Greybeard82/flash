import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../repositories/settings_repository.dart';
import 'bubble_panel.dart';
import 'quick_settings_bubble.dart';

/// The app-bar button that opens Quick Settings.
///
/// One widget rather than the same dozen lines in four screens, and it is
/// stateful only to own its own anchor key — the bubble grows out of the
/// button that was tapped, so each screen's copy needs a key of its own.
///
/// **FeedScreen deliberately does not use this**, and that is not an
/// oversight left over from before this widget existed. Its own
/// `_openBubblePanel` is shared by four bubbles — quick settings, the filter,
/// the blocklist and the alerts panel — and carries two things this widget
/// has no business knowing about: a single guard so only one of those four is
/// ever open at a time, and `_fabFade.settleNow()`, so the FAB cluster is not
/// caught mid-fade behind the scrim. Moving one of those four onto this
/// widget would fragment FeedScreen's own handling rather than consolidate
/// anything.
///
/// It used to matter for a second reason: this widget passes its own State's
/// context to [showBubblePanel], which is an app-bar IconButton, and the old
/// host measurement believed whatever context it was handed. FeedScreen
/// passing something screen-sized was the only thing keeping it correct.
/// [showBubblePanel] now measures from the anchor's Scaffold instead, so both
/// call shapes are right — the divergence is a difference in responsibility,
/// not in reliability.
///
/// The settings are read fresh on every open rather than passed in. The panel
/// edits live values, and a cached snapshot taken when the screen was built
/// would show a stale switch position after the same setting had been changed
/// from another screen's copy of this button.
class QuickSettingsAction extends StatefulWidget {
  const QuickSettingsAction({super.key});

  @override
  State<QuickSettingsAction> createState() => _QuickSettingsActionState();
}

class _QuickSettingsActionState extends State<QuickSettingsAction> {
  final _anchorKey = GlobalKey();
  final _settingsRepo = SettingsRepository();
  OverlayEntry? _open;

  Future<void> _openPanel() async {
    if (_open?.mounted ?? false) return;
    final settings = await _settingsRepo.getAll();
    if (!mounted) return;
    _open = showBubblePanel(
      context: context,
      anchorKey: _anchorKey,
      child: QuickSettingsBubble(initial: settings),
    );
  }

  @override
  void dispose() {
    // The overlay outlives this State otherwise, and its scrim would keep
    // swallowing taps on a screen that has gone.
    if (_open?.mounted ?? false) _open!.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _anchorKey,
      onPressed: _openPanel,
      tooltip: AppLocalizations.of(context)!.quickSettingsTooltip,
      icon: const Icon(Icons.tune_rounded),
    );
  }
}
