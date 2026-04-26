import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_card.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';

final notifFilterProvider = StateProvider<String>((_) => 'all');

final notifProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get('/notifications');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _iconFor(String? type) => switch (type) {
        'message' => Icons.chat_bubble_outline,
        'like' => Icons.favorite_outline,
        'comment' => Icons.comment_outlined,
        'follow' => Icons.person_add_outlined,
        'email' => Icons.mail_outline,
        'community' => Icons.forum_outlined,
        _ => Icons.notifications_outlined,
      };

  String _labelFor(String f) => switch (f) {
        'all' => 'Semua',
        'message' => 'Chat',
        'like' => 'Suka',
        'comment' => 'Komentar',
        'follow' => 'Pengikut',
        'email' => 'Email',
        'community' => 'Komunitas',
        _ => f,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(notifFilterProvider);
    final list = ref.watch(notifProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(dioProvider).post('/notifications/read-all');
              ref.invalidate(notifProvider);
            },
            child: const Text('Tandai Dibaca'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: MyloSpacing.lg),
              children: [
                for (final f in const ['all', 'message', 'like', 'comment', 'follow', 'email', 'community'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_labelFor(f)),
                      selected: filter == f,
                      onSelected: (_) => ref.read(notifFilterProvider.notifier).state = f,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notifProvider),
        child: list.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.all(MyloSpacing.lg), itemCount: 6,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, __) => const MLoadingSkeleton(height: 60),
          ),
          error: (e, _) => MEmptyState(icon: Icons.error_outline, title: 'Gagal', subtitle: '$e'),
          data: (raw) {
            final items = filter == 'all'
                ? raw
                : raw.where((n) => (n['type']?.toString() ?? '') == filter).toList();
            if (items.isEmpty) {
              return const MEmptyState(
                icon: Icons.notifications_none,
                title: 'Tidak ada notifikasi',
                subtitle: 'Notifikasi akan muncul di sini',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(MyloSpacing.lg),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final n = items[i];
                final isRead = n['isRead'] as bool? ?? false;
                return Dismissible(
                  key: ValueKey(n['id']),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: MyloColors.danger,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await ref.read(dioProvider).delete('/notifications/${n['id']}');
                    ref.invalidate(notifProvider);
                  },
                  child: MCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: isRead ? null : MyloColors.primary.withAlpha(13),
                    onTap: () async {
                      if (!isRead) {
                        await ref.read(dioProvider).post('/notifications/${n['id']}/read');
                        ref.invalidate(notifProvider);
                      }
                    },
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: MyloColors.primary.withAlpha(31),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_iconFor(n['type']?.toString()), color: MyloColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(n['title']?.toString() ?? '',
                              style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                          if (n['body'] != null)
                            Text(n['body'].toString(),
                                style: const TextStyle(fontSize: 13, color: MyloColors.textSecondary)),
                          if (n['createdAt'] != null)
                            Text(timeago.format(DateTime.parse(n['createdAt']), locale: 'id'),
                                style: const TextStyle(fontSize: 11, color: MyloColors.textTertiary)),
                        ]),
                      ),
                      if (!isRead)
                        Container(width: 8, height: 8,
                            decoration: const BoxDecoration(color: MyloColors.primary, shape: BoxShape.circle)),
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
