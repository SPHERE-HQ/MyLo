import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final postCommentsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
        (ref, id) async {
  final res = await ref.read(dioProvider).get('/feed/$id/comments');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class PostDetailScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> post;
  const PostDetailScreen({super.key, required this.post});
  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  bool _sending = false;
  late bool _isLiked;
  late int _likesCount;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.post['liked'] == true;
    _likesCount = (widget.post['likesCount'] as num?)?.toInt() ?? 0;
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
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
      if (newLiked) {
        await ref.read(dioProvider).post('/feed/$id/like');
      } else {
        await ref.read(dioProvider).delete('/feed/$id/like');
      }
    } catch (_) {
      setState(() {
        _isLiked = !newLiked;
        _likesCount += newLiked ? -1 : 1;
      });
    }
  }

  Future<void> _sendComment() async {
    final id = widget.post['id'] as String;
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(dioProvider)
          .post('/feed/$id/comments', data: {'content': text});
      _commentCtrl.clear();
      ref.invalidate(postCommentsProvider(id));
    } catch (_) {
      if (mounted) MSnackbar.error(context, 'Gagal kirim komentar');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final p = widget.post;
    final postId = p['id'] as String;
    final username = (p['username'] ?? '').toString();
    final displayName = (p['displayName'] ?? username).toString();
    final avatarUrl = p['avatarUrl'] as String?;
    final mediaUrls = p['mediaUrls'] as List?;
    final imageUrl =
        (mediaUrls != null && mediaUrls.isNotEmpty) ? mediaUrls.first.toString() : null;
    final caption = p['caption'] as String?;
    final createdAt = p['createdAt'] != null
        ? DateTime.tryParse(p['createdAt'].toString())
        : null;
    final comments = ref.watch(postCommentsProvider(postId));

    return Scaffold(
      appBar: AppBar(title: const Text('Postingan')),
      body: Column(children: [
        Expanded(
          child: ListView(children: [
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
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    if (createdAt != null)
                      Text(timeago.format(createdAt, locale: 'id'),
                          style: const TextStyle(
                              color: MyloColors.textTertiary, fontSize: 11)),
                  ]),
                ),
                const Icon(Icons.more_horiz, color: MyloColors.textTertiary),
              ]),
            ),
            if (imageUrl != null)
              CachedNetworkImage(
                imageUrl: imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => const MLoadingSkeleton(
                    width: double.infinity, height: 300, borderRadius: 0),
                errorWidget: (_, __, ___) => Container(
                  height: 300,
                  color: MyloColors.surfaceSecondary,
                  child: const Icon(Icons.broken_image,
                      color: MyloColors.textTertiary, size: 48),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                IconButton(
                  icon: Icon(
                    _isLiked ? Icons.favorite : Icons.favorite_border,
                    color: _isLiked ? Colors.red : null,
                    size: 26,
                  ),
                  onPressed: _toggleLike,
                ),
                Text('$_likesCount',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(width: 8),
                const Icon(Icons.chat_bubble_outline, size: 24),
                const SizedBox(width: 4),
                comments.when(
                  loading: () => const Text('...'),
                  error: (_, __) => const Text('0'),
                  data: (list) => Text('${list.length}',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.bookmark_border, size: 24),
                  onPressed: () {},
                ),
              ]),
            ),
            if (caption != null && caption.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: '$username ',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  TextSpan(
                      text: caption, style: const TextStyle(fontSize: 13)),
                ])),
              ),
            const Divider(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text('Komentar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            comments.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (e, _) => const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Gagal memuat komentar',
                    style: TextStyle(color: MyloColors.textSecondary)),
              ),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                          child: Text(
                              'Belum ada komentar. Jadilah yang pertama!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: MyloColors.textSecondary))))
                  : Column(
                      children: list.map((c) {
                        final name =
                            (c['displayName'] ?? c['username'] ?? 'U')
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
                                text: c['content']?.toString() ?? '',
                                style: const TextStyle(fontSize: 13)),
                          ])),
                          subtitle: c['createdAt'] != null
                              ? Text(
                                  timeago.format(
                                      DateTime.parse(c['createdAt']),
                                      locale: 'id'),
                                  style: const TextStyle(fontSize: 11))
                              : null,
                        );
                      }).toList(),
                    ),
            ),
            const SizedBox(height: 80),
          ]),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(
                12, 8, 12, MediaQuery.of(context).viewInsets.bottom + 8),
            decoration: BoxDecoration(
              color: isDark ? MyloColors.surfaceDark : MyloColors.surface,
              border: const Border(
                  top: BorderSide(color: MyloColors.border, width: 0.5)),
            ),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  decoration: InputDecoration(
                    hintText: 'Tulis komentar...',
                    filled: true,
                    fillColor: isDark
                        ? MyloColors.surfaceSecondaryDark
                        : MyloColors.surfaceSecondary,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(MyloRadius.full),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendComment(),
                ),
              ),
              const SizedBox(width: 8),
              _sending
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      icon:
                          const Icon(Icons.send, color: MyloColors.primary),
                      onPressed: _sendComment,
                    ),
            ]),
          ),
        ),
      ]),
    );
  }
}
