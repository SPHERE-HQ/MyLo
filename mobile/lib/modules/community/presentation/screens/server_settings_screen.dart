import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_dialog.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';

class ServerSettingsScreen extends ConsumerStatefulWidget {
  final String serverId;
  final Map<String, dynamic>? initial;
  const ServerSettingsScreen({super.key, required this.serverId, this.initial});
  @override
  ConsumerState<ServerSettingsScreen> createState() => _S();
}

class _S extends ConsumerState<ServerSettingsScreen> {
  late final _name = TextEditingController(text: widget.initial?['name']?.toString() ?? '');
  late final _desc = TextEditingController(text: widget.initial?['description']?.toString() ?? '');
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).put('/community/servers/${widget.serverId}',
          data: {'name': _name.text, 'description': _desc.text});
      if (mounted) { MSnackbar.show(context, 'Tersimpan'); Navigator.pop(context); }
    } catch (e) {
      if (mounted) MSnackbar.show(context, 'Gagal: $e');
    } finally { setState(() => _busy = false); }
  }

  Future<void> _delete() async {
    final ok = await MDialog.confirm(context: context,
        title: 'Hapus server?', message: 'Server, channel, dan semua pesan akan dihapus.', destructive: true);
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(dioProvider).delete('/community/servers/${widget.serverId}');
      if (mounted) context.go('/home/community');
    } catch (e) {
      if (mounted) MSnackbar.show(context, 'Gagal: $e');
    } finally { setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Server')),
      body: ListView(padding: const EdgeInsets.all(MyloSpacing.xxl), children: [
        MTextField(controller: _name, label: 'Nama Server'),
        const SizedBox(height: MyloSpacing.lg),
        MTextField(controller: _desc, label: 'Deskripsi', maxLines: 3),
        const SizedBox(height: MyloSpacing.xxl),
        MButton(label: 'Simpan Perubahan', isLoading: _busy, onPressed: _save),
        const SizedBox(height: MyloSpacing.xxl),
        const Divider(),
        const SizedBox(height: MyloSpacing.lg),
        MButton(label: 'Hapus Server',
            variant: MButtonVariant.danger, isLoading: _busy, onPressed: _delete),
      ]),
    );
  }
}
