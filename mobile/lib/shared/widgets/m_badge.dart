import 'package:flutter/material.dart';
import '../../app/theme.dart';

enum MBadgeVariant { primary, success, warning, danger, neutral }

class MBadge extends StatelessWidget {
  final String label;
  final MBadgeVariant variant;
  final IconData? icon;

  const MBadge({super.key, required this.label, this.variant = MBadgeVariant.primary, this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = switch (variant) {
      MBadgeVariant.primary => (MyloColors.primary.withOpacity(.15), MyloColors.primary),
      MBadgeVariant.success => (MyloColors.accent.withOpacity(.15), MyloColors.accent),
      MBadgeVariant.warning => (const Color(0xFFFFE7B3), const Color(0xFFB76E00)),
      MBadgeVariant.danger => (MyloColors.danger.withOpacity(.15), MyloColors.danger),
      MBadgeVariant.neutral => (Colors.grey.withOpacity(.15), Colors.grey.shade700),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: colors.$1, borderRadius: BorderRadius.circular(MyloRadius.full)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: colors.$2), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.$2)),
        ],
      ),
    );
  }
}
