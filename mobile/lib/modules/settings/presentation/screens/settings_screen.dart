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
          _section('AKUN'),
          _tile(context, Icons.person_outline, 'Profil', () => context.push('/home/profile')),
          _tile(context, Icons.lock_outline, 'Ganti Password', () => context.push('/home/settings/password')),
          _tile(context, Icons.security_outlined, '2-Step Verification', () => context.push('/home/settings/2fa')),
          _tile(context, Icons.fingerprint, 'Login Biometrik', () => context.push('/home/settings/biometric')),
          _tile(context, Icons.devices_other, 'Sesi Login Aktif', () => context.push('/home/settings/sessions')),
          _tile(context, Icons.shield_outlined, 'Privasi', () => context.push('/home/settings/privacy')),
          _section('APLIKASI'),
          _tile(context, Icons.notifications_outlined, 'Notifikasi', () => context.push('/home/settings/notifications')),
          _tile(context, Icons.palette_outlined, 'Tema & Tampilan', () => context.push('/home/settings/theme')),
          _tile(context, Icons.storage_outlined, 'Penyimpanan', () => context.push('/home/storage')),
          _section('DATA'),
          _tile(context, Icons.download_outlined, 'Ekspor Data Saya', () => context.push('/home/settings/export')),
          _tile(context, Icons.delete_outline, 'Hapus Akun', () => context.push('/home/settings/delete'),
              danger: true),
          _section('LAINNYA'),
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
          const SizedBox(height: MyloSpacing.xxl),
        ],
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.lg, MyloSpacing.sm),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: MyloColors.textSecondary, letterSpacing: 0.8)),
      );

  Widget _tile(BuildContext c, IconData icon, String label, VoidCallback onTap, {bool danger = false}) =>
      ListTile(
        leading: Icon(icon, color: danger ? MyloColors.danger : null),
        title: Text(label, style: TextStyle(color: danger ? MyloColors.danger : null)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}
