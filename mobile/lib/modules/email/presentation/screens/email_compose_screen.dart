import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';
import 'email_list_screen.dart';

class EmailComposeScreen extends ConsumerStatefulWidget {
  const EmailComposeScreen({super.key});
  @override
  ConsumerState<EmailComposeScreen> createState() => _S();
}

class _S extends ConsumerState<EmailComposeScreen> {
  final _toCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;

  Future<void> _send() async {
    if (_toCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      MSnackbar.warning(context, 'Penerima dan isi wajib diisi');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(dioProvider).post('/emails', data: {
        'to': _toCtrl.text.split(',').map((e) => e.trim()).toList(),
        'subject': _subjectCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
      });
      ref.invalidate(emailListProvider);
      if (mounted) { MSnackbar.success(context, 'Email terkirim'); context.pop(); }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal kirim: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tulis Email'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: MButton(label: 'Kirim', isLoading: _sending, onPressed: _send),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(MyloSpacing.lg),
        child: Column(children: [
          MTextField(controller: _toCtrl, label: 'Kepada', hint: 'email@example.com'),
          const SizedBox(height: MyloSpacing.md),
          MTextField(controller: _subjectCtrl, label: 'Subjek'),
          const SizedBox(height: MyloSpacing.md),
          MTextField(controller: _bodyCtrl, label: 'Isi pesan',
              maxLines: 12, hint: 'Tulis pesan kamu di sini...'),
        ]),
      ),
    );
  }
}
