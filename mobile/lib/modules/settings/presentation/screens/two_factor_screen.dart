import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_pin_input.dart';
import '../../../../shared/widgets/m_secure_screen.dart';
import '../../../../shared/widgets/m_snackbar.dart';

class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key});
  @override
  ConsumerState<TwoFactorScreen> createState() => _S();
}

class _S extends ConsumerState<TwoFactorScreen> {
  String? _otpauth;
  String _code = '';
  bool _busy = false;

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final res = await ref.read(dioProvider).post('/auth/2fa/enable');
      setState(() => _otpauth = (res.data as Map)['otpauth']?.toString());
    } catch (e) {
      if (mounted) MSnackbar.show(context, 'Gagal: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.length != 6) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('/auth/2fa/verify', data: {'code': _code});
      await ref.read(authStateProvider.notifier).refreshProfile();
      if (mounted) {
        MSnackbar.show(context, '2FA aktif');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) MSnackbar.show(context, 'Kode salah');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('/auth/2fa/disable');
      await ref.read(authStateProvider.notifier).refreshProfile();
      if (mounted) {
        MSnackbar.show(context, '2FA dinonaktifkan');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) MSnackbar.show(context, 'Gagal: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MSecureScreen(
      child: Scaffold(
        appBar: AppBar(title: const Text('Two-Factor Authentication')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(MyloSpacing.xxl),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Tingkatkan keamanan akun dengan 2FA berbasis authenticator app (Google Authenticator, Authy, dll).',
                style: TextStyle(color: MyloColors.textSecondary)),
            const SizedBox(height: MyloSpacing.xxl),
            if (_otpauth == null) ...[
              MButton(label: 'Aktifkan 2FA', isLoading: _busy, onPressed: _enable),
              const SizedBox(height: MyloSpacing.lg),
              MButton(label: 'Nonaktifkan 2FA',
                  variant: MButtonVariant.danger, isLoading: _busy, onPressed: _disable),
            ] else ...[
              const Text('1. Scan QR di authenticator app'),
              const SizedBox(height: MyloSpacing.md),
              Center(child: QrImageView(data: _otpauth!, size: 200, backgroundColor: Colors.white)),
              const SizedBox(height: MyloSpacing.xxl),
              const Text('2. Masukkan kode 6 digit dari aplikasi'),
              const SizedBox(height: MyloSpacing.lg),
              MPinInput(length: 6, onChanged: (v) => setState(() => _code = v),
                  onCompleted: (_) => _verify()),
              const SizedBox(height: MyloSpacing.xxl),
              MButton(label: 'Verifikasi', isLoading: _busy,
                  onPressed: _code.length == 6 ? _verify : null),
            ],
          ]),
        ),
      ),
    );
  }
}
