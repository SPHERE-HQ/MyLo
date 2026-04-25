import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';

final userPostsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, uid) async {
  final res = await ref.read(dioProvider).get('/users/$uid/posts');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class UserPostsScreen extends ConsumerWidget {
  final String userId;
  final String? username;
  const UserPostsScreen({super.key, required this.userId, this.username});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(userPostsProvider(userId));
    return Scaffold(
      appBar: AppBar(title: Text(username == null ? 'Postingan' : 'Postingan ${username!}')),
      body: posts.when(
        loading: () => const Padding(padding: EdgeInsets.all(MyloSpacing.lg), child: MLoadingSkeleton(height: 200)),
        error: (e, _) => MEmptyState(icon: Icons.error_outline, title: 'Gagal', subtitle: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return const MEmptyState(icon: Icons.image_not_supported_outlined,
                title: 'Belum ada postingan', subtitle: 'Postingan akan muncul di sini');
          }
          return GridView.builder(
            padding: const EdgeInsets.all(2),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 2, mainAxisSpacing: 2,
            ),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              final media = (p['mediaUrls'] is List && (p['mediaUrls'] as List).isNotEmpty)
                  ? (p['mediaUrls'] as List).first.toString() : null;
              return GestureDetector(
                onTap: () => context.push('/home/feed/post/${p['id']}', extra: p),
                child: media == null
                    ? Container(color: MyloColors.surfaceSecondary,
                        child: const Center(child: Icon(Icons.text_snippet_outlined)))
                    : CachedNetworkImage(imageUrl: media, fit: BoxFit.cover),
              );
            },
          );
        },
      ),
    );
  }
}
