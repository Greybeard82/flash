import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';

class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final scheme = theme.colorScheme;

    // Geometry below is untouched; only the greys moved. The old pair were
    // fixed hexes from the palette era — #1E2E3E and #2A3E52 are navy, which
    // on Quiet Ink's near-neutral dark surface read as a blue cast on every
    // card during boot.
    //
    // The base is the placeholder role, the same fill a missing thumbnail
    // uses, so a skeleton and the thing it stands in for are the same colour.
    // The sweep moves one step toward the page's own extreme — paper in
    // light, ink in dark — because a highlight has to be brighter than the
    // block it crosses, and which direction that is depends on the theme.
    final baseColor = theme.flashColors.placeholder;
    final highlightColor = Color.lerp(
      baseColor,
      isDark ? scheme.onSurface : scheme.surface,
      isDark ? 0.10 : 0.60,
    )!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Source line
                  Row(
                    children: [
                      _box(16, 16, radius: 8),
                      const SizedBox(width: 6),
                      _box(80, 12),
                      const SizedBox(width: 8),
                      _box(40, 12),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Title
                  _box(double.infinity, 14),
                  const SizedBox(height: 4),
                  _box(double.infinity, 14),
                  const SizedBox(height: 4),
                  _box(180, 14),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Thumbnail placeholder
            _box(72, 72, radius: 8),
          ],
        ),
      ),
    );
  }

  Widget _box(double width, double height, {double radius = 4}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Whatever this is, Shimmer's shader paints over it. Kept opaque and
        // neutral so the boxes are visible if the package is ever swapped for
        // something that does not.
        color: const Color(0xFF9E9E9E),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
