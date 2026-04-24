import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _S();
}

class _S extends ConsumerState<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      MSnackbar.warning(context, 'Email tidak valid');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post('/auth/forgot-password', data: {'email': email});
      if (!mounted) return;
      MSnackbar.success(context, 'Kode reset dikirim ke email kamu');
      context.go('/auth/reset-password?email=$email');
    } on DioException catch (e) {
      MSnackbar.error(context, 'Gagal: ${e.message}');
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
              const Text('Lupa Password',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: MyloSpacing.sm),
              Text('Masukkan email kamu, kami akan kirimkan kode reset.',
                  style: TextStyle(color: MyloColors.textSecondary)),
              const SizedBox(height: MyloSpacing.xxl),
              MTextField(
                controller: _emailCtrl,
                label: 'Email',
                hint: 'kamu@email.com',
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: MyloSpacing.xxl),
              MButton(
                label: 'Kirim Kode',
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
