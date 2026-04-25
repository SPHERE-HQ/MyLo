import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:shared_preferences/shared_preferences.dart';

class BiometricResult {
  final bool ok;
  final String? error;
  const BiometricResult(this.ok, [this.error]);
}

class BiometricService {
  static final _auth = LocalAuthentication();
  static const _enabledKey = 'mylo.biometric_enabled';

  static Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _auth.canCheckBiometrics;
      if (canCheck) return true;
      // Fall back to device passcode/PIN if available.
      final available = await _auth.getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_enabledKey, v);
  }

  /// Backward-compatible boolean wrapper.
  static Future<bool> authenticate(String reason) async {
    final r = await authenticateDetailed(reason);
    return r.ok;
  }

  /// Authenticate and return a result with a human-readable error if it fails.
  /// We allow the device passcode as a fallback when no biometric is enrolled
  /// so users on devices with only a PIN can still sign in.
  static Future<BiometricResult> authenticateDetailed(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (ok) return const BiometricResult(true);
      return const BiometricResult(false, 'Verifikasi dibatalkan');
    } on PlatformException catch (e) {
      return BiometricResult(false, _mapError(e));
    } catch (e) {
      return BiometricResult(false, 'Verifikasi gagal: $e');
    }
  }

  static String _mapError(PlatformException e) {
    switch (e.code) {
      case auth_error.notAvailable:
        return 'Biometrik tidak tersedia di perangkat ini.';
      case auth_error.notEnrolled:
        return 'Belum ada sidik jari/Face ID terdaftar di perangkat. '
            'Tambahkan dulu di pengaturan perangkat.';
      case auth_error.lockedOut:
        return 'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.';
      case auth_error.permanentlyLockedOut:
        return 'Biometrik dinonaktifkan. Buka kunci dengan PIN/pola perangkat dulu.';
      case auth_error.passcodeNotSet:
        return 'Setel kunci layar (PIN/pola) di perangkat dulu.';
      case auth_error.otherOperatingSystem:
        return 'Sistem operasi tidak mendukung biometrik.';
      default:
        final msg = e.message ?? e.code;
        return 'Verifikasi gagal: $msg';
    }
  }
}
