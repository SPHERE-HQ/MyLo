import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import 'package:uuid/uuid.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_avatar.dart';
import '../../../../shared/widgets/m_post_media.dart';
import '../../../../shared/widgets/m_snackbar.dart';

final myPostsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final auth = ref.watch(authStateProvider).value;
  if (auth == null) return [];
  final res = await ref.read(dioProvider).get('/users/${auth.id}/posts');
  return (res.data as List).cast<Map<String, dynamic>>();
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _uploadingAvatar = false;

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (picked == null) return;

    setState(() => _uploadingAvatar = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.path.split('.').last.toLowerCase();
      final name = 'avatars/${const Uuid().v4()}.$ext';
      await Supabase.instance.client.storage.from('avatars').uploadBinary(
            name,
            bytes,
            fileOptions:
                FileOptions(contentType: 'image/$ext', upsert: true),
          );
      final url = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(name);

      await ref
          .read(dioProvider)
          .put('/auth/profile', data: {'avatarUrl': url});
      await ref.read(authStateProvider.notifier).refreshProfile();

      if (mounted) MSnackbar.success(context, 'Foto profil diperbarui');
    } catch (e) {
      if (mounted) MSnackbar.error(context, 'Gagal upload foto: $e');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _showSettingsMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: MyloColors.textTertiary.withAlpha(128),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _menuItem(Icons.settings_outlined, 'Pengaturan',
                () => context.go('/home/settings')),
            _menuItem(Icons.lock_outline, 'Ganti Password',
                () => context.go('/home/settings/password')),
            _menuItem(Icons.shield_outlined, 'Privasi',
                () => context.go('/home/settings/privacy')),
            _menuItem(Icons.notifications_outlined, 'Notifikasi',
                () => context.go('/home/settings/notifications')),
            _menuItem(Icons.color_lens_outlined, 'Tema',
                () => context.go('/home/settings/theme')),
            _menuItem(Icons.devices_other_outlined, 'Sesi Aktif',
                () => context.go('/home/settings/sessions')),
            _menuItem(Icons.fingerprint, 'Biometrik',
                () => context.go('/home/settings/biometric')),
            _menuItem(Icons.verified_user_outlined, '2FA',
                () => context.go('/home/settings/2fa')),
            _menuItem(Icons.download_outlined, 'Ekspor Data',
                () => context.go('/home/settings/export')),
            _menuItem(Icons.help_outline, 'Bantuan',
                () => context.go('/home/settings/help')),
            _menuItem(Icons.info_outline, 'Tentang',
                () => context.go('/home/settings/about')),
            const Divider(),
            _menuItem(
              Icons.logout,
              'Keluar',
              () async {
                Navigator.pop(context);
                await ref.read(authStateProvider.notifier).logout();
                if (mounted) context.go('/auth/login');
              },
              danger: true,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? MyloColors.danger : MyloColors.primary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label,
          style: TextStyle(color: danger ? MyloColors.danger : null)),
      onTap: () {
        if (!danger) Navigator.pop(context);
        onTap();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.value;
    final posts = ref.watch(myPostsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('@${user?.username ?? '-'}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Pengaturan',
            onPressed: _showSettingsMenu,
          ),
        ],
      ),
      body: auth.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await ref.read(authStateProvider.notifier).refreshProfile();
                ref.invalidate(myPostsProvider);
              },
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildHeader(user),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabHeaderDelegate(),
                  ),
                  posts.when(
                    loading: () => const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => SliverFillRemaining(
                      child: Center(child: Text('Gagal: $e')),
                    ),
                    data: (list) => list.isEmpty
                        ? const SliverFillRemaining(
                            hasScrollBody: false,
                            child: Padding(
                              padding: EdgeInsets.all(40),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.camera_alt_outlined,
                                      size: 64,
                                      color: MyloColors.textTertiary),
                                  SizedBox(height: 12),
                                  Text('Belum ada postingan',
                                      style: TextStyle(
                                          color:
                                              MyloColors.textSecondary)),
                                  SizedBox(height: 4),
                                  Text(
                                    'Postingan kamu akan muncul di sini',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: MyloColors.textTertiary),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SliverPadding(
                            padding: const EdgeInsets.all(2),
                            sliver: SliverGrid(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (_, i) => _PostThumb(post: list[i]),
                                childCount: list.length,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(AuthUser? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                child: Stack(
                  children: [
                    MAvatar(
                      name: user?.displayName ?? user?.username ?? 'U',
                      url: user?.avatarUrl,
                      size: MAvatarSize.xxl,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: MyloColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white, width: 2),
                        ),
                        child: _uploadingAvatar
                            ? const Padding(
                                padding: EdgeInsets.all(5),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt,
                                color: Colors.white, size: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('${user?.postsCount ?? 0}', 'Postingan'),
                    _stat('${user?.followersCount ?? 0}', 'Pengikut'),
                    _stat('${user?.followingCount ?? 0}', 'Mengikuti'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(user?.displayName ?? user?.username ?? '-',
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700)),
          if ((user?.bio ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(user!.bio!,
                style: const TextStyle(fontSize: 13, height: 1.3)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () => context.go('/home/profile/edit'),
              child: const Text('Edit Profil',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: MyloColors.textSecondary)),
      ],
    );
  }
}

class _PostThumb extends StatelessWidget {
  final Map<String, dynamic> post;
  const _PostThumb({required this.post});

  @override
  Widget build(BuildContext context) {
    final mediaList = (post['mediaUrls'] as List?) ?? const [];
    final urls = mediaList.map((e) => e.toString()).toList();
    final first = urls.isNotEmpty ? urls.first : null;
    final isMulti = urls.length > 1;
    final isVideo = first != null && isVideoUrl(first);

    return GestureDetector(
      onTap: () => context.push('/home/feed/post/${post['id']}',
          extra: post),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (first != null && !isVideo)
            CachedNetworkImage(
              imageUrl: first,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                color: MyloColors.surfaceSecondary,
                child: const Icon(Icons.broken_image,
                    color: MyloColors.textTertiary),
              ),
              placeholder: (_, __) =>
                  Container(color: MyloColors.surfaceSecondary),
            )
          else if (first != null && isVideo)
            Container(
              color: Colors.black,
              child: const Center(
                child: Icon(Icons.play_circle_outline,
                    color: Colors.white, size: 32),
              ),
            )
          else
            Container(
              color: MyloColors.surfaceSecondary,
              padding: const EdgeInsets.all(8),
              child: Center(
                child: Text(
                  (post['caption'] ?? '').toString(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: MyloColors.textSecondary),
                ),
              ),
            ),
          if (isMulti)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.collections,
                  color: Colors.white, size: 16, shadows: [
                Shadow(blurRadius: 4, color: Colors.black54),
              ]),
            ),
          if (isVideo && !isMulti)
            const Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.play_arrow,
                  color: Colors.white, size: 18, shadows: [
                Shadow(blurRadius: 4, color: Colors.black54),
              ]),
            ),
        ],
      ),
    );
  }
}

class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  @override
  double get minExtent => 44;
  @override
  double get maxExtent => 44;
  @override
  bool shouldRebuild(_) => false;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? MyloColors.surfaceDark : Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: MyloColors.primary, width: 2)),
              ),
              child: const Icon(Icons.grid_on, size: 22),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: Colors.transparent, width: 2)),
              ),
              child: const Icon(Icons.bookmark_border,
                  size: 22, color: MyloColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
