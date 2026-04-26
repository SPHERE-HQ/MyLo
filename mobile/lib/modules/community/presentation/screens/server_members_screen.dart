import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';

final serverMembersProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, serverId) async {
  final res = await ref.read(dioProvider).get('/community/servers/$serverId/members');
  // Backend returns list of members from _getServer or we use a dedicated endpoint
  if (res.data is List) {
    return (res.data as List).cast<Map<String, dynamic>>();
  }
  // If data is a map with 'members' key
  final d = res.data as Map<String, dynamic>;
  return (d['members'] as List? ?? []).cast<Map<String, dynamic>>();
});

class ServerMembersScreen extends ConsumerWidget {
  final String serverId;
  final String serverName;
  const ServerMembersScreen(
      {super.key, required this.serverId, required this.serverName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(serverMembersProvider(serverId));
    return Scaffold(
      appBar: AppBar(title: Text('Anggota $serverName')),
      body: members.when(
        loading: () => ListView.builder(
          itemCount: 8,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              MLoadingSkeleton(width: 44, height: 44, borderRadius: 22),
              SizedBox(width: 12),
              Expanded(child: MLoadingSkeleton(height: 14)),
            ]),
          ),
        ),
        error: (e, _) =>
            MEmptyState(icon: Icons.error_outline, title: 'Gagal memuat', subtitle: '$e'),
        data: (list) => list.isEmpty
            ? const MEmptyState(
                icon: Icons.group_outlined,
                title: 'Belum ada anggota',
                subtitle: 'Undang teman untuk bergabung')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) {
                  final m = list[i];
                  final name = (m['displayName'] ?? m['username'] ?? '?')
                      .toString();
                  final role = (m['role'] ?? 'member').toString();
                  return ListTile(
                    leading: MAvatar(
                        name: name,
                        url: m['avatarUrl'] as String?,
                        size: MAvatarSize.md),
                    title: Text(name,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('@${m['username'] ?? ''}',
                        style: const TextStyle(
                            color: MyloColors.textTertiary, fontSize: 12)),
                    trailing: role == 'owner'
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: MyloColors.warning.withAlpha(51),
                              borderRadius:
                                  BorderRadius.circular(MyloRadius.full),
                            ),
                            child: const Text('Owner',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: MyloColors.warning,
                                    fontWeight: FontWeight.w600)))
                        : null,
                    onTap: () => context
                        .push('/home/users/${m['id']}'),
                  );
                },
              ),
      ),
    );
  }
}
