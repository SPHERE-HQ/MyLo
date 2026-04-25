import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_dialog.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final groupMembersProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, id) async {
  final res = await ref.read(dioProvider).get('/chat/conversations/$id');
  final data = res.data as Map<String, dynamic>;
  return (data['members'] as List? ?? const []).cast<Map<String, dynamic>>();
});

class GroupSettingsScreen extends ConsumerWidget {
  final String conversationId;
  const GroupSettingsScreen({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(groupMembersProvider(conversationId));
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Grup')),
      body: ListView(padding: const EdgeInsets.all(MyloSpacing.lg), children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: MyloSpacing.sm),
          child: Text('ANGGOTA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              color: MyloColors.textSecondary, letterSpacing: 0.8)),
        ),
        members.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Gagal: $e'),
          data: (list) => Column(children: list.map((m) => ListTile(
            leading: CircleAvatar(child: Text((m['username']?.toString() ?? '?')[0].toUpperCase())),
            title: Text(m['displayName']?.toString() ?? m['username']?.toString() ?? ''),
            subtitle: Text('@${m['username']}'),
            trailing: IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: MyloColors.danger),
              onPressed: () async {
                final ok = await MDialog.confirm(context: context,
                    title: 'Keluarkan anggota?', message: 'Mereka tidak bisa lagi mengakses chat ini.', destructive: true);
                if (ok != true) return;
                await ref.read(dioProvider).delete('/chat/conversations/$conversationId/members/${m['id']}');
                ref.invalidate(groupMembersProvider(conversationId));
                if (context.mounted) MSnackbar.show(context, 'Anggota dikeluarkan');
              },
            ),
          )).toList()),
        ),
        const SizedBox(height: MyloSpacing.xxl),
        const Divider(),
        const SizedBox(height: MyloSpacing.lg),
        MButton(
          label: 'Hapus / Keluar dari Grup',
          variant: MButtonVariant.danger,
          onPressed: () async {
            final ok = await MDialog.confirm(context: context,
                title: 'Yakin?', message: 'Anda akan keluar dari grup ini.', destructive: true);
            if (ok != true) return;
            await ref.read(dioProvider).delete('/chat/conversations/$conversationId');
            if (context.mounted) context.go('/home/chat');
          },
        ),
      ]),
    );
  }
}
