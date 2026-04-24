import 'package:flutter/material.dart';
import '../../app/theme.dart';

class MBottomSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    bool isScrollControlled = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: isDark ? MyloColors.surfaceDark : MyloColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MyloRadius.xl)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 8),
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: MyloSpacing.lg, vertical: MyloSpacing.sm),
                    child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                Flexible(child: child),
              ],
            ),
          ),
        );
      },
    );
  }
}
