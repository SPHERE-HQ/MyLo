import 'dart:io';
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:go_router/go_router.dart';
  import 'package:image_picker/image_picker.dart';
  import 'package:supabase_flutter/supabase_flutter.dart';
  import 'package:uuid/uuid.dart';
  import '../../../../core/api/api_client.dart';
  import '../../../../core/auth/auth_provider.dart';
  import '../../../../app/theme.dart';
  import '../../../../shared/widgets/m_avatar.dart';
  import '../../../../shared/widgets/m_button.dart';
  import '../../../../shared/widgets/m_snackbar.dart';

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
        await Supabase.instance.client.storage
            .from('avatars')
            .uploadBinary(name, bytes,
                fileOptions:
                    FileOptions(contentType: 'image/$ext', upsert: true));
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

    @override
    Widget build(BuildContext context) {
      final auth = ref.watch(authStateProvider);
      final user = auth.value;

      return Scaffold(
        appBar: AppBar(
          title: const Text('Profil'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => context.go('/home/settings'),
            ),
          ],
        ),
        body: auth.isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(MyloSpacing.xl),
                child: Column(
                  children: [
                    const SizedBox(height: MyloSpacing.xl),
                    GestureDetector(
                      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                      child: Stack(
                        children: [
                          MAvatar(
                            name:
                                user?.displayName ?? user?.username ?? 'U',
                            url: user?.avatarUrl,
                            size: MAvatarSize.xxl,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: MyloColors.primary,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                              ),
                              child: _uploadingAvatar
                                  ? const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Icon(Icons.camera_alt,
                                      color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: MyloSpacing.lg),
                    Text(
                      user?.displayName ?? user?.username ?? '-',
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('@${user?.username ?? '-'}',
                        style: const TextStyle(
                            color: MyloColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(user?.email ?? '-',
                        style: const TextStyle(
                            color: MyloColors.textSecondary,
                            fontSize: 13)),
                    const SizedBox(height: MyloSpacing.xxxl),
                    _MenuTile(
                      icon: Icons.edit_outlined,
                      label: 'Edit Profil',
                      onTap: () => context.go('/home/profile/edit'),
                    ),
                    _MenuTile(
                      icon: Icons.notifications_outlined,
                      label: 'Notifikasi',
                      onTap: () => context.go('/home/notifications'),
                    ),
                    _MenuTile(
                      icon: Icons.lock_outline,
                      label: 'Ganti Password',
                      onTap: () => context.go('/home/settings/password'),
                    ),
                    _MenuTile(
                      icon: Icons.help_outline,
                      label: 'Bantuan',
                      onTap: () => context.go('/home/settings/help'),
                    ),
                    const SizedBox(height: MyloSpacing.xl),
                    MButton(
                      label: 'Keluar',
                      variant: MButtonVariant.danger,
                      size: MButtonSize.large,
                      onPressed: () async {
                        await ref
                            .read(authStateProvider.notifier)
                            .logout();
                        if (context.mounted) context.go('/auth/login');
                      },
                    ),
                  ],
                ),
              ),
      );
    }
  }

  class _MenuTile extends StatelessWidget {
    final IconData icon;
    final String label;
    final VoidCallback onTap;
    const _MenuTile(
        {required this.icon, required this.label, required this.onTap});

    @override
    Widget build(BuildContext context) {
      return ListTile(
        leading: Icon(icon, color: MyloColors.primary),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right,
            color: MyloColors.textTertiary),
        onTap: onTap,
      );
    }
  }
  