import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../widgets/m_side_drawer.dart';
import '../widgets/m_floating_nav_bubble.dart';
import '../widgets/m_active_call_pill.dart';

/// Mapping antara root path tab dan label/ikonnya.
/// Index 0 ('/home/chat') juga jadi tab "home" yang dipakai untuk
/// fallback sebelum exit aplikasi.
const _navItems = <NavBubbleItem>[
  NavBubbleItem(icon: Icons.chat_bubble, label: 'Chat', path: '/home/chat'),
  NavBubbleItem(icon: Icons.groups, label: 'Komunitas', path: '/home/community'),
  NavBubbleItem(icon: Icons.grid_view, label: 'Feed', path: '/home/feed'),
  NavBubbleItem(icon: Icons.public, label: 'Browser', path: '/home/browser'),
  NavBubbleItem(icon: Icons.account_balance_wallet, label: 'Wallet', path: '/home/wallet'),
  NavBubbleItem(icon: Icons.email_outlined, label: 'Email', path: '/home/email'),
  NavBubbleItem(icon: Icons.cloud_outlined, label: 'Penyimpanan', path: '/home/storage'),
  NavBubbleItem(icon: Icons.auto_awesome, label: 'Mylo AI', path: '/home/ai'),
  NavBubbleItem(icon: Icons.notifications_outlined, label: 'Notifikasi', path: '/home/notifications'),
  NavBubbleItem(icon: Icons.person, label: 'Profil', path: '/home/profile'),
  NavBubbleItem(icon: Icons.settings_outlined, label: 'Pengaturan', path: '/home/settings'),
];

/// Path-path tempat bubble navigasi disembunyikan agar tidak menutup UI
/// (misal saat sedang dalam panggilan suara/video atau sedang chat).
bool _shouldHideBubble(String location) {
  // Sembunyikan di halaman panggilan dan voice room.
  if (location.contains('/voice')) return true;
  // Sembunyikan di chat room individual (tetap muncul di list).
  if (RegExp(r'^/home/chat/[^/]+$').hasMatch(location)) return true;
  if (RegExp(r'^/home/chat/[^/]+/').hasMatch(location)) return true;
  // Sembunyikan di channel komunitas.
  if (RegExp(r'^/home/community/[^/]+/channel/').hasMatch(location)) return true;
  // Sembunyikan di story viewer.
  if (location.startsWith('/home/feed/story')) return true;
  return false;
}

/// Pill panggilan aktif disembunyikan saat user sedang membuka layar
/// panggilan itu sendiri (kalau tidak, pill akan dobel menutupi layar).
bool _shouldHidePill(String location) {
  if (location.contains('/voice')) return true;
  // Story viewer fullscreen — biarkan pengguna fokus.
  if (location.startsWith('/home/feed/story')) return true;
  return false;
}

const _tabRootPaths = <String>{
  '/home/chat',
  '/home/community',
  '/home/feed',
  '/home/browser',
  '/home/wallet',
  '/home/profile',
  '/home/email',
  '/home/storage',
  '/home/ai',
  '/home/notifications',
  '/home/settings',
};

class HomeShell extends StatefulWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  DateTime? _lastBackPress;

  String _currentLocation(BuildContext context) =>
      GoRouterState.of(context).uri.toString();

  bool _isAtTabRoot(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    return _tabRootPaths.contains(loc);
  }

  Future<void> _handlePop(BuildContext context) async {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    if (!_isAtTabRoot(context) ||
        GoRouterState.of(context).uri.path != '/home/chat') {
      context.go('/home/chat');
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tekan kembali sekali lagi untuk keluar'),
        duration: Duration(seconds: 2),
      ));
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final loc = _currentLocation(context);
    final hideBubble = _shouldHideBubble(loc);
    final hidePill = _shouldHidePill(loc);
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handlePop(context);
      },
      child: Scaffold(
        // Drawer tetap ada — bisa dibuka dengan geser dari tepi kiri.
        drawer: const MSideDrawer(),
        // Perlebar area swipe agar gesture buka drawer terasa lebih natural.
        drawerEdgeDragWidth: 48,
        body: Stack(
          children: [
            // Konten utama. Kalau sedang dalam panggilan & user buka layar
            // panggilan, layar itu di-push di atas HomeShell jadi pill ini
            // tertutup secara natural; tapi di tab manapun lainnya, pill
            // tetap nempel di atas konten supaya panggilan gampang dibuka
            // lagi.
            Positioned.fill(
              child: hidePill
                  ? widget.child
                  : SafeArea(
                      bottom: false,
                      child: Column(children: [
                        const MActiveCallPill(),
                        Expanded(child: widget.child),
                      ]),
                    ),
            ),
            if (!hideBubble && !keyboardOpen)
              MFloatingNavBubble(
                items: _navItems,
                currentPath: loc,
              ),
          ],
        ),
      ),
    );
  }
}
