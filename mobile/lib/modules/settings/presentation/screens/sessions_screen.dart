import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_card.dart';
import '../../../../shared/widgets/m_dialog.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final sessionsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get('/auth/sessions');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(sessionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sesi Login Aktif')),
      body: list.when(
        loading: () => const Padding(
            padding: EdgeInsets.all(MyloSpacing.lg),
            child: MLoadingSkeleton(height: 70)),
        error: (e, _) => MEmptyState(icon: Icons.error_outline, title: 'Gagal', subtitle: '$e'),
        data: (items) {
          if (items.isEmpty) {
            return const MEmptyState(icon: Icons.devices, title: 'Tidak ada sesi', subtitle: 'Hanya perangkat ini yang aktif');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(MyloSpacing.lg),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final s = items[i];
              return MCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  const Icon(Icons.smartphone, color: MyloColors.primary, size: 28),
                  const SizedBox(width: MyloSpacing.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s['device']?.toString() ?? 'Unknown device', style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (s['ip'] != null)
                        Text('IP: ${s['ip']}', style: const TextStyle(fontSize: 12, color: MyloColors.textSecondary)),
                      if (s['lastActive'] != null)
                        Text('Aktif ${timeago.format(DateTime.parse(s['lastActive']), locale: 'id')}',
                            style: const TextStyle(fontSize: 11, color: MyloColors.textTertiary)),
                    ]),
                  ),
                  TextButton(
                    onPressed: () async {
                      final ok = await MDialog.confirm(context: context,
                          title: 'Keluarkan?', message: 'Sesi ini akan dilogout.', destructive: true);
                      if (ok != true) return;
                      try {
                        await ref.read(dioProvider).delete('/auth/sessions/${s['id']}');
                        ref.invalidate(sessionsProvider);
                        if (context.mounted) MSnackbar.show(context, 'Sesi dihapus');
                      } catch (e) {
                        if (context.mounted) MSnackbar.show(context, 'Gagal: $e');
                      }
                    },
                    child: const Text('Hapus', style: TextStyle(color: MyloColors.danger)),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
