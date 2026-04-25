import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/auth/auth_provider.dart';
import '../modules/ai/presentation/screens/ai_screen.dart';
import '../modules/auth/presentation/screens/forgot_password_screen.dart';
import '../modules/auth/presentation/screens/login_screen.dart';
import '../modules/auth/presentation/screens/onboarding_screen.dart';
import '../modules/auth/presentation/screens/register_screen.dart';
import '../modules/auth/presentation/screens/reset_password_screen.dart';
import '../modules/auth/presentation/screens/splash_screen.dart';
import '../modules/auth/presentation/screens/verify_email_screen.dart';
import '../modules/browser/presentation/screens/browser_screen.dart';
import '../modules/chat/presentation/screens/chat_list_screen.dart';
import '../modules/chat/presentation/screens/chat_room_screen.dart';
import '../modules/chat/presentation/screens/create_group_screen.dart';
import '../modules/community/presentation/screens/channel_screen.dart';
import '../modules/community/presentation/screens/community_list_screen.dart';
import '../modules/community/presentation/screens/server_create_screen.dart';
import '../modules/community/presentation/screens/server_invite_screen.dart';
import '../modules/community/presentation/screens/server_members_screen.dart';
import '../modules/email/presentation/screens/email_compose_screen.dart';
import '../modules/email/presentation/screens/email_detail_screen.dart';
import '../modules/email/presentation/screens/email_list_screen.dart';
import '../modules/feed/presentation/screens/buat_post_screen.dart';
import '../modules/feed/presentation/screens/explore_screen.dart';
import '../modules/feed/presentation/screens/feed_screen.dart';
import '../modules/feed/presentation/screens/post_detail_screen.dart';
import '../modules/feed/presentation/screens/story_viewer_screen.dart';
import '../modules/notifications/presentation/screens/notifications_screen.dart';
import '../modules/profile/presentation/screens/contact_profile_screen.dart';
import '../modules/profile/presentation/screens/edit_profile_screen.dart';
import '../modules/profile/presentation/screens/profile_screen.dart';
import '../modules/settings/presentation/screens/about_screen.dart';
import '../modules/settings/presentation/screens/change_password_screen.dart';
import '../modules/settings/presentation/screens/help_screen.dart';
import '../modules/settings/presentation/screens/privacy_screen.dart';
import '../modules/settings/presentation/screens/settings_screen.dart';
import '../modules/storage/presentation/screens/storage_screen.dart';
import '../modules/wallet/presentation/screens/topup_screen.dart';
import '../modules/wallet/presentation/screens/transfer_screen.dart';
import '../modules/wallet/presentation/screens/wallet_screen.dart';
import '../shared/screens/home_shell.dart';

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AsyncValue<AuthUser?>>(authStateProvider, (_, __) => notifyListeners());
  }
  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final auth = _ref.read(authStateProvider);
    final isAuthed = auth.value != null;
    final loc = state.matchedLocation;
    final isAuthRoute = loc.startsWith('/auth');
    final isSplash = loc == '/';
    if (isSplash) return null;
    if (!isAuthed && !isAuthRoute) return '/auth/login';
    if (isAuthed && isAuthRoute) return '/home/chat';
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
      GoRoute(
        path: '/auth/verify-email',
        builder: (_, state) => VerifyEmailScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      GoRoute(path: '/auth/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/auth/reset-password',
        builder: (_, state) => ResetPasswordScreen(
          email: state.uri.queryParameters['email'] ?? '',
        ),
      ),
      ShellRoute(
        builder: (_, __, child) => HomeShell(child: child),
        routes: [
          // ─── Chat ─────────────────────────────────────────────────
          GoRoute(path: '/home/chat', builder: (_, __) => const ChatListScreen()),
          GoRoute(
            path: '/home/chat/create-group',
            builder: (_, __) => const CreateGroupScreen(),
          ),
          GoRoute(
            path: '/home/chat/:id',
            builder: (_, s) => ChatRoomScreen(
              conversationId: s.pathParameters['id']!,
              otherUserName: s.uri.queryParameters['name'] ?? 'Chat',
              otherUserAvatar: s.uri.queryParameters['avatar'],
            ),
          ),
          // ─── Feed ─────────────────────────────────────────────────
          GoRoute(path: '/home/feed', builder: (_, __) => const FeedScreen()),
          GoRoute(path: '/home/feed/buat', builder: (_, __) => const BuatPostScreen()),
          GoRoute(
            path: '/home/feed/post/:id',
            builder: (_, s) {
              final post = s.extra as Map<String, dynamic>? ?? {'id': s.pathParameters['id']!};
              return PostDetailScreen(post: post);
            },
          ),
          GoRoute(
            path: '/home/feed/story',
            builder: (_, s) {
              final idx = int.tryParse(s.uri.queryParameters['index'] ?? '0') ?? 0;
              return StoryViewerScreen(initialIndex: idx);
            },
          ),
          GoRoute(path: '/home/explore', builder: (_, __) => const ExploreScreen()),
          // ─── Wallet (stays coming soon) ───────────────────────────
          GoRoute(path: '/home/wallet', builder: (_, __) => const WalletScreen()),
          GoRoute(path: '/home/wallet/topup', builder: (_, __) => const TopupScreen()),
          GoRoute(path: '/home/wallet/transfer', builder: (_, __) => const TransferScreen()),
          // ─── Email ────────────────────────────────────────────────
          GoRoute(path: '/home/email', builder: (_, __) => const EmailListScreen()),
          GoRoute(path: '/home/email/compose', builder: (_, __) => const EmailComposeScreen()),
          GoRoute(
            path: '/home/email/:id',
            builder: (_, s) => EmailDetailScreen(emailId: s.pathParameters['id']!),
          ),
          // ─── Community ────────────────────────────────────────────
          GoRoute(path: '/home/community', builder: (_, __) => const CommunityListScreen()),
          GoRoute(path: '/home/community/create', builder: (_, __) => const ServerCreateScreen()),
          GoRoute(
            path: '/home/community/:serverId/channel/:channelId',
            builder: (_, s) => ChannelScreen(
              serverId: s.pathParameters['serverId']!,
              channelId: s.pathParameters['channelId']!,
            ),
          ),
          GoRoute(
            path: '/home/community/:serverId/members',
            builder: (_, s) => ServerMembersScreen(
              serverId: s.pathParameters['serverId']!,
              serverName: s.extra as String? ?? 'Server',
            ),
          ),
          GoRoute(
            path: '/home/community/:serverId/invite',
            builder: (_, s) => ServerInviteScreen(
              serverId: s.pathParameters['serverId']!,
              serverName: s.extra as String? ?? 'Server',
            ),
          ),
          // ─── Browser, Storage, AI ─────────────────────────────────
          GoRoute(path: '/home/browser', builder: (_, __) => const BrowserScreen()),
          GoRoute(path: '/home/storage', builder: (_, __) => const StorageScreen()),
          GoRoute(path: '/home/ai', builder: (_, __) => const AiScreen()),
          // ─── Notifications ────────────────────────────────────────
          GoRoute(path: '/home/notifications', builder: (_, __) => const NotificationsScreen()),
          // ─── Profile ──────────────────────────────────────────────
          GoRoute(path: '/home/profile', builder: (_, __) => const ProfileScreen()),
          GoRoute(path: '/home/profile/edit', builder: (_, __) => const EditProfileScreen()),
          GoRoute(
            path: '/home/users/:id',
            builder: (_, s) => ContactProfileScreen(userId: s.pathParameters['id']!),
          ),
          // ─── Settings ─────────────────────────────────────────────
          GoRoute(path: '/home/settings', builder: (_, __) => const SettingsScreen()),
          GoRoute(path: '/home/settings/password', builder: (_, __) => const ChangePasswordScreen()),
          GoRoute(path: '/home/settings/privacy', builder: (_, __) => const PrivacyScreen()),
          GoRoute(path: '/home/settings/help', builder: (_, __) => const HelpScreen()),
          GoRoute(path: '/home/settings/about', builder: (_, __) => const AboutScreen()),
        ],
      ),
    ],
  );
});
