import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});
  @override
  ConsumerState<ResetPasswordScreen> createState() => _S();
}

class _S extends ConsumerState<ResetPasswordScreen> {
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    if (_codeCtrl.text.isEmpty || _passCtrl.text.length < 6) {
      MSnackbar.warning(context, 'Isi kode & password baru (min 6)');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post('/auth/reset-password', data: {
        'email': widget.email,
        'code': _codeCtrl.text.trim(),
        'password': _passCtrl.text,
      });
      if (!mounted) return;
      MSnackbar.success(context, 'Password berhasil direset, silakan login');
      context.go('/auth/login');
    } on DioException catch (e) {
      MSnackbar.error(context, 'Gagal: ${e.response?.data?["error"] ?? e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MyloSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Reset Password', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: MyloSpacing.sm),
              Text('Kode dikirim ke ${widget.email}',
                  style: TextStyle(color: MyloColors.textSecondary)),
              const SizedBox(height: MyloSpacing.xxl),
              MTextField(
                controller: _codeCtrl,
                label: 'Kode 6 digit',
                hint: '123456',
                prefixIcon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: MyloSpacing.lg),
              MTextField(
                controller: _passCtrl,
                label: 'Password Baru',
                hint: 'Min. 6 karakter',
                prefixIcon: Icons.lock_outline,
                obscureText: true,
              ),
              const SizedBox(height: MyloSpacing.xxl),
              MButton(
                label: 'Reset Password',
                size: MButtonSize.large,
                isLoading: _loading,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
