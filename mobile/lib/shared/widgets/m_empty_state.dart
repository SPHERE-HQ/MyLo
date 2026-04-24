import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'm_button.dart';

class MEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MyloSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: MyloColors.primary.withOpacity(.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: MyloColors.primary),
            ),
            const SizedBox(height: MyloSpacing.lg),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: MyloSpacing.sm),
              Text(subtitle!, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14,
                      color: isDark ? MyloColors.textSecondaryDark : MyloColors.textSecondary)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: MyloSpacing.xl),
              MButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}
