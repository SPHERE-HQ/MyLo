import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../modules/auth/presentation/screens/splash_screen.dart';
import '../modules/auth/presentation/screens/onboarding_screen.dart';
import '../modules/auth/presentation/screens/login_screen.dart';
import '../modules/auth/presentation/screens/register_screen.dart';
import '../modules/auth/presentation/screens/verify_email_screen.dart';
import '../shared/screens/home_shell.dart';
import '../modules/chat/presentation/screens/chat_list_screen.dart';
import '../modules/chat/presentation/screens/chat_room_screen.dart';
import '../modules/feed/presentation/screens/feed_screen.dart';
import '../modules/feed/presentation/screens/explore_screen.dart';
import '../modules/wallet/presentation/screens/wallet_screen.dart';
import '../modules/wallet/presentation/screens/topup_screen.dart';
import '../modules/wallet/presentation/screens/transfer_screen.dart';
import '../modules/email/presentation/screens/email_list_screen.dart';
import '../modules/email/presentation/screens/email_detail_screen.dart';
import '../modules/community/presentation/screens/community_list_screen.dart';
import '../modules/community/presentation/screens/channel_screen.dart';
import '../modules/profile/presentation/screens/profile_screen.dart';
import '../core/auth/auth_provider.dart';

// ChangeNotifier sebagai jembatan antara Riverpod dan GoRouter
// Ini mencegah GoRouter dibuat ulang setiap kali auth state berubah
class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (_, __) {
      notifyListeners();
    });
  }
  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = _ref.read(authStateProvider);
    final isAuthenticated = auth.value != null;
    final isAuthRoute = state.matchedLocation.startsWith('/auth');
    final isSplash = state.matchedLocation == '/';
    if (isSplash) return null;
    if (!isAuthenticated && !isAuthRoute) return '/auth/login';
    if (isAuthenticated && isAuthRoute) return '/home/chat';
    return null;
  }
}

final _routerNotifierProvider = Provider((ref) => _RouterNotifier(ref));

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(_routerNotifierProvider);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/auth/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/auth/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/auth/verify-email', builder: (_, __) => const VerifyEmailScreen()),
      ShellRoute(
        builder: (_, __, child) => HomeShell(child: child),
        routes: [
          GoRoute(path: '/home/chat', builder: (_, __) => const ChatListScreen()),
          GoRoute(
            path: '/home/chat/:id',
            builder: (_, state) => ChatRoomScreen(
              conversationId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(path: '/home/feed', builder: (_, __) => const FeedScreen()),
          GoRoute(path: '/home/explore', builder: (_, __) => const ExploreScreen()),
          GoRoute(path: '/home/wallet', builder: (_, __) => const WalletScreen()),
          GoRoute(path: '/home/wallet/topup', builder: (_, __) => const TopupScreen()),
          GoRoute(path: '/home/wallet/transfer', builder: (_, __) => const TransferScreen()),
          GoRoute(path: '/home/email', builder: (_, __) => const EmailListScreen()),
          GoRoute(
            path: '/home/email/:id',
            builder: (_, state) => EmailDetailScreen(
              emailId: state.pathParameters['id']!,
            ),
          ),
          GoRoute(path: '/home/community', builder: (_, __) => const CommunityListScreen()),
          GoRoute(
            path: '/home/community/:serverId/channel/:channelId',
            builder: (_, state) => ChannelScreen(
              serverId: state.pathParameters['serverId']!,
              channelId: state.pathParameters['channelId']!,
            ),
          ),
          GoRoute(path: '/home/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
});
