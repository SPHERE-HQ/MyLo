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

  static const _folders = [
    ('inbox', Icons.inbox_outlined, 'Kotak Masuk'),
    ('starred', Icons.star_outline, 'Berbintang'),
    ('sent', Icons.send_outlined, 'Terkirim'),
    ('draft', Icons.edit_note_outlined, 'Draf'),
    ('spam', Icons.report_outlined, 'Spam'),
    ('trash', Icons.delete_outline, 'Sampah'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(emailFolderProvider);
    final emails = ref.watch(emailListProvider);
    final folderTitle = _folders.firstWhere((f) => f.$1 == folder).$3;

    return Scaffold(
      appBar: AppBar(
        title: Text(folderTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/home/email/search'),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(children: [
            const Padding(
              padding: EdgeInsets.all(MyloSpacing.lg),
              child: Text('Email', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            for (final f in _folders)
              ListTile(
                leading: Icon(f.$2, color: folder == f.$1 ? MyloColors.primary : null),
                title: Text(f.$3, style: TextStyle(
                    color: folder == f.$1 ? MyloColors.primary : null,
                    fontWeight: folder == f.$1 ? FontWeight.w600 : null)),
                selected: folder == f.$1,
                onTap: () {
                  ref.read(emailFolderProvider.notifier).state = f.$1;
                  Navigator.pop(context);
                },
              ),
          ]),
        ),
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
              return MEmptyState(
                icon: Icons.mail_outline,
                title: 'Folder kosong',
                subtitle: 'Tidak ada email di $folderTitle',
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(MyloSpacing.lg),
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (_, i) {
                final e = list[i];
                final unread = !(e['isRead'] as bool? ?? false);
                final starred = e['isStarred'] as bool? ?? false;
                return InkWell(
                  onTap: () => context.push('/home/email/${e['id']}'),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    MAvatar(name: e['from']?.toString() ?? 'M', size: MAvatarSize.md),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e['from']?.toString() ?? '',
                            style: TextStyle(fontWeight: unread ? FontWeight.bold : FontWeight.w500)),
                        Text(e['subject']?.toString() ?? '(Tanpa subjek)',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: unread ? FontWeight.w600 : FontWeight.normal)),
                        Text(e['body']?.toString() ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: MyloColors.textSecondary)),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      if (e['createdAt'] != null)
                        Text(timeago.format(DateTime.parse(e['createdAt']), locale: 'id'),
                            style: const TextStyle(fontSize: 10, color: MyloColors.textTertiary)),
                      const SizedBox(height: 6),
                      IconButton(
                        padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                        icon: Icon(starred ? Icons.star : Icons.star_outline,
                            color: starred ? Colors.amber : null, size: 20),
                        onPressed: () async {
                          await ref.read(dioProvider).post('/emails/${e['id']}/star');
                          ref.invalidate(emailListProvider);
                        },
                      ),
                    ]),
                  ]),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
