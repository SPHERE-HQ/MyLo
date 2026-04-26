import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../widgets/m_side_drawer.dart';

/// Map between bottom-nav indices and their root path. Order matters: index 0
/// is also the "home tab" we fall back to before exiting the app.
const _tabPaths = <String>[
  '/home/chat',
  '/home/feed',
  '/home/browser',
  '/home/wallet',
  '/home/profile',
];

class HomeShell extends StatefulWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  DateTime? _lastBackPress;

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    for (var i = 0; i < _tabPaths.length; i++) {
      if (loc.startsWith(_tabPaths[i])) return i;
    }
    return 0;
  }

  bool _isAtTabRoot(BuildContext context) {
    final loc = GoRouterState.of(context).uri.path;
    return _tabPaths.contains(loc);
  }

  Future<void> _handlePop(BuildContext context) async {
    final router = GoRouter.of(context);
    // 1. If we are on a nested page within a tab (e.g. /home/profile/edit),
    //    pop back to the tab root.
    if (router.canPop()) {
      router.pop();
      return;
    }
    // 2. If we are on a tab other than the home tab, switch back to the
    //    home tab instead of exiting.
    if (!_isAtTabRoot(context) || _selectedIndex(context) != 0) {
      context.go(_tabPaths.first);
      return;
    }
    // 3. On the home tab: require a second back-press within 2 seconds to
    //    exit, so a stray tap doesn't kick the user out.
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
    final idx = _selectedIndex(context);
    return PopScope(
      // Always intercept the system back gesture so we can decide what to do.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handlePop(context);
      },
      child: Scaffold(
        drawer: const MSideDrawer(),
        body: widget.child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: idx,
          onDestinationSelected: (i) {
            if (i >= 0 && i < _tabPaths.length) {
              context.go(_tabPaths[i]);
            }
          },
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline),
              selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view), label: 'Feed'),
            NavigationDestination(
              icon: Icon(Icons.public_outlined),
              selectedIcon: Icon(Icons.public), label: 'Browser'),
            NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined),
              selectedIcon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person), label: 'Profil'),
          ],
        ),
      ),
    );
  }
}
