import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_dialog.dart';
import '../../../../shared/widgets/m_secure_screen.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';

class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});
  @override
  ConsumerState<DeleteAccountScreen> createState() => _S();
}

class _S extends ConsumerState<DeleteAccountScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  bool _confirm = false;

  Future<void> _delete() async {
    final ok = await MDialog.confirm(
      context: context,
      title: 'Hapus akun selamanya?',
      message: 'Semua data Anda akan dihapus permanen. Tindakan ini tidak bisa dibatalkan.',
      destructive: true,
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).post('/auth/account/delete',
          data: {'password': _password.text});
      await ref.read(authStateProvider.notifier).logout();
      if (mounted) context.go('/auth/login');
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
        appBar: AppBar(title: const Text('Hapus Akun')),
        body: ListView(padding: const EdgeInsets.all(MyloSpacing.xxl), children: [
          Container(
            padding: const EdgeInsets.all(MyloSpacing.lg),
            decoration: BoxDecoration(
              color: MyloColors.danger.withOpacity(.08),
              borderRadius: BorderRadius.circular(MyloRadius.md),
              border: Border.all(color: MyloColors.danger.withOpacity(.3)),
            ),
            child: const Text(
              'PERHATIAN: Setelah dihapus, akun & semua data tidak bisa dipulihkan. '
              'Sesuai UU PDP, tindakan ini permanen.',
              style: TextStyle(color: MyloColors.danger),
            ),
          ),
          const SizedBox(height: MyloSpacing.xxl),
          MTextField(
            controller: _password,
            label: 'Konfirmasi Password',
            obscureText: true,
          ),
          const SizedBox(height: MyloSpacing.lg),
          CheckboxListTile(
            value: _confirm,
            onChanged: (v) => setState(() => _confirm = v ?? false),
            title: const Text('Saya paham bahwa data saya akan dihapus permanen'),
          ),
          const SizedBox(height: MyloSpacing.xxl),
          MButton(
            label: 'Hapus Akun Selamanya',
            variant: MButtonVariant.danger,
            isLoading: _busy,
            onPressed: _confirm && _password.text.isNotEmpty ? _delete : null,
          ),
        ]),
      ),
    );
  }
}
