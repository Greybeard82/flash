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

  /// Where the panel sits: pinned below the status bar and inset from the side
  /// edges. Height is deliberately *not* fixed — the panel hugs its content,
  /// with [_maxHeight] only as an upper bound before the content scrolls, so a
  /// short panel doesn't leave dead space under its last control.
  ({double left, double top, double width}) _panelBox(BuildContext context) {
    final media = MediaQuery.of(context);
    const horizontalInset = 16.0;
    return (
      left: horizontalInset,
      top: media.padding.top + 12,
      width: media.size.width - horizontalInset * 2,
    );
  }

  double _maxHeight(BuildContext context) =>
      MediaQuery.of(context).size.height * 0.7;

  /// Scale origin, so the growth appears to come out of the button rather than
  /// the panel's centre.
  ///
  /// Horizontal is exact — the panel's width and position are known. Vertical
  /// is pinned to the top edge rather than computed, because the panel's
  /// height now depends on its content and isn't known when this is built.
  /// The buttons that open these panels sit at the top of the screen, so the
  /// top edge is where the growth should originate anyway.
  Alignment _originWithin(double left, double width) {
    if (widget.anchorRect == Rect.zero || width <= 0) {
      return Alignment.topRight;
    }
    final centreX = left + width / 2;
    final dx = (widget.anchorRect.center.dx - centreX) / (width / 2);
    return Alignment(dx.clamp(-1.0, 1.0), -1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final box = _panelBox(context);

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
            Positioned(
              left: box.left,
              top: box.top,
              width: box.width,
              child: FadeTransition(
                opacity: _opacity,
                child: ScaleTransition(
                  scale: _scale,
                  alignment: _originWithin(box.left, box.width),
                  // Taps inside must not fall through to the scrim.
                  child: GestureDetector(
                    onTap: () {},
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: _maxHeight(context)),
                      child: Material(
                        color: theme.colorScheme.surface,
                        elevation: 6,
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        // SingleChildScrollView sizes to its child when the
                        // incoming constraint is loose, so the sheet is exactly
                        // as tall as its controls and only scrolls past the cap.
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
