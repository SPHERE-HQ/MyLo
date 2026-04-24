import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../core/auth/auth_provider.dart';
import 'm_avatar.dart';

class MSideDrawer extends ConsumerWidget {
  const MSideDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    return Drawer(
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [MyloColors.primary, MyloColors.secondary],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
            ),
            child: Row(children: [
              MAvatar(name: user?.displayName ?? user?.username ?? '?',
                  url: user?.avatarUrl, size: MAvatarSize.lg),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user?.displayName ?? user?.username ?? 'Pengguna',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 18, fontWeight: FontWeight.bold),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('@${user?.username ?? '?'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _tile(context, Icons.email_outlined, 'Email', '/home/email'),
                _tile(context, Icons.groups_outlined, 'Komunitas', '/home/community'),
                _tile(context, Icons.travel_explore_outlined, 'Browser', '/home/browser'),
                _tile(context, Icons.cloud_outlined, 'Penyimpanan', '/home/storage'),
                _tile(context, Icons.auto_awesome, 'Mylo AI', '/home/ai'),
                _tile(context, Icons.notifications_outlined, 'Notifikasi', '/home/notifications'),
                const Divider(),
                _tile(context, Icons.person_outline, 'Profil', '/home/profile'),
                _tile(context, Icons.settings_outlined, 'Pengaturan', '/home/settings'),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: MyloColors.danger),
            title: const Text('Keluar', style: TextStyle(color: MyloColors.danger)),
            onTap: () async {
              await ref.read(authStateProvider.notifier).logout();
              if (context.mounted) context.go('/auth/login');
            },
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext c, IconData i, String t, String r) =>
      ListTile(leading: Icon(i), title: Text(t),
          onTap: () { Navigator.pop(c); c.push(r); });
}
