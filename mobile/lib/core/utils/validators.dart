class MyloValidators {
  static String? required(String? value, [String? label]) {
    if (value == null || value.trim().isEmpty) {
      return '${label ?? 'Kolom'} tidak boleh kosong';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email tidak boleh kosong';
    final re = RegExp(r'^[\w\.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
    if (!re.hasMatch(value.trim())) return 'Format email tidak valid';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Kata sandi tidak boleh kosong';
    if (value.length < 8) return 'Kata sandi minimal 8 karakter';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value == null || value.isEmpty) return 'Konfirmasi kata sandi wajib diisi';
    if (value != original) return 'Kata sandi tidak sama';
    return null;
  }

  static String? username(String? value) {
    if (value == null || value.trim().isEmpty) return 'Username tidak boleh kosong';
    if (value.length < 3) return 'Username minimal 3 karakter';
    if (value.length > 30) return 'Username maksimal 30 karakter';
    final re = RegExp(r'^[a-zA-Z0-9_\.]+$');
    if (!re.hasMatch(value)) return 'Hanya huruf, angka, titik, dan underscore';
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 9 || digits.length > 15) return 'Nomor HP tidak valid';
    return null;
  }

  static String? minLength(String? value, int min, [String? label]) {
    if (value == null || value.trim().length < min) {
      return '${label ?? 'Teks'} minimal $min karakter';
    }
    return null;
  }

  static String? maxLength(String? value, int max, [String? label]) {
    if (value != null && value.length > max) {
      return '${label ?? 'Teks'} maksimal $max karakter';
    }
    return null;
  }

  static String? otp(String? value) {
    if (value == null || value.trim().isEmpty) return 'Kode OTP wajib diisi';
    if (value.trim().length != 6) return 'Kode OTP harus 6 digit';
    if (!RegExp(r'^\d{6}$').hasMatch(value.trim())) return 'Kode OTP hanya angka';
    return null;
  }

  /// Compose multiple validators — runs each in order, returns first error
  static String? Function(String?) compose(
      List<String? Function(String?)> validators) {
    return (value) {
      for (final v in validators) {
        final err = v(value);
        if (err != null) return err;
      }
      return null;
    };
  }
}
