import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'bubble_panel.dart';

/// (minutes, label) pairs, in the order both the field and its menu list them.
///
/// 30 minutes is the floor and 6 hours the ceiling, with a plain hourly ladder
/// between them; the 3-hour default sits in the middle of that ladder rather
/// than at either end. 15 minutes is deliberately absent — Android clamps a
/// PeriodicWorkRequest at 15 minutes anyway, so it was the one entry that
/// promised something the platform would not actually deliver.
///
/// 0 cancels the periodic task outright, which is why it reads "Never".
List<(int, String)> refreshIntervalOptions(AppLocalizations l10n) => [
      (30, l10n.every30Minutes),
      (60, l10n.everyHour),
      (120, l10n.every2Hours),
      (180, l10n.every3Hours),
      (240, l10n.every4Hours),
      (300, l10n.every5Hours),
      (360, l10n.every6Hours),
      (0, l10n.manualOnly),
    ];

/// The background-refresh-interval selector.
///
/// Lives in its own file because it is no longer tied to the Quick Settings
/// bubble it was written for — but the overlay machinery below is still shaped
/// by that origin, and has to stay that way while it is used anywhere inside a
/// bubble panel.
///
/// Was a plain `DropdownButton<int>`, then briefly a `PopupMenuButton` with
/// `useRootNavigator: true`. Neither worked. On-device testing (an
/// accessibility dump taken at the same instant as a screenshot) found both
/// popups genuinely opening — every option present and focusable, a
/// full-screen dismiss barrier and all — while painting nothing: the popup
/// rendered underneath the hosting bubble's own `OverlayEntry`
/// (`bubble_panel.dart`'s `showBubblePanel`, a manual `Overlay.insert` rather
/// than a route). `useRootNavigator` didn't change that, because this app has
/// exactly one `Navigator` — routing "through the root" is the same Navigator
/// either way, and that Navigator inserts a newly pushed route's entries
/// relative to *its own* bookkeeping, immediately above whatever it last knew
/// was on top. It has no idea a bubble's raw entry got appended afterward by a
/// completely different mechanism, so the new route lands below it regardless
/// of which Navigator pushed it. And because the popup was a route while the
/// bubble is not, dismissing the bubble did not close it either: the route
/// stayed alive, and reappeared — now unobscured, so visible for the first
/// time — floating over whatever screen came next, still eating the tap after
/// that.
///
/// The fix is to stop using a route at all. This is its own small overlay
/// entry, opened and positioned the same way `showBubblePanel` opens a bubble
/// (`Overlay.of(context).insert`, anchored to this field's own on-screen rect)
/// — so it is guaranteed to paint above anything already in the overlay by
/// construction. `registerBackDismiss` gives it the same back-press reach every
/// `_BubblePanel` has, for the same reason [dismissTopBubblePanel] exists.
class RefreshIntervalField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const RefreshIntervalField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<RefreshIntervalField> createState() => _RefreshIntervalFieldState();
}

class _RefreshIntervalFieldState extends State<RefreshIntervalField> {
  final _fieldKey = GlobalKey();
  OverlayEntry? _menu;

  @override
  void dispose() {
    // The overlay outlives this State otherwise — same reasoning as
    // QuickSettingsAction's own dispose, for the same kind of leak.
    if (_menu?.mounted ?? false) _menu!.remove();
    super.dispose();
  }

  void _closeMenu(OverlayEntry entry) {
    if (entry.mounted) entry.remove();
    if (identical(_menu, entry)) {
      // setState, not a bare assignment: [_menu] drives PopScope.canPop in
      // build, so the route has to learn that back is its own again.
      if (mounted) {
        setState(() => _menu = null);
      } else {
        _menu = null;
      }
    }
  }

  void _openMenu() {
    if (_menu?.mounted ?? false) return;
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final anchor = box.localToGlobal(Offset.zero) & box.size;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _RefreshIntervalMenu(
        anchor: anchor,
        value: widget.value,
        onSelected: (v) {
          widget.onChanged(v);
          _closeMenu(entry);
        },
        onDismiss: () => _closeMenu(entry),
      ),
    );
    Overlay.of(context).insert(entry);
    setState(() => _menu = entry);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final options = refreshIntervalOptions(l10n);
    // orElse rather than a bare firstWhere: a value stored by an older build
    // (15 minutes, say) is no longer in the list, and throwing here would take
    // the whole Settings screen down over a stale row.
    final current = options.firstWhere(
      (o) => o.$1 == widget.value,
      orElse: () => options.firstWhere((o) => o.$1 == 180),
    );

    // PopScope, because registerBackDismiss alone is not enough here.
    //
    // That stack is only ever read by dismissTopBubblePanel(), and the only
    // callers of it are three back handlers in the app shell (lib/app.dart).
    // Those run when the shell itself is the thing handling back — true when
    // this field lived inside the Quick Settings bubble, which is an overlay
    // ABOVE the shell. It is false now: the field lives on SettingsScreen,
    // which is a PUSHED ROUTE, so back is answered by that route's own pop and
    // the shell handler is never consulted. The registered handler became
    // unreachable, and the first back press popped Settings with the menu
    // still open, riding above the outgoing screen for the length of the
    // transition.
    //
    // A PopScope in this widget's own subtree fixes it wherever it is hosted:
    // it is inside whatever route contains the field, so it intercepts that
    // route's pop. registerBackDismiss is kept as well, so the widget still
    // behaves correctly if it is ever put back inside a bubble; the two are
    // idempotent because _closeMenu no-ops on an already-removed entry.
    return PopScope(
      canPop: _menu == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final entry = _menu;
        if (entry != null) _closeMenu(entry);
      },
      child: _buildField(theme, current.$2),
    );
  }

  Widget _buildField(ThemeData theme, String label) {
    // The same full-width, underline-free look `isExpanded: true` gave the
    // DropdownButton this replaced.
    return InkWell(
      key: _fieldKey,
      borderRadius: BorderRadius.circular(8),
      onTap: _openMenu,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.titleMedium),
            ),
            Icon(Icons.arrow_drop_down_rounded,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// The interval menu's own overlay content: a full-screen, invisible
/// tap-to-dismiss layer behind a compact option list anchored to [anchor] —
/// [RefreshIntervalField]'s own on-screen rect at the moment it was tapped,
/// the same "measure once, position from that" approach `_BubblePanel` takes
/// with its anchor button.
class _RefreshIntervalMenu extends StatefulWidget {
  final Rect anchor;
  final int value;
  final ValueChanged<int> onSelected;
  final VoidCallback onDismiss;

  const _RefreshIntervalMenu({
    required this.anchor,
    required this.value,
    required this.onSelected,
    required this.onDismiss,
  });

  @override
  State<_RefreshIntervalMenu> createState() => _RefreshIntervalMenuState();
}

class _RefreshIntervalMenuState extends State<_RefreshIntervalMenu> {
  /// Registered for the lifetime of this overlay, so a system back press
  /// closes the menu instead of walking past it — the same problem
  /// `_BubblePanel` solves for itself, for the same reason (an `OverlayEntry`
  /// has no `ModalRoute` of its own for `PopScope` to answer to).
  late final VoidCallback _backHandler;

  @override
  void initState() {
    super.initState();
    _backHandler = widget.onDismiss;
    registerBackDismiss(_backHandler);
  }

  @override
  void dispose() {
    unregisterBackDismiss(_backHandler);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final options = refreshIntervalOptions(l10n);

    // Eight options are taller than the old six, and this now opens from a
    // full Settings list rather than a short bubble, so the menu is bounded
    // and scrolls rather than running off the bottom of a small screen.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;

    return Stack(
      children: [
        // No dimming — a dropdown, not a modal. Its only job is to catch the
        // outside tap that closes the menu without it also reaching whatever
        // is underneath.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onDismiss,
          ),
        ),
        Positioned(
          left: widget.anchor.left,
          top: widget.anchor.bottom + 4,
          width: widget.anchor.width,
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (minutes, label) in options)
                      InkWell(
                        onTap: () => widget.onSelected(minutes),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  label,
                                  style: minutes == widget.value
                                      ? theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: theme.colorScheme.primary,
                                        )
                                      : theme.textTheme.bodyLarge,
                                ),
                              ),
                              if (minutes == widget.value)
                                Icon(Icons.check_rounded,
                                    size: 18, color: theme.colorScheme.primary),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
