import 'package:intl/intl.dart';

class MyloFormatters {
  // ─── Dates ───────────────────────────────────────────────────────────
  static String date(DateTime dt) =>
      DateFormat('dd MMM yyyy', 'id').format(dt);

  static String dateTime(DateTime dt) =>
      DateFormat('dd MMM yyyy, HH:mm', 'id').format(dt);

  static String time(DateTime dt) => DateFormat('HH:mm').format(dt);

  static String shortDate(DateTime dt) =>
      DateFormat('dd/MM/yy').format(dt);

  static String chatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat('HH:mm').format(dt);
    if (diff.inDays == 1) return 'Kemarin';
    if (diff.inDays < 7) return DateFormat('EEEE', 'id').format(dt);
    return DateFormat('dd/MM/yy').format(dt);
  }

  // ─── Numbers ─────────────────────────────────────────────────────────
  static String currency(num amount, {String symbol = 'Rp'}) {
    final fmt = NumberFormat.currency(
        locale: 'id_ID', symbol: symbol, decimalDigits: 0);
    return fmt.format(amount);
  }

  static String compact(num count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}jt';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}rb';
    }
    return '$count';
  }

  static String fileSize(num bytes) {
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  // ─── Strings ─────────────────────────────────────────────────────────
  static String initials(String name, [int max = 2]) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts
        .take(max)
        .map((p) => p.isEmpty ? '' : p[0].toUpperCase())
        .join();
  }

  static String truncate(String text, int limit) {
    if (text.length <= limit) return text;
    return '${text.substring(0, limit)}...';
  }

  static String phone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0') && digits.length >= 10) {
      return '+62 ${digits.substring(1, 4)}-${digits.substring(4, 8)}-${digits.substring(8)}';
    }
    return raw;
  }
}
