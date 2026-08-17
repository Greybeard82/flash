import 'package:flutter/material.dart';

class UnreadBadge extends StatelessWidget {
  final int count;
  final bool small;

  const UnreadBadge({super.key, required this.count, this.small = false});

  /// The widest this badge ever renders (the "999+" overflow label), so
  /// callers that show/hide or update it in place — e.g. a tab bar where
  /// every tab's count updates live — can reserve a fixed-width slot instead
  /// of letting the badge's intrinsic width shift sibling layout.
  ///
  /// Measured with the same fixed style and no text-scaling as the Text
  /// widget in build() (see its `textScaler: TextScaler.noScaling`) — the
  /// two must always agree, or the box can end up narrower than the text
  /// it's sized for and wrap the digits onto a second line. A small buffer
  /// is added on top as insurance against any remaining sub-pixel drift
  /// between an out-of-tree TextPainter measurement and actual layout.
  static double maxWidth({bool small = false}) {
    final fontSize = small ? 10.0 : 11.0;
    final horizontalPadding = small ? 8.0 : 12.0; // 4+4 or 6+6, see build()
    const safetyBuffer = 2.0;
    final painter = TextPainter(
      text: TextSpan(
        text: '999+',
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    return painter.width + horizontalPadding + safetyBuffer;
  }

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final color = Theme.of(context).colorScheme.primary;
    final label = count > 999 ? '999+' : count.toString();
    final fontSize = small ? 10.0 : 11.0;
    final padding = small
        ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
        : const EdgeInsets.symmetric(horizontal: 6, vertical: 2);

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        // Pinned to the device's base scale, matching the unscaled
        // TextPainter used by maxWidth() below — a fixed-width box sized
        // against unscaled metrics but rendering text that DOES follow the
        // system font-size setting is exactly what wraps digits onto a
        // second line (#…): the two must always agree.
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimary,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
