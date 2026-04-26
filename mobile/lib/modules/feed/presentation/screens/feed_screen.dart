import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/api/api_client.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_post_media.dart';

final feedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final res = await ref.read(dioProvider).get('/feed');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mylo',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        actions: [
          IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => context.go('/home/notifications')),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: MyloColors.primary,
        onPressed: () async {
          final result = await context.push('/home/feed/buat');
          if (result == true) ref.invalidate(feedProvider);
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(feedProvider),
        child: feed.when(
          loading: () => _buildSkeleton(),
          error: (e, _) => Center(child: Text('Gagal memuat: $e')),
          data: (posts) => posts.isEmpty
              ? ListView(children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_library_outlined,
                            size: 64, color: MyloColors.textTertiary),
                        SizedBox(height: 12),
                        Text('Belum ada post',
                            style:
                                TextStyle(color: MyloColors.textSecondary)),
                      ],
                    ),
                  ),
                ])
              : ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (ctx, i) => _PostCard(
                    post: posts[i],
                    onRefresh: () => ref.invalidate(feedProvider),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() => ListView.builder(
        itemCount: 3,
        itemBuilder: (_, __) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: const [
                MLoadingSkeleton(width: 40, height: 40, borderRadius: 20),
                SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  MLoadingSkeleton(width: 120, height: 13),
                  SizedBox(height: 6),
                  MLoadingSkeleton(width: 80, height: 11),
                ]),
              ]),
            ),
            const MLoadingSkeleton(
                width: double.infinity, height: 320, borderRadius: 0),
            const Padding(
              padding: EdgeInsets.all(12),
              child: MLoadingSkeleton(width: 200, height: 13),
            ),
          ],
        ),
      );
}

class _PostCard extends ConsumerStatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onRefresh;
  const _PostCard({required this.post, required this.onRefresh});
  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard>
    with SingleTickerProviderStateMixin {
  late bool _isLiked;
  late int _likesCount;
  bool _showHeart = false;
  late AnimationController _heartAnim;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post['liked'] == true;
    _likesCount = (widget.post['likesCount'] as num?)?.toInt() ?? 0;
    _heartAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
  }

  @override
  void dispose() {
    _heartAnim.dispose();
    super.dispose();
  }

  Future<void> _toggleLike() async {
    final id = widget.post['id'] as String;
    final newLiked = !_isLiked;
    setState(() {
      _isLiked = newLiked;
      _likesCount += newLiked ? 1 : -1;
    });
    try {
      final dio = ref.read(dioProvider);
      if (newLiked) {
        await dio.post('/feed/$id/like');
      } else {
        await dio.delete('/feed/$id/like');
      }
    } catch (_) {
      setState(() {
        _isLiked = !newLiked;
        _likesCount += newLiked ? -1 : 1;
      });
    }
  }

  void _doubleTapLike() {
    if (!_isLiked) _toggleLike();
    setState(() => _showHeart = true);
    _heartAnim.forward(from: 0).then((_) => setState(() => _showHeart = false));
  }

  @override
  Widget build(BuildContext context) {
    final postId = widget.post['id'] as String;
    final username = (widget.post['username'] ?? '').toString();
    final displayName = (widget.post['displayName'] ?? username).toString();
    final avatarUrl = widget.post['avatarUrl'] as String?;
    final mediaList = (widget.post['mediaUrls'] as List?) ?? const [];
    final mediaUrls = mediaList.map((e) => e.toString()).toList();
    final caption = widget.post['caption'] as String?;
    final createdAt = widget.post['createdAt'] != null
        ? DateTime.tryParse(widget.post['createdAt'].toString())
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            MAvatar(name: displayName, url: avatarUrl, size: MAvatarSize.md),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  if (createdAt != null)
                    Text(timeago.format(createdAt, locale: 'id'),
                        style: const TextStyle(
                            color: MyloColors.textTertiary, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.more_horiz, color: MyloColors.textTertiary),
          ]),
        ),
        if (mediaUrls.isNotEmpty)
          Stack(
            alignment: Alignment.center,
            children: [
              MPostMedia(
                urls: mediaUrls,
                height: 320,
                onDoubleTap: _doubleTapLike,
              ),
              if (_showHeart)
                ScaleTransition(
                  scale: Tween(begin: 0.5, end: 1.5).animate(CurvedAnimation(
                      parent: _heartAnim, curve: Curves.elasticOut)),
                  child: const Icon(Icons.favorite,
                      color: Colors.white, size: 80),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(
              icon: Icon(_isLiked ? Icons.favorite : Icons.favorite_border,
                  color: _isLiked ? Colors.red : null, size: 26),
              onPressed: _toggleLike,
              splashRadius: 20,
            ),
            Text('$_likesCount',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline, size: 24),
              splashRadius: 20,
              onPressed: () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => _CommentsSheet(postId: postId),
              ),
            ),
            Text('${widget.post['commentsCount'] ?? 0}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.bookmark_border, size: 24),
              splashRadius: 20,
              onPressed: () {},
            ),
          ]),
        ),
        if (caption != null && caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$username ',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
              TextSpan(
                  text: caption, style: const TextStyle(fontSize: 13)),
            ])),
          ),
        const SizedBox(height: 6),
        const Divider(height: 1),
      ],
    );
  }
}

class _CommentsSheet extends ConsumerStatefulWidget {
  final String postId;
  const _CommentsSheet({required this.postId});
  @override
  ConsumerState<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<_CommentsSheet> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true, _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await ref
          .read(dioProvider)
          .get('/feed/${widget.postId}/comments');
      setState(() {
        _comments = (res.data as List).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(dioProvider).post(
          '/feed/${widget.postId}/comments',
          data: {'content': text});
      _ctrl.clear();
      await _load();
    } catch (_) {} finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(
          color: isDark ? MyloColors.surfaceDark : Colors.white,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: MyloColors.textTertiary.withAlpha(128),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('Komentar',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _comments.isEmpty
                    ? const Center(
                        child: Text('Belum ada komentar',
                            style: TextStyle(
                                color: MyloColors.textSecondary)))
                    : ListView.builder(
                        controller: sc,
                        itemCount: _comments.length,
                        itemBuilder: (_, i) {
                          final c = _comments[i];
                          final name = (c['displayName'] ??
                                  c['username'] ??
                                  'U')
                              .toString();
                          return ListTile(
                            leading: MAvatar(
                                name: name,
                                url: c['avatarUrl'] as String?,
                                size: MAvatarSize.sm),
                            title: Text.rich(TextSpan(children: [
                              TextSpan(
                                  text: '${c['username'] ?? ''} ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              TextSpan(
                                  text:
                                      c['content']?.toString() ?? '',
                                  style: const TextStyle(fontSize: 13)),
                            ])),
                          );
                        },
                      ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12,
                MediaQuery.of(context).viewInsets.bottom + 12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  decoration: InputDecoration(
                    hintText: 'Tulis komentar...',
                    filled: true,
                    fillColor: isDark
                        ? MyloColors.surfaceSecondaryDark
                        : MyloColors.surfaceSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _sending
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      icon: const Icon(Icons.send,
                          color: MyloColors.primary),
                      onPressed: _send),
            ]),
          ),
        ]),
      ),
    );
  }
}
