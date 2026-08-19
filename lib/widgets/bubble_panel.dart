import 'dart:ui';

import 'package:flutter/material.dart';

/// Shows [child] as a panel that grows out of the button at [anchorKey] and
/// shrinks back into it on dismiss.
///
/// Same lifecycle as `showRadialMenu` in `radial_menu.dart`: an [OverlayEntry]
/// rather than a Navigator route, an [AnimationController] driving scale and
/// opacity, tap-outside to dismiss, and the entry removed once the reverse
/// animation finishes. The curves and 220ms duration are lifted from there too,
/// so the two overlays feel like the same thing. The difference is the backdrop
/// — blurred here rather than only dimmed — and that this one is anchored to
/// the top of the screen and sized as a panel.
///
/// Returns the [OverlayEntry] so a caller can force-remove it; normal dismissal
/// is handled internally.
OverlayEntry showBubblePanel({
  required BuildContext context,
  required GlobalKey anchorKey,
  required Widget child,
}) {
  final anchorRect = _globalRectOf(anchorKey);

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _BubblePanel(
      anchorRect: anchorRect,
      onDismissed: () {
        if (entry.mounted) entry.remove();
      },
      child: child,
    ),
  );
  Overlay.of(context).insert(entry);
  return entry;
}

/// The button's rect in global coordinates, used as the origin the panel grows
/// out of. Falls back to the top-right corner if the button has somehow gone
/// away between tap and insert.
Rect _globalRectOf(GlobalKey key) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Rect.zero;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _BubblePanel extends StatefulWidget {
  final Rect anchorRect;
  final VoidCallback onDismissed;
  final Widget child;

  const _BubblePanel({
    required this.anchorRect,
    required this.onDismissed,
    required this.child,
  });

  @override
  State<_BubblePanel> createState() => _BubblePanelState();
}

class _BubblePanelState extends State<_BubblePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;
  late final Animation<double> _backdrop;

  /// Guards against the two dismiss paths — the scrim and the panel's own
  /// close affordance — both landing while the reverse is already running.
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    // Same curve set as radial_menu.dart: a little overshoot on open, a clean
    // pull back on reverse.
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeIn,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _backdrop = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    await _controller.reverse();
    widget.onDismissed();
  }

  /// Where the panel sits: the top section of the screen, inset from the edges
  /// and below the status bar. "Maximised" is relative to the button it came
  /// from, not the whole screen.
  Rect _panelRect(BuildContext context) {
    final media = MediaQuery.of(context);
    const horizontalInset = 16.0;
    final top = media.padding.top + 12;
    final width = media.size.width - horizontalInset * 2;
    final maxHeight = media.size.height * 0.52;
    return Rect.fromLTWH(horizontalInset, top, width, maxHeight);
  }

  /// Scale origin, expressed as an [Alignment] inside the panel, so the growth
  /// appears to come out of the button rather than the panel's centre.
  Alignment _originWithin(Rect panel) {
    if (widget.anchorRect == Rect.zero || panel.isEmpty) {
      return Alignment.topRight;
    }
    final dx = (widget.anchorRect.center.dx - panel.center.dx) /
        (panel.width / 2);
    final dy = (widget.anchorRect.center.dy - panel.center.dy) /
        (panel.height / 2);
    return Alignment(dx.clamp(-1.5, 1.5), dy.clamp(-1.5, 1.5));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final panel = _panelRect(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _backdrop.value;
        return Stack(
          children: [
            // Blurred, lightly dimmed backdrop. The radial menu dims only;
            // this defocuses as well, so the panel reads as the foreground.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 6 * t, sigmaY: 6 * t),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.28 * t),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: panel,
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  alignment: _originWithin(panel),
                  // Taps inside must not fall through to the scrim.
                  child: GestureDetector(
                    onTap: () {},
                    child: Material(
                      color: theme.colorScheme.surface,
                      elevation: 6,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: SafeArea(
                        top: false,
                        bottom: false,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                          child: BubblePanelScope(
                            dismiss: _dismiss,
                            child: widget.child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Lets panel content close the bubble it is inside without knowing how it was
/// presented.
class BubblePanelScope extends InheritedWidget {
  final Future<void> Function() dismiss;

  const BubblePanelScope({
    super.key,
    required this.dismiss,
    required super.child,
  });

  static BubblePanelScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BubblePanelScope>();

  @override
  bool updateShouldNotify(BubblePanelScope oldWidget) => false;
}

/// Shared heading for a bubble's content, so both panels look alike.
class BubblePanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const BubblePanelHeader({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => BubblePanelScope.maybeOf(context)?.dismiss(),
          ),
        ],
      ),
    );
  }
}
