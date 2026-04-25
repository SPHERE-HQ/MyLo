import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_dialog.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final historyProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get('/browser/history');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hist = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat'), actions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: () async {
            final ok = await MDialog.confirm(context: context,
                title: 'Hapus semua riwayat?', message: 'Tindakan ini tidak bisa dibatalkan.', destructive: true);
            if (ok == true) {
              await ref.read(dioProvider).delete('/browser/history');
              ref.invalidate(historyProvider);
              if (context.mounted) MSnackbar.show(context, 'Riwayat dihapus');
            }
          },
        ),
      ]),
      body: hist.when(
        loading: () => const Padding(padding: EdgeInsets.all(MyloSpacing.lg), child: MLoadingSkeleton(height: 60)),
        error: (e, _) => MEmptyState(icon: Icons.error_outline, title: 'Gagal', subtitle: '$e'),
        data: (items) {
          if (items.isEmpty) {
            return const MEmptyState(
                icon: Icons.history, title: 'Tidak ada riwayat',
                subtitle: 'Halaman yang Anda kunjungi akan muncul di sini');
          }
          return ListView.separated(
            padding: const EdgeInsets.all(MyloSpacing.lg),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 8),
            itemBuilder: (_, i) {
              final h = items[i];
              return ListTile(
                leading: const Icon(Icons.history, color: MyloColors.textSecondary),
                title: Text(h['title']?.toString() ?? ''),
                subtitle: Text(h['url']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: h['visitedAt'] == null ? null
                    : Text(timeago.format(DateTime.parse(h['visitedAt']), locale: 'id'),
                        style: const TextStyle(fontSize: 11, color: MyloColors.textTertiary)),
                onTap: () => Navigator.pop(context, h['url']?.toString()),
              );
            },
          );
        },
      ),
    );
  }
}
