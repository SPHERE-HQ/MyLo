import 'package:cached_network_image/cached_network_image.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import '../../../../app/theme.dart';
  import '../../../../core/api/api_client.dart';
  import '../../../../shared/widgets/m_avatar.dart';
  import '../../../../shared/widgets/m_empty_state.dart';
  import '../../../../shared/widgets/m_loading_skeleton.dart';

  final _exploreQueryProvider = StateProvider<String>((ref) => '');

  final _explorePostsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
    final q = ref.watch(_exploreQueryProvider);
    final res = await ref.read(dioProvider).get('/feed', queryParameters: q.isNotEmpty ? {'q': q} : null);
    return (res.data as List).cast<Map<String, dynamic>>();
  });

  class ExploreScreen extends ConsumerStatefulWidget {
    const ExploreScreen({super.key});
    @override
    ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
  }

  class _ExploreScreenState extends ConsumerState<ExploreScreen> {
    final _searchCtrl = TextEditingController();

    @override
    void dispose() {
      _searchCtrl.dispose();
      super.dispose();
    }

    void _onSearch(String val) {
      ref.read(_exploreQueryProvider.notifier).state = val.trim();
    }

    @override
    Widget build(BuildContext context) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final posts = ref.watch(_explorePostsProvider);

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
        body: posts.when(
          loading: () => ListView.builder(
            padding: const EdgeInsets.all(MyloSpacing.lg),
            itemCount: 8,
            itemBuilder: (_, __) => const Padding(
              padding: EdgeInsets.only(bottom: MyloSpacing.md),
              child: MLoadingSkeleton(height: 100, borderRadius: MyloRadius.md),
            ),
          ),
          error: (e, _) => MEmptyState(
            icon: Icons.wifi_off_outlined,
            title: 'Gagal memuat',
            subtitle: e.toString(),
            action: TextButton(
              onPressed: () => ref.invalidate(_explorePostsProvider),
              child: const Text('Coba lagi'),
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return MEmptyState(
                icon: Icons.explore_outlined,
                title: _searchCtrl.text.isEmpty
                    ? 'Belum ada postingan'
                    : 'Tidak ada hasil untuk "${_searchCtrl.text}"',
                subtitle: _searchCtrl.text.isEmpty
                    ? 'Jadilah yang pertama memposting!'
                    : 'Coba kata kunci lain',
              );
            }
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(_explorePostsProvider),
              child: GridView.builder(
                padding: const EdgeInsets.all(MyloSpacing.sm),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: MyloSpacing.sm,
                  mainAxisSpacing: MyloSpacing.sm,
                  childAspectRatio: 0.85,
                ),
                itemCount: items.length,
                itemBuilder: (ctx, i) => _PostCard(post: items[i]),
              ),
            );
          },
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
      final imageUrl = post['imageUrl'] as String?;
      final caption = (post['caption'] ?? '').toString();
      final author = (post['author'] as Map<String, dynamic>?) ?? {};
      final likes = (post['likesCount'] ?? post['likes_count'] ?? 0) as int;

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
                    size: 22,
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
  