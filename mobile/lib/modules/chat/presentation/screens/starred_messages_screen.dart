import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_empty_state.dart';

/// Provider untuk daftar id pesan yang dibintangi dalam suatu percakapan.
/// Disimpan lokal di SharedPreferences (key per-conversation).
final starredIdsProvider =
    FutureProvider.family<Set<String>, String>((ref, convId) async {
  final p = await SharedPreferences.getInstance();
  final ids = p.getStringList('chat.starred.$convId') ?? const <String>[];
  return ids.toSet();
});

Future<void> setStarred(
    String convId, String messageId, bool starred) async {
  final p = await SharedPreferences.getInstance();
  final key = 'chat.starred.$convId';
  final cur = (p.getStringList(key) ?? const <String>[]).toSet();
  if (starred) {
    cur.add(messageId);
  } else {
    cur.remove(messageId);
  }
  await p.setStringList(key, cur.toList());
}

class StarredMessagesScreen extends ConsumerWidget {
  final String conversationId;
  const StarredMessagesScreen({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final starredAsync = ref.watch(starredIdsProvider(conversationId));
    return Scaffold(
      appBar: AppBar(title: const Text('Pesan Berbintang')),
      body: starredAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat: $e')),
        data: (ids) {
          if (ids.isEmpty) {
            return const MEmptyState(
              icon: Icons.star_border,
              title: 'Belum ada pesan berbintang',
              subtitle: 'Tekan lama pesan dan pilih Bintangi',
            );
          }
          return FutureBuilder(
            future: ref.read(dioProvider).get(
                '/chat/conversations/$conversationId/messages'),
            builder: (_, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final raw = snap.data?.data;
              List<dynamic> all = raw is List
                  ? raw
                  : (raw is Map && raw['messages'] is List
                      ? raw['messages'] as List
                      : const []);
              final filtered = all
                  .whereType<Map>()
                  .map((m) => Map<String, dynamic>.from(m))
                  .where((m) => ids.contains(m['id']?.toString()))
                  .toList();
              if (filtered.isEmpty) {
                return const MEmptyState(
                  icon: Icons.star_border,
                  title: 'Pesan berbintang sudah tidak tersedia',
                );
              }
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = filtered[i];
                  final content =
                      m['content']?.toString() ?? '[Media]';
                  final ts = m['createdAt']?.toString() ?? '';
                  return ListTile(
                    leading: const Icon(Icons.star, color: MyloColors.warning),
                    title: Text(content,
                        maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text(ts,
                        style: const TextStyle(
                            fontSize: 11, color: MyloColors.textTertiary)),
                    trailing: IconButton(
                      icon: const Icon(Icons.star, color: MyloColors.warning),
                      onPressed: () async {
                        await setStarred(
                            conversationId, m['id'].toString(), false);
                        ref.invalidate(starredIdsProvider(conversationId));
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
