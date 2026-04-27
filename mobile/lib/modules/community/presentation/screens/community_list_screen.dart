import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_badge.dart';
import '../../../../shared/widgets/m_card.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final communityListProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get('/community/servers');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class CommunityListScreen extends ConsumerWidget {
  const CommunityListScreen({super.key});

  Future<void> _join(WidgetRef ref, BuildContext ctx, String id) async {
    try {
      await ref.read(dioProvider).post('/community/servers/$id/join');
      ref.invalidate(communityListProvider);
      if (ctx.mounted) MSnackbar.success(ctx, 'Berhasil gabung server');
    } catch (e) {
      if (ctx.mounted) MSnackbar.error(ctx, 'Gagal: $e');
    }
  }

  void _open(BuildContext ctx, String serverId) {
    ctx.push('/home/community/$serverId/overview');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(communityListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Komunitas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/home/community/create'),
        icon: const Icon(Icons.add),
        label: const Text('Server Baru'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(communityListProvider),
        child: list.when(
          loading: () => ListView.separated(
            padding: const EdgeInsets.all(MyloSpacing.lg), itemCount: 5,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, __) => const MLoadingSkeleton(height: 80),
          ),
          error: (e, _) => MEmptyState(icon: Icons.error_outline, title: 'Gagal memuat', subtitle: '$e'),
          data: (servers) {
            if (servers.isEmpty) {
              return const MEmptyState(
                icon: Icons.groups_outlined,
                title: 'Belum ada komunitas',
                subtitle: 'Buat atau gabung server untuk mulai berbincang',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(MyloSpacing.lg),
              itemCount: servers.length,
              itemBuilder: (_, i) {
                final s = servers[i];
                final joined = s['joined'] as bool? ?? false;
                return MCard(
                  margin: const EdgeInsets.only(bottom: MyloSpacing.md),
                  onTap: joined ? () => _open(context, s['id']) : null,
                  child: Row(children: [
                    s['iconUrl'] != null
                        ? ClipRRect(borderRadius: BorderRadius.circular(MyloRadius.md),
                            child: CachedNetworkImage(imageUrl: s['iconUrl'],
                                width: 56, height: 56, fit: BoxFit.cover))
                        : MAvatar(name: s['name'] ?? '?', size: MAvatarSize.lg),
                    const SizedBox(width: MyloSpacing.md),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s['name'] ?? '?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        if (s['description'] != null)
                          Text(s['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: MyloColors.textSecondary)),
                        const SizedBox(height: 4),
                        Row(children: [
                          if (joined) const MBadge(label: 'Bergabung', variant: MBadgeVariant.success),
                          if (s['isPublic'] == true) ...[
                            const SizedBox(width: 6),
                            const MBadge(label: 'Publik', variant: MBadgeVariant.neutral),
                          ],
                        ]),
                      ]),
                    ),
                    if (!joined)
                      TextButton(onPressed: () => _join(ref, context, s['id']), child: const Text('Gabung')),
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
