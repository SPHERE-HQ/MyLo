import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _S();
}

class _S extends ConsumerState<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  bool _loading = false;

  Future<void> _save() async {
    if (_new.text.length < 6) { MSnackbar.warning(context, 'Password baru min. 6'); return; }
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).put('/auth/password', data: {
        'oldPassword': _old.text, 'newPassword': _new.text,
      });
      if (mounted) { MSnackbar.success(context, 'Password diperbarui'); context.pop(); }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ganti Password')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(MyloSpacing.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MTextField(controller: _old, label: 'Password Lama', obscureText: true,
            prefixIcon: Icons.lock_outline),
        const SizedBox(height: MyloSpacing.md),
        MTextField(controller: _new, label: 'Password Baru', obscureText: true,
            prefixIcon: Icons.lock),
        const SizedBox(height: MyloSpacing.xl),
        MButton(label: 'Simpan', size: MButtonSize.large,
            isLoading: _loading, onPressed: _save),
      ]),
    ),
  );
}
