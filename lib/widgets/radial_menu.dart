import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../theme/app_theme.dart';

class RadialMenu extends StatefulWidget {
  final VoidCallback onShare;
  final VoidCallback onDismiss;
  final VoidCallback onBookmark;
  final Article article;

  /// Removes this card from wherever it was opened from, when that is a thing
  /// the surface can do.
  ///
  /// Null everywhere but the Alerts tab. An alert match is a permanent record
  /// with no article row behind it, so nothing else in the app can retire it —
  /// dismissing it by hand is the only way it ever goes away, and the menu the
  /// user already long-presses is where that belongs. Null keeps the
  /// three-button layout byte for byte as it was.
  final VoidCallback? onDelete;

  const RadialMenu({
    super.key,
    required this.onShare,
    required this.onDismiss,
    required this.onBookmark,
    required this.article,
    this.onDelete,
  });

  @override
  State<RadialMenu> createState() => _RadialMenuState();
}

class _RadialMenuState extends State<RadialMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  late Animation<double> _spread;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    // easeOutBack gives a satisfying overshoot on open;
    // easeIn on reverse pulls buttons cleanly back to X.
    _spread = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }


  @override
  Widget build(BuildContext context) {
    final onDelete = widget.onDelete;
    return GestureDetector(
      onTap: _dismiss,
      child: Stack(
        children: [
          FadeTransition(
            opacity: _opacity,
            // `scrim`, not `Colors.black` — the same swap the bubble panel's
            // overlay took. Byte-identical today, since neither scheme
            // declares a scrim and both fall to ColorScheme's own black.
            //
            // The two overlays still dim by different amounts, 0.6 here and
            // 0.28 in `bubble_panel.dart`, and that is left alone: this one
            // covers the whole screen to isolate a menu, the other blurs
            // behind a panel that is still part of its screen. Picking one
            // number for both is a design call, not a token swap.
            child: Container(
              color: Theme.of(context)
                  .colorScheme
                  .scrim
                  .withValues(alpha: 0.6),
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.10,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ScaleTransition(
                scale: _scale,
                child: FadeTransition(
                  opacity: _opacity,
                  // The width arithmetic in _RadialLayout models the 64dp
                  // circles and nothing else, but a button is as wide as its
                  // *label* when the label is wider — and German's
                  // "Zusammenfassung" is about 99dp at labelSmall, so the
                  // four-action row measures ~327dp rather than 292dp and ran
                  // off a 360dp screen with the Delete button clipped. Scaling
                  // the whole layout, rather than truncating the labels, keeps
                  // every word readable and keeps the internal geometry exact:
                  // the Row and the X below it shrink by the same factor, so
                  // the dy = 100 the animation depends on stays true. On
                  // English, and on any layout that already fits, scaleDown is
                  // a no-op.
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _RadialLayout(
                        spread: _spread,
                        onShare: () {
                          HapticFeedback.mediumImpact();
                          _dismiss().then((_) => widget.onShare());
                        },
                        onDismiss: _dismiss,
                        onBookmark: () {
                          HapticFeedback.mediumImpact();
                          _dismiss().then((_) => widget.onBookmark());
                        },
                        onDelete: onDelete == null
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                _dismiss().then((_) => onDelete());
                              },
                        isSaved: widget.article.isSaved,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RadialLayout extends StatelessWidget {
  final Animation<double> spread;
  final VoidCallback onShare;
  final VoidCallback onDismiss;
  final VoidCallback onBookmark;
  final VoidCallback? onDelete;
  final bool isSaved;

  const _RadialLayout({
    required this.spread,
    required this.onShare,
    required this.onDismiss,
    required this.onBookmark,
    required this.onDelete,
    required this.isSaved,
  });

  // Offsets each action button must travel to reach X's centre.
  //
  // Column layout (natural state):
  //   Row height ≈ 84 px  (64 circle + 6 gap + 14 label)
  //   SizedBox  = 16 px
  //   X circle  = 64 px   → X centre at 84+16+32 = 132 px from Column top
  //   Row circle centres  = 32 px from Column top
  //   → vertical distance = 132 − 32 = 100 px
  //
  // dy is 100 in both layouts below, and the 16 px SizedBox above X stays 16:
  // a fourth action makes the Row wider, never taller, so nothing in the
  // vertical arithmetic depends on how many buttons the Row holds.
  //
  // TWO ACTIONS (onDelete == null) — Bookmark, Share, 24 px gap:
  //   Row width = 2×64 + 24 = 152 px, centre = 76 px
  //   Button centres at 32 / 120
  //   → dx = +44 (Bookmark), −44 (Share)
  //
  // THREE ACTIONS (onDelete != null) — Bookmark, Share, Delete, 20 px gaps:
  //   Row width = 3×64 + 2×20 = 232 px, centre = 116 px (= Share centre)
  //   Button centres at 32 / 116 / 200
  //   → dx = +84 (Bookmark), 0 (Share), −84 (Delete)
  //
  // Summary used to sit in this row and now has its own button on the card,
  // so both layouts lost one circle. Delete simply took the slot Summary had
  // in the old three-button case, which is why these numbers are that case's
  // numbers unchanged — the row it produces is the one that was already
  // known to fit.
  //
  // At spread t=0 → buttons at X (apply full offset).
  // At spread t=1 → buttons at natural positions (offset = 0).
  // Translation to apply: offset × (1 − t).

  Widget _actionButton({
    required double t,
    required double dx,
    required double dy,
    required Widget child,
  }) {
    final inv = 1.0 - t;
    return Transform.translate(
      offset: Offset(dx * inv, dy * inv),
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasDelete = onDelete != null;
    // 20 for three, 24 for two. Not one shared constant: the numbers below are
    // derived from the gap, so a single value would silently move every button
    // off the centre it was computed for.
    final gap = hasDelete ? 20.0 : 24.0;
    // Left to right: Bookmark, Share, Delete. See the arithmetic above for
    // where these come from. Leftmost is positive — every button travels
    // *towards* the X, which sits at the row's centre — so a list runs from
    // positive to negative and never the mirror image of that.
    final dx = hasDelete
        ? const [84.0, 0.0, -84.0]
        : const [44.0, -44.0];

    return AnimatedBuilder(
      animation: spread,
      builder: (context, _) {
        final t = spread.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _actionButton(
                  t: t,
                  dx: dx[0],
                  dy: 100,
                  child: _RadialButton(
                    icon: isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    label: isSaved ? l10n.saved : l10n.bookmark,
                    onTap: onBookmark,
                    enabled: true,
                  ),
                ),
                SizedBox(width: gap),
                _actionButton(
                  t: t,
                  dx: dx[1],
                  dy: 100,
                  child: _RadialButton(
                    icon: Icons.share_rounded,
                    label: l10n.share,
                    onTap: onShare,
                    enabled: true,
                  ),
                ),
                if (hasDelete) ...[
                  SizedBox(width: gap),
                  _actionButton(
                    t: t,
                    dx: dx[2],
                    dy: 100,
                    child: _RadialButton(
                      icon: Icons.delete_outline_rounded,
                      label: l10n.alertsRemove,
                      onTap: onDelete,
                      enabled: true,
                      // Tinted like the close button rather than the accent:
                      // it is the one action here that destroys something.
                      tint: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // X — fixed anchor, always at natural position
            _RadialButton(
              icon: Icons.close_rounded,
              label: '',
              onTap: onDismiss,
              enabled: true,
              isClose: true,
            ),
          ],
        );
      },
    );
  }
}

class _RadialButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isClose;

  /// Overrides the accent this button is drawn in. Only Delete uses it.
  final Color? tint;

  const _RadialButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.enabled,
    this.isClose = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surfaceContainerHighest;

    // Close used to paint itself in `error`, which said "delete this forever"
    // in exactly the red used for "cancel this menu" — the two loudest things
    // on the ring were the one that destroys an article and the one that puts
    // the menu away. It is a neutral glyph on a neutral circle now. `tint`
    // still exists and Alerts' delete still passes `error` through it, so the
    // one genuinely destructive action keeps the colour to itself.
    final accent = tint ?? theme.colorScheme.primary;

    final Color bg;
    final Color iconColor;
    if (isClose) {
      bg = Colors.transparent;
      iconColor = theme.colorScheme.onSurfaceVariant;
    } else if (enabled) {
      bg = accent.withValues(alpha: 0.15);
      iconColor = accent;
    } else {
      // 6.5: disabled and inert are one role, and the 8% wash goes away
      // rather than changing value. A faint disc behind a faint glyph was
      // two ways of saying the same thing, and the fainter it got the more
      // it read as a rendering artefact.
      bg = Colors.transparent;
      iconColor = theme.flashColors.inert;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: enabled ? onTap : null,
          child: Material(
            color: surface,
            shape: const CircleBorder(),
            elevation: 4,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: bg,
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          // The same surface the circle above sits on, for the same reason.
          // The caption used to be bare Text over the menu's scrim, which
          // means over whatever article headline happened to be behind it —
          // and since the labels are the only thing naming the two glyphs,
          // that made the menu unreadable at exactly the moment it had to be
          // read. `surfaceContainerHighest` and elevation 4 are taken from the
          // circle rather than chosen, so the two read as one object and both
          // stay correct in Quiet Ink light, Quiet Ink dark and Newspaper.
          Material(
            color: surface,
            elevation: 4,
            borderRadius: BorderRadius.circular(9),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  // The disabled half is `inert` per 6.5. The enabled half was
                  // ink at 80%, which is not a level the scale has; it is a
                  // caption under an icon button, so it takes onSurfaceVariant.
                  // Inferred — 6.5 ruled on the disabled half only.
                  color: enabled
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.flashColors.inert,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Show the radial menu as an overlay entry.
OverlayEntry showRadialMenu({
  required BuildContext context,
  required VoidCallback onShare,
  required VoidCallback onBookmark,
  required Article article,
  VoidCallback? onDelete,
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => RadialMenu(
      onShare: onShare,
      onBookmark: onBookmark,
      onDismiss: () => entry.remove(),
      article: article,
      onDelete: onDelete,
    ),
  );
  Overlay.of(context).insert(entry);
  return entry;
}
