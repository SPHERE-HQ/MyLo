import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';
import '../../../../shared/widgets/m_text_field.dart';

final conversationsProvider = FutureProvider.autoDispose((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get('/chat/conversations');
  return res.data as List;
});

final _userSearchProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
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
        'participantIds': [user['id']],
      });
      final id = (res.data as Map)['id'] as String?;
      if (mounted && id != null) {
        setState(() { _showSearch = false; _searchQuery = ''; _searchCtrl.clear(); });
        final name = (user['displayName'] ?? user['username'] ?? 'Chat').toString();
        context.push('/home/chat/$id?name=${Uri.encodeComponent(name)}&avatar=${user['avatarUrl'] ?? ''}');
      }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final convs = ref.watch(conversationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? MTextField.search(
                controller: _searchCtrl,
                hint: 'Cari pengguna...',
                autofocus: true,
                onChanged: (v) => setState(() => _searchQuery = v),
              )
            : const Text('Mylo',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          if (!_showSearch)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() { _showSearch = true; }),
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _showSearch = false;
                _searchQuery = '';
                _searchCtrl.clear();
              }),
            ),
        ],
      ),
      body: _showSearch && _searchQuery.isNotEmpty
          ? _buildUserSearch()
          : _showSearch && _searchQuery.isEmpty
              ? const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.search, size: 48, color: MyloColors.textTertiary),
                    SizedBox(height: 12),
                    Text('Ketik nama atau username',
                        style: TextStyle(color: MyloColors.textSecondary)),
                  ]),
                )
              : _buildConversationList(convs),
      floatingActionButton: _showSearch
          ? FloatingActionButton.extended(
              backgroundColor: MyloColors.primary,
              onPressed: () => context.push('/home/chat/create-group'),
              icon: const Icon(Icons.group_add, color: Colors.white),
              label: const Text('Grup Baru',
                  style: TextStyle(color: Colors.white)),
            )
          : FloatingActionButton(
              onPressed: () => setState(() => _showSearch = true),
              backgroundColor: MyloColors.primary,
              child: const Icon(Icons.edit, color: Colors.white),
            ),
    );
  }

  Widget _buildUserSearch() {
    final users = ref.watch(_userSearchProvider(_searchQuery));
    return users.when(
      loading: () => ListView.builder(
        itemCount: 5,
        itemBuilder: (_, __) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            MLoadingSkeleton(width: 48, height: 48, borderRadius: 24),
            SizedBox(width: 12),
            Expanded(child: MLoadingSkeleton(height: 14)),
          ]),
        ),
      ),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) => list.isEmpty
          ? const MEmptyState(
              icon: Icons.person_search,
              title: 'Pengguna tidak ditemukan',
              subtitle: 'Coba nama atau username lain')
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final u = list[i];
                final name = (u['displayName'] ?? u['username'] ?? '?').toString();
                return ListTile(
                  leading: MAvatar(
                      name: name,
                      url: u['avatarUrl'] as String?,
                      size: MAvatarSize.md),
                  title: Text(name,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('@${u['username'] ?? ''}',
                      style: const TextStyle(
                          color: MyloColors.textTertiary, fontSize: 12)),
                  onTap: () => _startDirectChat(u),
                );
              },
            ),
    );
  }

  Widget _buildConversationList(AsyncValue<dynamic> convs) {
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(conversationsProvider),
      child: convs.when(
        loading: () => ListView.builder(
          itemCount: 8,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              MLoadingSkeleton(width: 48, height: 48, borderRadius: 24),
              SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                MLoadingSkeleton(width: 120, height: 14),
                SizedBox(height: 6),
                MLoadingSkeleton(height: 12),
              ])),
            ]),
          ),
        ),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) => list.isEmpty
            ? const MEmptyState(
                icon: Icons.chat_bubble_outline,
                title: 'Belum ada percakapan',
                subtitle: 'Tap tombol edit untuk mulai chat')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 76),
                itemBuilder: (_, i) {
                  final c = list[i] as Map<String, dynamic>;
                  final lastMsg =
                      c['lastMessage'] as Map<String, dynamic>?;
                  final unread =
                      (c['unreadCount'] as num?)?.toInt() ?? 0;
                  return ListTile(
                    leading: MAvatar(
                        name: c['name'] ?? 'Chat',
                        url: c['avatarUrl'],
                        size: MAvatarSize.md),
                    title: Text(
                      c['name'] ?? 'Percakapan',
                      style: TextStyle(
                        fontWeight: unread > 0
                            ? FontWeight.bold
                            : FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      lastMsg?['content'] ?? 'Belum ada pesan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: unread > 0
                            ? null
                            : MyloColors.textSecondary,
                        fontWeight: unread > 0
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: unread > 0
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: MyloColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text('$unread',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold)),
                          )
                        : null,
                    onTap: () {
                      final name = (c['name'] ?? 'Chat').toString();
                      context.push(
                          '/home/chat/${c['id']}?name=${Uri.encodeComponent(name)}&avatar=${c['avatarUrl'] ?? ''}');
                    },
                  );
                },
              ),
      ),
    );
  }
}
