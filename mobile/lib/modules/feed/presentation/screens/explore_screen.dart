import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final _exploreQueryProvider = StateProvider<String>((ref) => '');

final _explorePostsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final q = ref.watch(_exploreQueryProvider);
  final res = await ref
      .read(dioProvider)
      .get('/feed', queryParameters: q.isNotEmpty ? {'q': q} : null);
  return (res.data as List).cast<Map<String, dynamic>>();
});

final _exploreUsersProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final q = ref.watch(_exploreQueryProvider);
  if (q.isEmpty) return const [];
  final res = await ref
      .read(dioProvider)
      .get('/users', queryParameters: {'q': q});
  return (res.data as List).cast<Map<String, dynamic>>();
});

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final _searchCtrl = TextEditingController();
  bool _startingChat = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String val) {
    ref.read(_exploreQueryProvider.notifier).state = val.trim();
  }

  Future<void> _openChatWithUser(Map<String, dynamic> user) async {
    if (_startingChat) return;
    setState(() => _startingChat = true);
    try {
      final res = await ref.read(dioProvider).post(
        '/chat/conversations',
        data: {'type': 'private', 'memberIds': [user['id']]},
      );
      final id = (res.data as Map)['id'] as String?;
      if (mounted && id != null) {
        final name = (user['displayName'] ?? user['username'] ?? 'Chat').toString();
        context.push(
          '/home/chat/$id?name=${Uri.encodeComponent(name)}&avatar=${user['avatarUrl'] ?? ''}',
        );
      }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal membuka chat: $e');
    } finally {
      if (mounted) setState(() => _startingChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final posts = ref.watch(_explorePostsProvider);
    final users = ref.watch(_exploreUsersProvider);
    final query = ref.watch(_exploreQueryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                MyloSpacing.lg, 0, MyloSpacing.lg, MyloSpacing.sm),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Cari postingan, pengguna...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearch('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MyloRadius.full),
                  borderSide: BorderSide.none,
                ),
                fillColor: isDark
                    ? MyloColors.surfaceSecondaryDark
                    : MyloColors.surfaceSecondary,
                filled: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_explorePostsProvider);
          ref.invalidate(_exploreUsersProvider);
        },
        child: CustomScrollView(
          slivers: [
            if (query.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      MyloSpacing.lg, MyloSpacing.md, MyloSpacing.lg, MyloSpacing.xs),
                  child: Text(
                    'Pengguna',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              users.when(
                loading: () => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(MyloSpacing.lg),
                    child: MLoadingSkeleton(height: 56, borderRadius: MyloRadius.md),
                  ),
                ),
                error: (e, _) => SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(MyloSpacing.lg),
                    child: Text('Gagal memuat pengguna: $e',
                        style: const TextStyle(color: MyloColors.textTertiary)),
                  ),
                ),
                data: (list) {
                  if (list.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            MyloSpacing.lg, 0, MyloSpacing.lg, MyloSpacing.md),
                        child: Text(
                          'Tidak ada pengguna untuk "$query"',
                          style: const TextStyle(color: MyloColors.textTertiary),
                        ),
                      ),
                    );
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final u = list[i];
                        return ListTile(
                          leading: MAvatar(
                            url: u['avatarUrl'] as String?,
                            name: (u['displayName'] ?? u['username'] ?? 'U').toString(),
                            size: MAvatarSize.sm,
                          ),
                          title: Text(
                            (u['displayName'] ?? u['username'] ?? '').toString(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('@${u['username'] ?? ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.chat_bubble_outline, size: 20),
                            onPressed: () => _openChatWithUser(u),
                          ),
                          onTap: () => _openChatWithUser(u),
                        );
                      },
                      childCount: list.length,
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: Divider(height: 24)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      MyloSpacing.lg, 0, MyloSpacing.lg, MyloSpacing.xs),
                  child: Text(
                    'Postingan',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
            posts.when(
              loading: () => SliverPadding(
                padding: const EdgeInsets.all(MyloSpacing.lg),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, __) => const Padding(
                      padding: EdgeInsets.only(bottom: MyloSpacing.md),
                      child: MLoadingSkeleton(height: 100, borderRadius: MyloRadius.md),
                    ),
                    childCount: 6,
                  ),
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                child: MEmptyState(
                  icon: Icons.wifi_off_outlined,
                  title: 'Gagal memuat',
                  subtitle: e.toString(),
                  actionLabel: 'Coba lagi',
                  onAction: () => ref.invalidate(_explorePostsProvider),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return SliverFillRemaining(
                    child: MEmptyState(
                      icon: Icons.explore_outlined,
                      title: query.isEmpty
                          ? 'Belum ada postingan'
                          : 'Tidak ada hasil untuk "$query"',
                      subtitle: query.isEmpty
                          ? 'Jadilah yang pertama memposting!'
                          : 'Coba kata kunci lain',
                    ),
                  );
                }
                return SliverPadding(
                  padding: const EdgeInsets.all(MyloSpacing.sm),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: MyloSpacing.sm,
                      mainAxisSpacing: MyloSpacing.sm,
                      childAspectRatio: 0.85,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _PostCard(post: items[i]),
                      childCount: items.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? imageUrl = post['imageUrl'] as String?;
    if (imageUrl == null || imageUrl.isEmpty) {
      final media = post['mediaUrls'];
      if (media is List && media.isNotEmpty) {
        imageUrl = media.first?.toString();
      }
    }
    final caption = (post['caption'] ?? '').toString();
    final author = (post['author'] as Map<String, dynamic>?) ??
        {
          'username': post['username'],
          'displayName': post['displayName'],
          'avatarUrl': post['avatarUrl'],
        };
    final likes = ((post['likesCount'] ?? post['likes_count'] ?? 0) as num).toInt();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? MyloColors.surfaceDark : MyloColors.surface,
        borderRadius: BorderRadius.circular(MyloRadius.md),
        border: Border.all(
          color: isDark ? MyloColors.borderDark : MyloColors.border,
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty)
            Expanded(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                placeholder: (_, __) => Container(
                    color: isDark
                        ? MyloColors.surfaceSecondaryDark
                        : MyloColors.surfaceSecondary),
                errorWidget: (_, __, ___) => Container(
                  color: isDark
                      ? MyloColors.surfaceSecondaryDark
                      : MyloColors.surfaceSecondary,
                  child: const Icon(Icons.broken_image_outlined,
                      color: MyloColors.textTertiary),
                ),
              ),
            )
          else
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(MyloSpacing.md),
                color: isDark
                    ? MyloColors.surfaceSecondaryDark
                    : MyloColors.surfaceSecondary,
                child: Text(
                  caption,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? MyloColors.textSecondaryDark
                        : MyloColors.textSecondary,
                  ),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(MyloSpacing.sm),
            child: Row(
              children: [
                MAvatar(
                  url: author['avatarUrl'] as String?,
                  name: (author['displayName'] ?? author['username'] ?? 'U').toString(),
                  size: MAvatarSize.xs,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (author['displayName'] ?? author['username'] ?? '').toString(),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.favorite_outline,
                    size: 12, color: MyloColors.textTertiary),
                const SizedBox(width: 2),
                Text('$likes',
                    style: const TextStyle(
                        fontSize: 11, color: MyloColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
