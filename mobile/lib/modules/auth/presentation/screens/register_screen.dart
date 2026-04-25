import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/google_sign_in_button.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});
  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authStateProvider.notifier).register(
      _userCtrl.text.trim(),
      _emailCtrl.text.trim(),
      _passCtrl.text,
      _nameCtrl.text.trim(),
    );
    final auth = ref.read(authStateProvider);
    if (auth.hasError && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error.toString()), backgroundColor: MyloColors.danger),
      );
    }
    // Navigation handled by router redirect when auth.value != null
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Buat Akun')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(MyloSpacing.xl),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nama Lengkap'),
                  validator: (v) => v == null || v.isEmpty ? 'Nama wajib diisi' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (v) => v == null || v.length < 3 ? 'Minimal 3 karakter' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => v == null || !v.contains('@') ? 'Email tidak valid' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => v == null || v.length < 8 ? 'Minimal 8 karakter' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Konfirmasi Password'),
                  validator: (v) => v != _passCtrl.text ? 'Password tidak sama' : null,
                ),
                const SizedBox(height: 24),
                MButton(
                  label: 'Daftar',
                  onPressed: _register,
                  isLoading: auth.isLoading,
                  size: MButtonSize.large,
                ),
                const OrDivider(),
                const GoogleSignInButton(label: 'Daftar dengan Google'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Sudah punya akun? ', style: TextStyle(color: MyloColors.textSecondary)),
                    TextButton(
                      // Fix: use go() instead of pop() — works regardless of navigation history
                      onPressed: () => context.go('/auth/login'),
                      child: const Text('Masuk'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
