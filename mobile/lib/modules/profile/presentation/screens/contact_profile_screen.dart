import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/api/api_client.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_empty_state.dart';
import '../../../../shared/widgets/m_loading_skeleton.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final userProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
        (ref, id) async {
  final res = await ref.read(dioProvider).get('/users/$id');
  return res.data as Map<String, dynamic>;
});

class ContactProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const ContactProfileScreen({super.key, required this.userId});
  @override
  ConsumerState<ContactProfileScreen> createState() =>
      _ContactProfileScreenState();
}

class _ContactProfileScreenState
    extends ConsumerState<ContactProfileScreen> {
  bool _followLoading = false;

  Future<void> _toggleFollow(
      bool isFollowing) async {
    setState(() => _followLoading = true);
    try {
      if (isFollowing) {
        await ref.read(dioProvider).delete('/users/${widget.userId}/follow');
      } else {
        await ref.read(dioProvider).post('/users/${widget.userId}/follow');
      }
      ref.invalidate(userProfileProvider(widget.userId));
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  Future<void> _startChat(Map<String, dynamic> user) async {
    try {
      final res = await ref.read(dioProvider).post('/chat/conversations', data: {
        'participantIds': [widget.userId],
      });
      final id = (res.data as Map)['id'] as String?;
      if (mounted && id != null) {
        final name = (user['displayName'] ?? user['username'] ?? 'Chat').toString();
        context.push('/home/chat/$id?name=${Uri.encodeComponent(name)}');
      }
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal buka chat: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider(widget.userId));
    return Scaffold(
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            MEmptyState(icon: Icons.error_outline, title: 'Gagal memuat', subtitle: '$e'),
        data: (u) {
          final name = (u['displayName'] ?? u['username'] ?? 'User').toString();
          final username = (u['username'] ?? '').toString();
          final avatarUrl = u['avatarUrl'] as String?;
          final coverUrl = u['coverUrl'] as String?;
          final bio = u['bio'] as String?;
          final isFollowing = u['isFollowing'] as bool? ?? false;
          final followersCount = (u['followersCount'] as num?)?.toInt() ?? 0;
          final followingCount = (u['followingCount'] as num?)?.toInt() ?? 0;
          final postsCount = (u['postsCount'] as num?)?.toInt() ?? 0;

          return CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              flexibleSpace: FlexibleSpaceBar(
                background: coverUrl != null
                    ? CachedNetworkImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover)
                    : Container(
                        color: MyloColors.primary.withOpacity(0.7)),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(children: [
                Transform.translate(
                  offset: const Offset(0, -44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.white, width: 3),
                        ),
                        child: MAvatar(
                            name: name,
                            url: avatarUrl,
                            size: MAvatarSize.xxl),
                      ),
                      const Spacer(),
                      MButton(
                        label: isFollowing ? 'Berhenti Ikuti' : 'Ikuti',
                        variant: isFollowing
                            ? MButtonVariant.secondary
                            : MButtonVariant.primary,
                        isLoading: _followLoading,
                        onPressed: () => _toggleFollow(isFollowing),
                        size: MButtonSize.small,
                      ),
                      const SizedBox(width: 8),
                      MButton(
                        label: 'Chat',
                        variant: MButtonVariant.secondary,
                        onPressed: () => _startChat(u),
                        size: MButtonSize.small,
                      ),
                    ]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('@$username',
                        style: const TextStyle(
                            color: MyloColors.textSecondary, fontSize: 14)),
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(bio, style: const TextStyle(fontSize: 14)),
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      _StatChip(count: postsCount, label: 'Postingan'),
                      const SizedBox(width: 24),
                      _StatChip(count: followersCount, label: 'Pengikut'),
                      const SizedBox(width: 24),
                      _StatChip(count: followingCount, label: 'Mengikuti'),
                    ]),
                    const SizedBox(height: 24),
                  ]),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final int count;
  final String label;
  const _StatChip({required this.count, required this.label});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text('$count',
          style: const TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold)),
      Text(label,
          style: const TextStyle(
              fontSize: 12, color: MyloColors.textSecondary)),
    ]);
  }
}
