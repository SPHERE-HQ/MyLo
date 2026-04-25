class MyloFormatters {
  static const _monthsId = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  static const _daysId = [
    '', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'
  ];

  // ─── Dates ───────────────────────────────────────────────────────────
  static String date(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')} ${_monthsId[dt.month]} ${dt.year}';

  static String dateTime(DateTime dt) =>
      '${date(dt)}, ${time(dt)}';

  static String time(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  static String shortDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year.toString().substring(2)}';

  static String chatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return time(dt);
    if (diff.inDays == 1) return 'Kemarin';
    if (diff.inDays < 7) return _daysId[dt.weekday];
    return shortDate(dt);
  }

  // ─── Numbers ─────────────────────────────────────────────────────────
  static String currency(num amount, {String symbol = 'Rp'}) {
    final str = amount.toInt().toString();
    final buf = StringBuffer(symbol);
    buf.write('\u00A0');
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(str[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
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
      final rest = digits.substring(1);
      if (rest.length >= 7) {
        return '+62 ${rest.substring(0, 3)}-${rest.substring(3, 7)}-${rest.substring(7)}';
      }
    }
    return raw;
  }
}
