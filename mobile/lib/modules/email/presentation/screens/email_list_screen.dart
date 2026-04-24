import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';

final emailFolderProvider = StateProvider<String>((ref) => 'inbox');

final emailListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final folder = ref.watch(emailFolderProvider);
  final dio = ref.read(dioProvider);
  final res = await dio.get('/emails', queryParameters: {'folder': folder});
  return (res.data as List).cast<Map<String, dynamic>>();
});

class EmailListScreen extends ConsumerWidget {
  const EmailListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(emailFolderProvider);
    final emails = ref.watch(emailListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Email'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.folder_outlined),
            onSelected: (v) => ref.read(emailFolderProvider.notifier).state = v,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'inbox', child: Text('Inbox')),
              PopupMenuItem(value: 'sent', child: Text('Terkirim')),
              PopupMenuItem(value: 'starred', child: Text('Berbintang')),
              PopupMenuItem(value: 'trash', child: Text('Sampah')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/home/email/compose'),
        icon: const Icon(Icons.edit),
        label: const Text('Tulis'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(emailListProvider),
        child: emails.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.all(MyloSpacing.lg),
            itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, __) => const MLoadingSkeleton(height: 70),
          ),
          error: (e, _) => MEmptyState(icon: Icons.error_outline, title: 'Gagal memuat', subtitle: '$e'),
          data: (list) {
            if (list.isEmpty) {
              return const MEmptyState(
                icon: Icons.mark_email_read_outlined,
                title: 'Tidak ada email',
                subtitle: 'Folder ini kosong',
              );
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = list[i];
                final isRead = e['isRead'] as bool? ?? false;
                final from = e['from']?.toString() ?? '?';
                return ListTile(
                  leading: MAvatar(name: from, size: MAvatarSize.md),
                  title: Text(e['subject']?.toString() ?? '(tanpa subjek)',
                      style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    folder == 'sent' ? (e['to'] is List ? (e['to'] as List).join(', ') : '') : from,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  trailing: e['createdAt'] != null
                      ? Text(timeago.format(DateTime.parse(e['createdAt']), locale: 'id'),
                          style: const TextStyle(fontSize: 11, color: MyloColors.textSecondary))
                      : null,
                  onTap: () => context.push('/home/email/${e['id']}'),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
