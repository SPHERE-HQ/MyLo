import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/theme.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../shared/widgets/m_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        children: [
          _section('Akun'),
          _tile(context, Icons.person_outline, 'Profil', () => context.push('/home/profile')),
          _tile(context, Icons.lock_outline, 'Ganti Password', () => context.push('/home/settings/password')),
          _tile(context, Icons.email_outlined, 'Privasi & Keamanan', () => context.push('/home/settings/privacy')),
          _section('Aplikasi'),
          _tile(context, Icons.notifications_outlined, 'Notifikasi', () => context.push('/home/notifications')),
          _tile(context, Icons.palette_outlined, 'Tema', () {}),
          _tile(context, Icons.language_outlined, 'Bahasa', () {}),
          _section('Lainnya'),
          _tile(context, Icons.help_outline, 'Bantuan', () => context.push('/home/settings/help')),
          _tile(context, Icons.info_outline, 'Tentang Mylo', () => context.push('/home/settings/about')),
          const SizedBox(height: MyloSpacing.lg),
          ListTile(
            leading: const Icon(Icons.logout, color: MyloColors.danger),
            title: const Text('Keluar', style: TextStyle(color: MyloColors.danger)),
            onTap: () async {
              final ok = await MDialog.confirm(context: context,
                  title: 'Keluar?', message: 'Kamu perlu login ulang nanti.', destructive: true);
              if (ok == true) {
                await ref.read(authStateProvider.notifier).logout();
                if (context.mounted) context.go('/auth/login');
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.sm),
    child: Text(t.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: MyloColors.textSecondary, letterSpacing: 0.8)),
  );

  Widget _tile(BuildContext c, IconData icon, String label, VoidCallback onTap) =>
      ListTile(leading: Icon(icon), title: Text(label),
          trailing: const Icon(Icons.chevron_right), onTap: onTap);
}
