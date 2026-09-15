import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// **The one number David tunes.**
///
/// The corner radius as a proportion of the track's height, because neither a
/// screenshot nor a mock reading gives an absolute radius anyone can trust.
/// 0.5 is a stadium — the shape Material gives you and the one this widget
/// exists to avoid. 0.0 is a hard rectangle. 0.32 is the shipped first guess:
/// visibly square-shouldered, still softened.
///
/// Change this one constant and every switch in the app follows, including the
/// thumb, which takes the same proportion of its own height so the two curves
/// stay in the same family at any value.
const double kFlashSwitchCornerRatio = 0.32;

/// Track geometry. The visible control; see [kFlashSwitchMinTarget] for what
/// is actually tappable.
const double kFlashSwitchTrackWidth = 44;
const double kFlashSwitchTrackHeight = 26;

/// Inset of the thumb inside the track, per side.
const double kFlashSwitchThumbInset = 3;

/// **48dp, and not negotiable here.**
///
/// This app has gone under 48 exactly twice, each time with explicit sign-off
/// and each time because the shape itself was the design. A settings toggle is
/// not one of those: the track is 26dp tall because that is what the mock
/// wants, and the tappable box stays 48 regardless.
const double kFlashSwitchMinTarget = 48;

/// Matches the chip selection in `folder_tab_bar.dart` and the banner slide in
/// `notification_banner.dart`, rather than inventing a tempo. Both are the
/// same thing this is: a small control changing state under the finger.
const Duration kFlashSwitchDuration = Duration(milliseconds: 200);

/// A switch with square shoulders.
///
/// **Why this exists at all.** `SwitchThemeData` in Flutter 3.41.6 exposes ten
/// properties — colours, outline colour and width, thumb icon, padding, tap
/// target size, cursor, overlay, splash radius — and **no shape**. `Switch`
/// itself takes no `ShapeBorder`. The track is painted by `_SwitchPainter` as
/// `RRect.fromRectAndRadius(trackRect, Radius.circular(trackHeight / 2))`: a
/// stadium, derived from the height, unreachable from a theme. Verified
/// against the pinned SDK rather than assumed.
///
/// **What this is not.** It is not a picture of a switch. A custom toggle that
/// looks right and announces itself to a screen reader as a button, or has a
/// 26dp touch target, or only responds to taps, is worse than the stock one it
/// replaced. All three are handled below and all three are asserted.
class FlashSwitch extends StatefulWidget {
  const FlashSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;

  /// Null disables the control, matching `Switch`'s own convention so call
  /// sites read the same way.
  final ValueChanged<bool>? onChanged;

  @override
  State<FlashSwitch> createState() => _FlashSwitchState();
}

class _FlashSwitchState extends State<FlashSwitch> {
  /// How far this drag has travelled, so the decision is made on DISTANCE
  /// rather than on release velocity.
  ///
  /// Velocity was the first attempt and it is the wrong model twice over: a
  /// slow deliberate drag has almost none, and it made the behaviour depend
  /// on how fast someone moves rather than on what they did. Distance is also
  /// what a real switch does — you push the thumb across.
  double _dragDelta = 0;

  bool get _enabled => widget.onChanged != null;

  /// A quarter of the track. Far enough that a stray horizontal wobble during
  /// a vertical list scroll does not flip a setting, short enough that a
  /// deliberate push always lands.
  static const double _dragThreshold = kFlashSwitchTrackWidth / 4;

  void _toggleTo(bool next) {
    if (next != widget.value) widget.onChanged!(next);
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final scheme = Theme.of(context).colorScheme;
    final ink = Theme.of(context).flashColors;

    // Every pair here is measured against WCAG 1.4.11's 3:1 for non-text
    // graphical objects, in all three themes, in both states — see
    // flash_switch_test.dart, which asserts the numbers rather than trusting
    // this comment.
    //
    // The OFF track is `onSurfaceMuted` rather than a pale grey because the
    // track has to clear 3:1 against the PAGE, not just against its own thumb.
    // A Material-style pale track relies on its outline to be visible at all
    // and measures about 1.1:1 on white.
    final Color track = !_enabled
        ? ink.inert
        : value
            ? scheme.primary
            : ink.onSurfaceMuted;
    final Color thumb = !_enabled
        ? scheme.surface
        : value
            ? scheme.onPrimary
            : scheme.surface;

    const double thumbSize =
        kFlashSwitchTrackHeight - kFlashSwitchThumbInset * 2;

    final Widget visual = SizedBox(
      width: kFlashSwitchTrackWidth,
      height: kFlashSwitchTrackHeight,
      child: AnimatedContainer(
        duration: kFlashSwitchDuration,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: track,
          borderRadius: BorderRadius.circular(
              kFlashSwitchTrackHeight * kFlashSwitchCornerRatio),
        ),
        child: AnimatedAlign(
          duration: kFlashSwitchDuration,
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: kFlashSwitchThumbInset),
            child: Container(
              width: thumbSize,
              height: thumbSize,
              decoration: BoxDecoration(
                color: thumb,
                // The same proportion as the track, so the two curves stay in
                // one family whatever kFlashSwitchCornerRatio becomes.
                borderRadius:
                    BorderRadius.circular(thumbSize * kFlashSwitchCornerRatio),
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      // `toggled` is what makes a screen reader say "switch, on" rather than
      // "button". Without it this is an image with a tap handler, which is the
      // single most common way a custom toggle fails the people who most need
      // it to work.
      toggled: value,
      enabled: _enabled,
      onTap: _enabled ? () => widget.onChanged!(!value) : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          // Opaque so the whole 48dp box takes the hit, not just the pixels
          // the track happens to cover.
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? () => widget.onChanged!(!value) : null,
          // People swipe switches. A tap-only toggle reads as broken to
          // anyone who has ever used one, and costs two callbacks to support.
          onHorizontalDragStart: _enabled ? (_) => _dragDelta = 0 : null,
          onHorizontalDragUpdate:
              _enabled ? (d) => _dragDelta += d.delta.dx : null,
          onHorizontalDragEnd: _enabled
              ? (_) {
                  if (_dragDelta > _dragThreshold) {
                    _toggleTo(true);
                  } else if (_dragDelta < -_dragThreshold) {
                    _toggleTo(false);
                  }
                  _dragDelta = 0;
                }
              : null,
          child: SizedBox(
            height: kFlashSwitchMinTarget,
            width: kFlashSwitchMinTarget,
            child: Center(child: visual),
          ),
        ),
      ),
    );
  }
}

/// [SwitchListTile]'s shape, with [FlashSwitch] in place of the stock switch.
///
/// A drop-in for the eight call sites, so replacing them is a widget rename
/// rather than a re-layout of Settings and both bubbles. Row-tap toggles,
/// which is what `SwitchListTile` does and what people expect from a settings
/// row.
class FlashSwitchListTile extends StatelessWidget {
  const FlashSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.contentPadding,
    this.dense,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;

  @override
  Widget build(BuildContext context) {
    // One Semantics node for the row, not two. Without the ExcludeSemantics
    // the reader announces the tile and then the switch, and the user hears
    // the label twice.
    return MergeSemantics(
      child: ListTile(
        contentPadding: contentPadding,
        dense: dense,
        title: title,
        subtitle: subtitle,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        trailing: FlashSwitch(value: value, onChanged: onChanged),
      ),
    );
  }
}
