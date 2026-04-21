import 'package:flutter/material.dart';
import '../../app/theme.dart';

enum MButtonVariant { primary, secondary, ghost, danger }
enum MButtonSize { large, medium, small }

class MButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final MButtonVariant variant;
  final MButtonSize size;
  final bool isLoading;
  final Widget? icon;

  const MButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = MButtonVariant.primary,
    this.size = MButtonSize.medium,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final height = size == MButtonSize.large ? 52.0 : size == MButtonSize.medium ? 44.0 : 36.0;
    final bgColor = variant == MButtonVariant.primary
        ? MyloColors.primary
        : variant == MButtonVariant.danger
            ? MyloColors.danger
            : Colors.transparent;
    final fgColor = variant == MButtonVariant.secondary
        ? MyloColors.primary
        : variant == MButtonVariant.ghost
            ? MyloColors.primary
            : Colors.white;
    final border = variant == MButtonVariant.secondary
        ? BorderSide(color: MyloColors.primary)
        : BorderSide.none;

    return SizedBox(
      height: height,
      width: size == MButtonSize.large ? double.infinity : null,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          side: border,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyloRadius.xl)),
          padding: const EdgeInsets.symmetric(horizontal: MyloSpacing.xl),
        ),
        child: isLoading
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: fgColor))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[icon!, const SizedBox(width: MyloSpacing.sm)],
                  Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: fgColor)),
                ],
              ),
      ),
    );
  }
}
