import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';

final conversationsProvider =
    FutureProvider.family<List, bool>((ref, archived) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get('/chat/conversations',
      queryParameters: {'archived': archived ? '1' : '0'});
  return res.data as List;
});

final _userSearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, q) async {
  if (q.trim().isEmpty) return [];
  final res = await ref.read(dioProvider).get('/users', queryParameters: {'q': q});
  return (res.data as List).cast<Map<String, dynamic>>();
});

class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});
  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  bool _showSearch = false;
  bool _showArchived = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _startingChat = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _startDirectChat(Map<String, dynamic> user) async {
    if (_startingChat) return;
    setState(() => _startingChat = true);
    try {
      final res = await ref.read(dioProvider).post('/chat/conversations', data: {
        'type': 'private', 'memberIds': [user['id']],
      });
      final id = res.data['id'].toString();
      if (mounted) {
        setState(() => _showSearch = false);
        ref.invalidate(conversationsProvider);
        final name = user['displayName'] ?? user['username'] ?? 'Chat';
        final qp = <String, String>{
          'name': name.toString(),
          if (user['id'] != null) 'userId': user['id'].toString(),
          if (user['avatarUrl'] != null) 'avatar': user['avatarUrl'].toString(),
        };
        final query = qp.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
        context.push('/home/chat/$id?$query');
      }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal memulai chat: $e');
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  Future<void> _showConversationMenu(Map<String, dynamic> conv, String name, bool archived) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text(name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          ListTile(
            leading: Icon(archived ? Icons.unarchive_outlined : Icons.archive_outlined),
            title: Text(archived ? 'Keluarkan dari arsip' : 'Arsipkan percakapan'),
            onTap: () => Navigator.pop(ctx, 'archive'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Hapus percakapan',
                style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
          const SizedBox(height: 4),
        ]),
      ),
    );
    if (action == null) return;
    if (action == 'archive') {
      try {
        await ref.read(dioProvider).post(
              '/chat/conversations/${conv['id']}/archive',
              data: {'archived': !archived},
            );
        ref.invalidate(conversationsProvider);
        if (mounted) MSnackbar.success(context, archived ? 'Dikeluarkan dari arsip' : 'Diarsipkan');
      } catch (e) {
        if (mounted) MSnackbar.error(context, 'Gagal: $e');
      }
    } else if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hapus percakapan?'),
          content: Text('Semua pesan dengan $name akan hilang dari daftar Anda.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await ref.read(dioProvider).delete('/chat/conversations/${conv['id']}');
        ref.invalidate(conversationsProvider);
        if (mounted) MSnackbar.success(context, 'Percakapan dihapus');
      } catch (e) {
        if (mounted) MSnackbar.error(context, 'Gagal menghapus: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final convAsync = ref.watch(conversationsProvider(_showArchived));
    final meAsync = ref.watch(authStateProvider);
    final myId = meAsync.valueOrNull?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? MTextField.search(
                controller: _searchCtrl, hint: 'Cari pengguna...',
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : Row(children: [
                Text(_showArchived ? 'Arsip' : 'Mylo'),
                if (_showArchived) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.archive, size: 18),
                ],
              ]),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) { _searchCtrl.clear(); _searchQuery = ''; }
            }),
          ),
          if (!_showSearch)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (v) {
                if (v == 'archived') setState(() => _showArchived = !_showArchived);
                if (v == 'group') context.push('/home/chat/create-group');
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'group', child: Row(children: [
                  Icon(Icons.group_add_outlined, size: 18), SizedBox(width: 10), Text('Grup baru'),
                ])),
                PopupMenuItem(value: 'archived', child: Row(children: [
                  Icon(_showArchived ? Icons.chat_outlined : Icons.archive_outlined, size: 18),
                  const SizedBox(width: 10),
                  Text(_showArchived ? 'Lihat aktif' : 'Lihat arsip'),
                ])),
              ],
            ),
        ],
      ),
      body: _showSearch
          ? _buildSearch(myId)
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(conversationsProvider),
              child: convAsync.when(
                loading: () => ListView.separated(
                  itemCount: 8,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, __) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      const MLoadingSkeleton(height: 44, width: 44, borderRadius: 22),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
                        MLoadingSkeleton(height: 14, width: 120),
                        SizedBox(height: 6),
                        MLoadingSkeleton(height: 12),
                      ])),
                    ]),
                  ),
                ),
                error: (e, _) => Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline, size: 40),
                    const SizedBox(height: 8),
                    Text('Gagal memuat: $e'),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: () => ref.invalidate(conversationsProvider),
                        child: const Text('Coba lagi')),
                  ]),
                ),
                data: (convs) {
                  if (convs.isEmpty) {
                    return MEmptyState(
                        icon: _showArchived ? Icons.archive_outlined : Icons.chat_bubble_outline,
                        title: _showArchived ? 'Tidak ada percakapan arsip' : 'Belum ada percakapan',
                        subtitle: _showArchived
                            ? 'Percakapan yang Anda arsipkan muncul di sini'
                            : 'Mulai chat dengan menekan ikon cari di atas');
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 4),
                    itemCount: convs.length + (_showArchived ? 0 : 1),
                    itemBuilder: (_, i) {
                      if (!_showArchived && i == 0) return _aiTile();
                      final c = convs[(_showArchived ? i : i - 1)] as Map<String, dynamic>;
                      return _convTile(c, myId);
                    },
                  );
                },
              ),
            ),
    );
  }

  Widget _aiTile() => ListTile(
    leading: const CircleAvatar(
      backgroundColor: MyloColors.primary,
      child: Icon(Icons.auto_awesome, color: Colors.white),
    ),
    title: const Text('Mylo AI', style: TextStyle(fontWeight: FontWeight.w600)),
    subtitle: const Text('Asisten pintar — tanya apa saja'),
    trailing: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: MyloColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text('AI', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: MyloColors.primary)),
    ),
    onTap: () => context.push('/home/ai'),
  );

  Widget _convTile(Map<String, dynamic> c, String myId) {
    final isGroup = c['type'] == 'group';
    final archived = c['archived'] == true;
    String name = c['name']?.toString() ?? '';
    String? avatar = c['avatarUrl'] as String?;
    String? otherUserId;
    final members = (c['members'] as List?) ?? [];
    if (!isGroup) {
      final other = members.firstWhere(
          (m) => m['id'] != myId,
          orElse: () => members.isNotEmpty ? members.first : {});
      if (name.isEmpty) {
        name = other['displayName']?.toString() ??
            other['username']?.toString() ?? 'Percakapan';
      }
      avatar ??= other['avatarUrl'] as String?;
      otherUserId = other['id'] as String?;
    }
    return ListTile(
      leading: MAvatar(name: name, url: avatar, size: MAvatarSize.md),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(c['lastMessage']?.toString() ?? 'Belum ada pesan',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: isGroup
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: MyloColors.secondary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text('Grup', style: TextStyle(fontSize: 11)))
          : null,
      onTap: () {
        final qp = <String, String>{
          'name': name,
          if (otherUserId != null) 'userId': otherUserId,
          if (avatar != null) 'avatar': avatar,
        };
        final query = qp.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
        context.push('/home/chat/${c['id']}?$query');
      },
      onLongPress: () => _showConversationMenu(c, name, archived),
    );
  }

  Widget _buildSearch(String myId) {
    if (_searchQuery.trim().isEmpty) {
      return const Center(child: Text('Ketik nama atau username untuk mencari'));
    }
    final results = ref.watch(_userSearchProvider(_searchQuery));
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (users) {
        final filtered = users.where((u) => u['id']?.toString() != myId).toList();
        if (filtered.isEmpty) {
          return const MEmptyState(icon: Icons.person_search, title: 'Tidak ditemukan');
        }
        return ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (_, i) {
            final u = filtered[i];
            final name = u['displayName']?.toString() ?? u['username']?.toString() ?? '';
            return ListTile(
              leading: MAvatar(name: name, url: u['avatarUrl'] as String?),
              title: Text(name),
              subtitle: Text('@${u['username'] ?? ''}'),
              trailing: _startingChat
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chat_bubble_outline),
              onTap: () => _startDirectChat(u),
            );
          },
        );
      },
    );
  }
}
