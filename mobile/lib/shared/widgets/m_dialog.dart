import 'package:flutter/material.dart';
import '../../app/theme.dart';
import 'm_button.dart';

class MDialog {
  static Future<bool?> confirm({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Lanjut',
    String cancelText = 'Batal',
    bool destructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyloRadius.xl)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          MButton(
            label: cancelText,
            variant: MButtonVariant.ghost,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          MButton(
            label: confirmText,
            variant: destructive ? MButtonVariant.danger : MButtonVariant.primary,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  static Future<void> info({
    required BuildContext context,
    required String title,
    required String message,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(MyloRadius.xl)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }
}
