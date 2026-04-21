import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../app/theme.dart';

class MLoadingSkeleton extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const MLoadingSkeleton({super.key, this.width = double.infinity, required this.height, this.borderRadius = 8});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? MyloColors.surfaceSecondaryDark : MyloColors.surfaceSecondary,
      highlightColor: isDark ? MyloColors.surfaceDark : MyloColors.surface,
      child: Container(
        width: width, height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(borderRadius)),
      ),
    );
  }
}
