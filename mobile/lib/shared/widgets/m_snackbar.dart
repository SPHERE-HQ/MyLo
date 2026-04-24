import 'package:flutter/material.dart';
import '../../app/theme.dart';

enum MSnackbarType { info, success, warning, error }

class MSnackbar {
  static void show(BuildContext context, String message, {MSnackbarType type = MSnackbarType.info}) {
    final color = switch (type) {
      MSnackbarType.success => MyloColors.accent,
      MSnackbarType.warning => const Color(0xFFB76E00),
      MSnackbarType.error => MyloColors.danger,
      _ => MyloColors.primary,
    };
    final icon = switch (type) {
      MSnackbarType.success => Icons.check_circle,
      MSnackbarType.warning => Icons.warning_rounded,
      MSnackbarType.error => Icons.error_rounded,
      _ => Icons.info_rounded,
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyloRadius.md)),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  static void info(BuildContext c, String m) => show(c, m, type: MSnackbarType.info);
  static void success(BuildContext c, String m) => show(c, m, type: MSnackbarType.success);
  static void warning(BuildContext c, String m) => show(c, m, type: MSnackbarType.warning);
  static void error(BuildContext c, String m) => show(c, m, type: MSnackbarType.error);
}
