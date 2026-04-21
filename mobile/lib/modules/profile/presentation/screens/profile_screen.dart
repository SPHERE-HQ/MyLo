import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../app/theme.dart';
import '../../../../shared/widgets/m_button.dart';
import '../../../../shared/widgets/m_avatar.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
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
                  MAvatar(
                    name: user?.displayName ?? user?.username ?? 'U',
                    url: user?.avatarUrl,
                    size: MAvatarSize.xl,
                  ),
                  const SizedBox(height: MyloSpacing.lg),
                  Text(
                    user?.displayName ?? user?.username ?? '-',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user?.username ?? '-'}',
                    style: const TextStyle(color: MyloColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? '-',
                    style: const TextStyle(color: MyloColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: MyloSpacing.xxxl),
                  _MenuTile(icon: Icons.person_outline, label: 'Edit Profil', onTap: () {}),
                  _MenuTile(icon: Icons.notifications_outlined, label: 'Notifikasi', onTap: () {}),
                  _MenuTile(icon: Icons.lock_outline, label: 'Keamanan', onTap: () {}),
                  _MenuTile(icon: Icons.help_outline, label: 'Bantuan', onTap: () {}),
                  const SizedBox(height: MyloSpacing.xl),
                  MButton(
                    label: 'Keluar',
                    variant: MButtonVariant.danger,
                    size: MButtonSize.large,
                    onPressed: () async {
                      await ref.read(authStateProvider.notifier).logout();
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
  const _MenuTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: MyloColors.primary),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right, color: MyloColors.textTertiary),
      onTap: onTap,
    );
  }
}
