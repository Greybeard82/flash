import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RadialMenu extends StatefulWidget {
  final VoidCallback onShare;
  final VoidCallback onDismiss;

  const RadialMenu({
    super.key,
    required this.onShare,
    required this.onDismiss,
  });

  @override
  State<RadialMenu> createState() => _RadialMenuState();
}

class _RadialMenuState extends State<RadialMenu>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
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
    return GestureDetector(
      onTap: _dismiss,
      child: Stack(
        children: [
          // Dim background
          FadeTransition(
            opacity: _opacity,
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
          ),
          // Radial menu centred on screen
          Center(
            child: ScaleTransition(
              scale: _scale,
              child: FadeTransition(
                opacity: _opacity,
                child: _RadialLayout(
                  onShare: () {
                    HapticFeedback.mediumImpact();
                    _dismiss().then((_) => widget.onShare());
                  },
                  onDismiss: _dismiss,
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
  final VoidCallback onShare;
  final VoidCallback onDismiss;

  const _RadialLayout({required this.onShare, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    const double buttonSize = 64;
    const double spacing = 80;

    return SizedBox(
      width: spacing * 2 + buttonSize,
      height: spacing + buttonSize,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // Share — top-left
          Positioned(
            left: 0,
            top: 0,
            child: _RadialButton(
              icon: Icons.share_rounded,
              label: 'Share',
              onTap: onShare,
              enabled: true,
            ),
          ),
          // Summary — top-right (disabled in Phase 1)
          Positioned(
            right: 0,
            top: 0,
            child: _RadialButton(
              icon: Icons.auto_awesome_rounded,
              label: 'Summary',
              onTap: null,
              enabled: false,
            ),
          ),
          // Dismiss — centre bottom
          Positioned(
            bottom: 0,
            left: spacing - buttonSize / 2,
            child: _RadialButton(
              icon: Icons.close_rounded,
              label: '',
              onTap: onDismiss,
              enabled: true,
              isClose: true,
            ),
          ),
        ],
      ),
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

/// Show the radial menu as an overlay entry
OverlayEntry showRadialMenu({
  required BuildContext context,
  required VoidCallback onShare,
}) {
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => RadialMenu(
      onShare: onShare,
      onDismiss: () => entry.remove(),
    ),
  );
  Overlay.of(context).insert(entry);
  return entry;
}
