import 'package:flutter/material.dart';

import 'scroll_fade.dart';

/// One button in a [FabCluster].
class FabAction {
  /// Must be unique across every FAB alive at once, or Hero animations
  /// between routes throw.
  final String heroTag;

  /// A [Widget] rather than an [IconData], because the feed's refresh button
  /// swaps a spinner in while a fetch is in flight.
  final Widget icon;

  final String tooltip;

  /// Null disables the button, as it does on [FloatingActionButton].
  final VoidCallback? onPressed;

  /// For tests and for the onboarding spotlight, which anchors on one of these.
  final Key? buttonKey;

  const FabAction({
    required this.heroTag,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
  });
}

/// The stack of mini floating actions at the bottom-right of a list screen.
///
/// Two screens built this by hand before it existed — the feed with three
/// buttons, Alerts with two — and both had the same `ScrollFade` wrapper and
/// the same 8dp `SizedBox` repeated between every pair. That duplication is
/// the reason the cluster is a component now: the geometry below is stated
/// once rather than being retyped correctly twice and incorrectly the third
/// time.
///
/// **Nothing here styles the buttons.** Mini FABs come out of Material 3 at
/// 40x40 painted, radius 12, on `primaryContainer` — which is exactly what
/// the mock asks for, so this widget passes `mini: true` and lets the theme
/// answer. `fab_cluster_test.dart` pins those values anyway, because "the
/// framework happens to agree with us" is a thing that stops being true on
/// an upgrade, and silently.
///
/// The painted button is 40 but its tap target is 48: Material pads a mini FAB
/// out to the minimum. That is deliberate and worth keeping — a 40dp target
/// would be under spec, and unlike the category chips there is no row of four
/// competing for the width, so there is nothing to buy by shrinking it.
class FabCluster extends StatelessWidget {
  final ScrollFadeController controller;
  final List<FabAction> actions;

  /// Between buttons.
  static const double gap = 8;

  const FabCluster({
    super.key,
    required this.controller,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) children.add(const SizedBox(height: gap));
      final action = actions[i];
      children.add(
        ScrollFade(
          controller: controller,
          child: FloatingActionButton(
            key: action.buttonKey,
            heroTag: action.heroTag,
            onPressed: action.onPressed,
            tooltip: action.tooltip,
            mini: true,
            child: action.icon,
          ),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}
