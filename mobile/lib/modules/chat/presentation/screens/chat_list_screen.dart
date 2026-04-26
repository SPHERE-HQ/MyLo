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

// Non-autoDispose: tetap hidup saat pindah tab sehingga tidak blank
final conversationsProvider = FutureProvider<List>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get('/chat/conversations');
  return res.data as List;
});

final _userSearchProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
        (ref, q) async {
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
        'type': 'private',
        'memberIds': [user['id']],
      });
      final id = res.data['id'].toString();
      if (mounted) {
        setState(() => _showSearch = false);
        ref.invalidate(conversationsProvider);
        context.push('/home/chat/$id', extra: user['displayName'] ?? user['username']);
      }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal memulai chat: $e');
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final convAsync = ref.watch(conversationsProvider);
    final meAsync = ref.watch(authStateProvider);
    final myId = meAsync.valueOrNull?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? MTextField.search(
                controller: _searchCtrl,
                hint: 'Cari pengguna...',
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Mylo'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchCtrl.clear();
                _searchQuery = '';
              }
            }),
          ),
          if (!_showSearch)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => context.push('/home/chat/create-group'),
              tooltip: 'Grup baru',
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
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const MLoadingSkeleton(height: 14, width: 120),
                        const SizedBox(height: 6),
                        const MLoadingSkeleton(height: 12),
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
                    return const MEmptyState(
                        icon: Icons.chat_bubble_outline,
                        title: 'Belum ada percakapan',
                        subtitle: 'Mulai chat dengan menekan ikon cari di atas');
                  }
                  // Mylo AI entry always at top
                  return ListView.builder(
                    padding: const EdgeInsets.only(top: 4),
                    itemCount: convs.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) {
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: MyloColors.primary,
                            child: const Icon(Icons.auto_awesome, color: Colors.white),
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
                      }
                      final c = convs[i - 1] as Map<String, dynamic>;
                      final isGroup = c['type'] == 'group';
                      String name = c['name']?.toString() ?? '';
                      if (!isGroup && name.isEmpty) {
                        final members = (c['members'] as List?) ?? [];
                        final other = members.firstWhere(
                            (m) => m['userId'] != myId,
                            orElse: () => members.isNotEmpty ? members.first : {});
                        name = other['displayName']?.toString() ??
                            other['username']?.toString() ?? 'Percakapan';
                      }
                      return ListTile(
                        leading: MAvatar(name: name, size: MAvatarSize.md),
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
                        onTap: () => context.push('/home/chat/${c['id']}', extra: name),
                      );
                    },
                  );
                },
              ),
            ),
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
