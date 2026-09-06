import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/settings.dart';
import '../repositories/settings_repository.dart';
import '../screens/settings_screen.dart';
import '../services/refresh_service.dart';
import '../services/settings_notifier.dart';
import '../services/unread_badge_service.dart';
import '../theme/app_theme.dart';
import 'bubble_panel.dart';

/// The five palette keys (values stored under `color_palette`), in the order
/// the picker lists them.
const List<String> kPaletteKeys = ['green', 'blue', 'orange', 'red', 'teal_orange'];

String _paletteLabel(AppLocalizations l10n, String key) => switch (key) {
      'green' => l10n.paletteGreen,
      'blue' => l10n.paletteBlue,
      'orange' => l10n.paletteOrange,
      'red' => l10n.paletteRed,
      'teal_orange' => l10n.paletteTealOrange,
      _ => key,
    };

/// Quick settings panel: theme, color palette, and Newspaper mode.
///
/// The theme options are System / Light / Dark — the app's three [ThemeMode]
/// values. Nothing in this app distinguishes a true black/AMOLED mode from
/// dark (every palette's dark background is a generated tonal surface, not
/// pure black), so "black" is presented as Dark rather than implying a
/// fourth mode that does not exist.
///
/// Newspaper mode already overrides the theme *and* palette choice app-wide
/// — `app.dart` forces `ThemeMode.light` and the Newspaper palette whenever
/// it is on, and the Settings screen already greys out its own theme
/// selector to match. This panel reflects that same rule rather than
/// inventing a second one — the palette picker lives inside the same
/// greyed-out block as the theme selector, since a palette choice is equally
/// meaningless while Newspaper mode is overriding it.
class QuickSettingsBubble extends StatefulWidget {
  final AppSettings initial;

  /// Applies the theme immediately, ahead of the DB write. Supplied by the
  /// host screen because the live theme state lives above this widget.
  final ValueChanged<String>? onThemeChanged;

  /// Applies Newspaper mode immediately, same reason.
  final ValueChanged<bool>? onNewspaperChanged;

  /// Applies the color palette immediately, same reason.
  final ValueChanged<String>? onPaletteChanged;

  const QuickSettingsBubble({
    super.key,
    required this.initial,
    this.onThemeChanged,
    this.onNewspaperChanged,
    this.onPaletteChanged,
  });

  @override
  State<QuickSettingsBubble> createState() => _QuickSettingsBubbleState();
}

class _QuickSettingsBubbleState extends State<QuickSettingsBubble>
    with SingleTickerProviderStateMixin {
  final _repo = SettingsRepository();

  late String _theme;
  late bool _newspaper;
  late String _palette;
  late bool _markReadOnScroll;
  late bool _markAllReadConfirm;
  late bool _iconBadge;
  late int _refreshIntervalMinutes;

  /// Collapsed by default — see the picker's own row for why.
  bool _paletteExpanded = false;

  /// Drives the chevron's rotation. Same duration and the same
  /// begin/end turns as the Categories screen's folder chevron
  /// (`_FolderSectionState._chevronController` in `feeds_screen.dart`), so
  /// the two collapse affordances feel like the same control.
  late final AnimationController _paletteChevronController;

  @override
  void initState() {
    super.initState();
    _theme = widget.initial.theme;
    _newspaper = widget.initial.newspaperMode;
    _palette = widget.initial.colorPalette;
    _markReadOnScroll = widget.initial.markReadOnScroll;
    _markAllReadConfirm = widget.initial.markAllReadConfirm;
    _iconBadge = widget.initial.unreadBadgeNotification;
    _refreshIntervalMinutes = widget.initial.refreshIntervalMinutes;
    _paletteChevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 0.0, // starts collapsed, matching _paletteExpanded
    );
  }

  @override
  void dispose() {
    _paletteChevronController.dispose();
    super.dispose();
  }

  void _togglePaletteExpanded() {
    setState(() => _paletteExpanded = !_paletteExpanded);
    if (_paletteExpanded) {
      _paletteChevronController.forward();
    } else {
      _paletteChevronController.reverse();
    }
  }

  Future<void> _setTheme(String value) async {
    setState(() => _theme = value);
    widget.onThemeChanged?.call(value);
    await _repo.set('theme', value);
    SettingsNotifier.instance.settingsChanged();
  }

  Future<void> _setPalette(String value) async {
    // Collapses back down on the same tap that picks one — the picker opens
    // to make a choice, and once it's made there is nothing left to compare.
    setState(() {
      _palette = value;
      _paletteExpanded = false;
    });
    _paletteChevronController.reverse();
    widget.onPaletteChanged?.call(value);
    await _repo.set('color_palette', value);
    SettingsNotifier.instance.settingsChanged();
  }

  Future<void> _setNewspaper(bool value) async {
    setState(() => _newspaper = value);
    widget.onNewspaperChanged?.call(value);
    await _repo.set('newspaper_mode', value.toString());
    SettingsNotifier.instance.settingsChanged();
  }

  /// No `onChanged` callback to the host: FeedScreen already re-applies its
  /// reading settings whenever [SettingsNotifier] fires, so notifying is
  /// enough — unlike theme and Newspaper mode, whose live state lives above
  /// this widget in `app.dart` and needs the extra hand-off.
  Future<void> _setMarkReadOnScroll(bool value) async {
    setState(() => _markReadOnScroll = value);
    await _repo.set('mark_read_on_scroll', value.toString());
    SettingsNotifier.instance.settingsChanged();
  }

  /// The only way back on once the dialog's "Don't show again" has turned
  /// it off.
  Future<void> _setMarkAllReadConfirm(bool value) async {
    setState(() => _markAllReadConfirm = value);
    await _repo.set('mark_all_read_confirm', value.toString());
    SettingsNotifier.instance.settingsChanged();
  }

  /// Rescheduling is the whole point, not a side effect: the stored value is
  /// only ever read when the periodic task is registered, so writing it
  /// without `forceReschedule` leaves WorkManager running on the old interval
  /// until something else happens to re-register it.
  Future<void> _setRefreshInterval(int value) async {
    setState(() => _refreshIntervalMinutes = value);
    await _repo.set('refresh_interval_minutes', value.toString());
    await RefreshService(_repo).schedulePeriodicRefresh(forceReschedule: true);
    SettingsNotifier.instance.settingsChanged();
  }

  /// Turning it off takes the notification down now rather than at whatever
  /// point the unread count next happens to change.
  Future<void> _setIconBadge(bool value) async {
    setState(() => _iconBadge = value);
    await _repo.set(kUnreadBadgeSettingKey, value.toString());
    await UnreadBadgeService.instance.onSettingChanged(enabled: value);
    SettingsNotifier.instance.settingsChanged();
  }

  /// Dismisses the bubble, then pushes Settings.
  ///
  /// The push uses the *navigator* captured before the dismiss, not this
  /// widget's context afterwards. Dismissing tears this subtree down, so
  /// reaching for `context` on the far side is reading a context that may
  /// already be unmounted — the same hazard `_reopenAsKeywordPanel` documents
  /// in feed_screen.dart, where the fix is likewise to do the work from
  /// something that outlives the panel.
  void _openFullSettings() {
    final navigator = Navigator.of(context);
    BubblePanelScope.maybeOf(context)?.dismiss();
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        BubblePanelHeader(
          icon: Icons.tune_rounded,
          title: l10n.quickSettingsTitle,
        ),
        const SizedBox(height: 4),

        // Greyed out while Newspaper mode is on, because Newspaper mode
        // overrides the theme choice entirely.
        Opacity(
          opacity: _newspaper ? 0.4 : 1.0,
          child: IgnorePointer(
            ignoring: _newspaper,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.theme, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'system', label: Text(l10n.themeSystem)),
                    ButtonSegment(value: 'light', label: Text(l10n.themeLight)),
                    ButtonSegment(value: 'dark', label: Text(l10n.themeDark)),
                  ],
                  selected: {_theme},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _setTheme(s.first),
                ),
                const SizedBox(height: 16),
                Text(l10n.colorPalette, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 8),
                // Collapsed to just the current palette by default — five full
                // rows (each its own swatch strip) pushed everything below
                // them, including the refresh interval this panel opens the
                // most, a full page-scroll down. The chevron is the only way
                // back to comparing all five; picking one while expanded
                // (_setPalette) collapses it again on the same tap.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      // AnimatedSize so the panel's own height eases into the
                      // change rather than snapping — `_BubblePanel` sizes
                      // itself to this content via a plain
                      // SingleChildScrollView with no size animation of its
                      // own, so without this the one-to-five-row jump (and
                      // back) would be an instant cut.
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Previewed at the currently active brightness —
                            // Theme.of already resolved System/Light/Dark
                            // against live OS state by the time this builds,
                            // so this is exactly the brightness the person is
                            // looking at right now, not a guess.
                            for (final key
                                in _paletteExpanded ? kPaletteKeys : [_palette])
                              _PaletteRow(
                                selected: _palette == key,
                                label: _paletteLabel(l10n, key),
                                scheme: paletteColorScheme(
                                  palette: key,
                                  brightness: theme.brightness,
                                ),
                                onTap: () => _setPalette(key),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _togglePaletteExpanded,
                      visualDensity: VisualDensity.compact,
                      icon: RotationTransition(
                        turns: Tween(begin: -0.25, end: 0.0)
                            .animate(_paletteChevronController),
                        child: Icon(Icons.expand_more_rounded,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.7)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_newspaper)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.newspaperModeOverridesTheme,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),

        const SizedBox(height: 12),
        // Above the switches: how often the app fetches is the most
        // consequential thing on this panel, and the only one here that
        // changes what the device does while the app is closed.
        Text(l10n.backgroundRefreshInterval, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 4),
        _RefreshIntervalField(
          value: _refreshIntervalMinutes,
          onChanged: _setRefreshInterval,
        ),

        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.newspaperMode, style: theme.textTheme.bodyMedium),
          subtitle: Text(
            l10n.newspaperModeSubtitle,
            style: theme.textTheme.labelSmall,
          ),
          value: _newspaper,
          onChanged: _setNewspaper,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.markReadOnScroll, style: theme.textTheme.bodyMedium),
          subtitle: Text(
            l10n.markReadOnScrollSubtitle,
            style: theme.textTheme.labelSmall,
          ),
          value: _markReadOnScroll,
          onChanged: _setMarkReadOnScroll,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title:
              Text(l10n.confirmMarkAllRead, style: theme.textTheme.bodyMedium),
          value: _markAllReadConfirm,
          onChanged: _setMarkAllReadConfirm,
        ),
        // No subtitle, deliberately. What the badge looks like depends on the
        // launcher — a number on One UI, a dot on a Pixel — and explaining
        // that here made a one-line toggle carry a paragraph about vendor
        // launcher behaviour that nobody flicking a switch needs.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.iconBadge, style: theme.textTheme.bodyMedium),
          value: _iconBadge,
          onChanged: _setIconBadge,
        ),

        const Divider(height: 20),
        // The only way to the full Settings screen. It is reached from this
        // panel rather than the nav bar, and this panel opens from all four
        // top-level screens, so the route in is the same wherever you are.
        InkWell(
          onTap: _openFullSettings,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Icon(Icons.settings_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(l10n.moreSettings,
                      style: theme.textTheme.bodyMedium),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One selectable row in the palette picker: a strip previewing the
/// palette's actual generated tones, its name, and a checkmark when selected
/// — colors pulled from the real [ColorScheme] rather than a separate set of
/// preview constants that could drift from what the palette actually renders.
class _PaletteRow extends StatelessWidget {
  final bool selected;
  final String label;
  final ColorScheme scheme;
  final VoidCallback onTap;

  const _PaletteRow({
    required this.selected,
    required this.label,
    required this.scheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.4),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              _PaletteSwatchStrip(scheme: scheme),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded,
                    color: theme.colorScheme.primary, size: 20)
              else
                const SizedBox(width: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three swatches — primary, secondary, surface — from one palette's
/// generated [ColorScheme], side by side as a single small strip.
class _PaletteSwatchStrip extends StatelessWidget {
  final ColorScheme scheme;

  const _PaletteSwatchStrip({required this.scheme});

  @override
  Widget build(BuildContext context) {
    Widget swatch(Color color) => Container(
          width: 18,
          height: 28,
          color: color,
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            swatch(scheme.primary),
            swatch(scheme.secondary),
            swatch(scheme.surface),
          ],
        ),
      ),
    );
  }
}

/// (minutes, label) pairs, in the order both the field and its menu list
/// them — identical to the original `DropdownMenuItem` list.
List<(int, String)> _refreshIntervalOptions(AppLocalizations l10n) => [
      (15, l10n.every15Minutes),
      (30, l10n.every30Minutes),
      (60, l10n.everyHour),
      (180, l10n.every3Hours),
      (360, l10n.every6Hours),
      (0, l10n.manualOnly),
    ];

/// The background-refresh-interval selector.
///
/// Was a plain `DropdownButton<int>`, then briefly a `PopupMenuButton` with
/// `useRootNavigator: true`. Neither worked. On-device testing (an
/// accessibility dump taken at the same instant as a screenshot) found both
/// popups genuinely opening — every option present and focusable, a
/// full-screen dismiss barrier and all — while painting nothing: the popup
/// rendered underneath this bubble's own `OverlayEntry`
/// (`bubble_panel.dart`'s `showBubblePanel`, a manual `Overlay.insert`
/// rather than a route). `useRootNavigator` didn't change that, because this
/// app has exactly one `Navigator` — routing "through the root" is the same
/// Navigator either way, and that Navigator inserts a newly pushed route's
/// entries relative to *its own* bookkeeping, immediately above whatever it
/// last knew was on top. It has no idea the bubble's raw entry got appended
/// afterward by a completely different mechanism, so the new route lands
/// below it regardless of which Navigator pushed it. And because the popup
/// was a route while the bubble is not, dismissing the bubble did not close
/// it either: the route stayed alive, and reappeared — now unobscured, so
/// visible for the first time — floating over whatever screen came next,
/// still eating the tap after that.
///
/// The fix is to stop using a route at all. This is its own small overlay
/// entry, opened and positioned the same way `showBubblePanel` opens the
/// bubble that hosts it (`Overlay.of(context).insert`, anchored to this
/// field's own on-screen rect) — so it is guaranteed to paint above the
/// bubble by construction: it is inserted after the bubble's entry, into
/// the same `Overlay`, the same way the bubble itself was inserted after
/// whatever screen was already showing. `registerBackDismiss` gives it the
/// same back-press reach every `_BubblePanel` already has, for the same
/// reason [dismissTopBubblePanel] exists at all.
class _RefreshIntervalField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _RefreshIntervalField({required this.value, required this.onChanged});

  @override
  State<_RefreshIntervalField> createState() => _RefreshIntervalFieldState();
}

class _RefreshIntervalFieldState extends State<_RefreshIntervalField> {
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
    if (identical(_menu, entry)) _menu = null;
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
    _menu = entry;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final options = _refreshIntervalOptions(l10n);
    final currentLabel = options.firstWhere((o) => o.$1 == widget.value).$2;

    // The same full-width, underline-free look `isExpanded: true` gave the
    // DropdownButton this replaced.
    return InkWell(
      key: _fieldKey,
      borderRadius: BorderRadius.circular(8),
      onTap: _openMenu,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(currentLabel, style: theme.textTheme.titleMedium),
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
/// tap-to-dismiss layer behind a compact option list anchored to
/// [anchor] — [_RefreshIntervalField]'s own on-screen rect at the moment it
/// was tapped, the same "measure once, position from that" approach
/// `_BubblePanel` takes with its anchor button.
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
  /// `_BubblePanel` solves for itself, for the same reason (an
  /// `OverlayEntry` has no `ModalRoute` of its own for `PopScope` to answer
  /// to).
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
    final options = _refreshIntervalOptions(l10n);

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
      ],
    );
  }
}
