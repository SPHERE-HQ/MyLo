import 'package:flutter/material.dart';
import '../../app/theme.dart';

class MCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final Color? color;

  const MCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(MyloSpacing.lg),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = color ?? (isDark ? MyloColors.surfaceDark : MyloColors.surface);
    return Padding(
      padding: margin,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(MyloRadius.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(MyloRadius.lg),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
