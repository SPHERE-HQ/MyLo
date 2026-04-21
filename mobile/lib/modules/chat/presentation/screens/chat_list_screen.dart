import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../../../core/api/api_client.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';

final conversationsProvider = FutureProvider.autoDispose((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get('/chat/conversations');
  return res.data as List;
});

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convs = ref.watch(conversationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mylo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () {}),
        ],
      ),
      body: convs.when(
        loading: () => ListView.builder(
          itemCount: 8,
          itemBuilder: (_, __) => const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              MLoadingSkeleton(width: 48, height: 48, borderRadius: 24),
              SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                MLoadingSkeleton(width: 120, height: 14),
                SizedBox(height: 6),
                MLoadingSkeleton(height: 12),
              ])),
            ]),
          ),
        ),
        error: (e, _) => Center(child: Text('$e')),
        data: (convs) => convs.isEmpty
            ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.chat_bubble_outline, size: 64, color: MyloColors.textTertiary),
                SizedBox(height: 12),
                Text('Belum ada percakapan', style: TextStyle(color: MyloColors.textSecondary)),
              ]))
            : ListView.separated(
                itemCount: convs.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                itemBuilder: (_, i) {
                  final c = convs[i] as Map<String, dynamic>;
                  final lastMsg = c['lastMessage'] as Map<String, dynamic>?;
                  return ListTile(
                    leading: MAvatar(name: c['name'] ?? 'Chat', url: c['avatarUrl']),
                    title: Text(c['name'] ?? 'Percakapan', fontWeight: FontWeight.w600),
                    subtitle: Text(lastMsg?['content'] ?? 'Belum ada pesan', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: MyloColors.textSecondary)),
                    onTap: () => context.push('/home/chat/${c['id']}'),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: MyloColors.primary,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }
}
