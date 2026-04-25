import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/article.dart';
import '../screens/article_summary_sheet.dart';

class RadialMenu extends StatefulWidget {
  final VoidCallback onShare;
  final VoidCallback onDismiss;
  final VoidCallback onBookmark;
  final Article article;

  const RadialMenu({
    super.key,
    required this.onShare,
    required this.onDismiss,
    required this.onBookmark,
    required this.article,
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
    _scale   = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
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

  void _openSummary() {
    _dismiss().then((_) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => ArticleSummarySheet(article: widget.article),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismiss,
      child: Stack(
        children: [
          FadeTransition(
            opacity: _opacity,
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
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
                  child: _RadialLayout(
                    spread: _spread,
                    onShare: () {
                      HapticFeedback.mediumImpact();
                      _dismiss().then((_) => widget.onShare());
                    },
                    onDismiss: _dismiss,
                    onSummary: _openSummary,
                    onBookmark: () {
                      HapticFeedback.mediumImpact();
                      _dismiss().then((_) => widget.onBookmark());
                    },
                    isSaved: widget.article.isSaved,
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
  final VoidCallback onSummary;
  final VoidCallback onBookmark;
  final bool isSaved;

  const _RadialLayout({
    required this.spread,
    required this.onShare,
    required this.onDismiss,
    required this.onSummary,
    required this.onBookmark,
    required this.isSaved,
  });

  // Offsets each action button must travel to reach X's centre.
  //
  // Column layout (natural state):
  //   Row height ≈ 84 px  (64 circle + 6 gap + 14 label)
  //   SizedBox  = 16 px
  //   X circle  = 64 px   → X centre at 84+16+32 = 132 px from Column top
  //   Row circle centres  = 32 px from Column top
  //   → vertical distance  = 132 − 32 = 100 px
  //
  //   Row width = 3×64 + 2×20 = 232 px, centre = 116 px (= Share centre)
  //   Favourite centre = 32 px   → 84 px left  of Share/X
  //   Summary  centre = 200 px   → 84 px right of Share/X
  //   → horizontal distances: ±84 px
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
                // Bookmark — X is 84 px right and 100 px below
                _actionButton(
                  t: t,
                  dx: 84,
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
                const SizedBox(width: 20),
                // Share — X is 100 px directly below
                _actionButton(
                  t: t,
                  dx: 0,
                  dy: 100,
                  child: _RadialButton(
                    icon: Icons.share_rounded,
                    label: l10n.share,
                    onTap: onShare,
                    enabled: true,
                  ),
                ),
                const SizedBox(width: 20),
                // Summary — X is 84 px left and 100 px below
                _actionButton(
                  t: t,
                  dx: -84,
                  dy: 100,
                  child: _RadialButton(
                    icon: Icons.auto_awesome_rounded,
                    label: l10n.summary,
                    onTap: onSummary,
                    enabled: true,
                  ),
                ),
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

  const _RadialButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.enabled,
    this.isClose = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final surface = theme.colorScheme.surfaceContainerHighest;

    final bg = isClose
        ? theme.colorScheme.error.withValues(alpha: 0.15)
        : enabled
            ? accent.withValues(alpha: 0.15)
            : theme.colorScheme.onSurface.withValues(alpha: 0.08);

    final iconColor = isClose
        ? theme.colorScheme.error
        : enabled
            ? accent
            : theme.colorScheme.onSurface.withValues(alpha: 0.3);

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
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: enabled
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.8)
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
              fontWeight: FontWeight.w600,
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
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => RadialMenu(
      onShare: onShare,
      onBookmark: onBookmark,
      onDismiss: () => entry.remove(),
      article: article,
    ),
  );
  Overlay.of(context).insert(entry);
  return entry;
}
