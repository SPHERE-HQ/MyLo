import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';
import 'community_list_screen.dart';

class ServerCreateScreen extends ConsumerStatefulWidget {
  const ServerCreateScreen({super.key});
  @override
  ConsumerState<ServerCreateScreen> createState() => _S();
}

class _S extends ConsumerState<ServerCreateScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _isPublic = true;
  bool _loading = false;

  Future<void> _create() async {
    if (_name.text.trim().isEmpty) {
      MSnackbar.warning(context, 'Nama wajib diisi');
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(dioProvider).post('/community/servers', data: {
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'isPublic': _isPublic,
      });
      ref.invalidate(communityListProvider);
      if (mounted) { MSnackbar.success(context, 'Server dibuat'); context.pop(); }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Server Baru')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(MyloSpacing.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MTextField(controller: _name, label: 'Nama Server', hint: 'Misal: Komunitas Flutter'),
          const SizedBox(height: MyloSpacing.md),
          MTextField(controller: _desc, label: 'Deskripsi (opsional)', maxLines: 3),
          const SizedBox(height: MyloSpacing.md),
          SwitchListTile(
            title: const Text('Publik'),
            subtitle: const Text('Bisa ditemukan & digabung semua orang'),
            value: _isPublic,
            onChanged: (v) => setState(() => _isPublic = v),
          ),
          const SizedBox(height: MyloSpacing.xl),
          MButton(label: 'Buat Server', size: MButtonSize.large,
              isLoading: _loading, onPressed: _create),
        ]),
      ),
    );
  }
}
