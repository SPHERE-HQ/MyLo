import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/m_side_drawer.dart';

class HomeShell extends StatelessWidget {
  final Widget child;
  const HomeShell({super.key, required this.child});

  int _selectedIndex(BuildContext context) {
    final loc = GoRouterState.of(context).uri.toString();
    if (loc.startsWith('/home/chat')) return 0;
    if (loc.startsWith('/home/feed')) return 1;
    if (loc.startsWith('/home/explore')) return 2;
    if (loc.startsWith('/home/wallet')) return 3;
    if (loc.startsWith('/home/profile')) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _selectedIndex(context);
    return Scaffold(
      drawer: const MSideDrawer(),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/home/chat');
            case 1: context.go('/home/feed');
            case 2: context.go('/home/explore');
            case 3: context.go('/home/wallet');
            case 4: context.go('/home/profile');
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
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore), label: 'Explore'),
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet), label: 'Wallet'),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person), label: 'Profil'),
        ],
      ),
    );
  }
}
