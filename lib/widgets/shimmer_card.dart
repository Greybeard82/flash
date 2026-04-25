import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF1E2E3E) : const Color(0xFFE0E0E0);
    final highlightColor =
        isDark ? const Color(0xFF2A3E52) : const Color(0xFFF5F5F5);

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
        color: Colors.grey,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
