import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../presentation/screens/shell/app_shell.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/search/search_screen.dart';
import '../../presentation/screens/details/details_screen.dart';
import '../../presentation/screens/watchlist/watchlist_screen.dart';
import '../../presentation/screens/downloads/downloads_screen.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';
import '../../presentation/screens/profile/account_settings_screen.dart';
import '../../presentation/screens/profile/placeholder_screen.dart';
import '../../presentation/screens/admin/admin_console_screen.dart';
import '../../presentation/screens/admin/manage_entries_screen.dart';
import '../../presentation/screens/admin/admin_message_screen.dart';
import '../../presentation/screens/admin/manage_admins_screen.dart';
import '../../presentation/screens/profile/notification_settings_screen.dart';
import '../../presentation/screens/notifications/notifications_screen.dart';
import '../../presentation/providers/auth_provider.dart';
import '../../presentation/providers/manifest_provider.dart';

class AppRouter {
  static GlobalKey<NavigatorState> rootNavKey = GlobalKey<NavigatorState>();
}

/// Unified fast transition — subtle slide-up + fade for all pages.
/// Keeps the app feeling snappy and consistent across every navigation path.
CustomTransitionPage<void> _quickPage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: ShellPopScope(child: child),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final slide = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
          .chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);
      final fade = CurveTween(curve: Curves.easeOutCubic).animate(animation);

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    // Listen to auth state. Only notify GoRouter when the user identity
    // actually changes (login or logout), not on every AsyncValue emission.
    _ref.listen(authStateProvider, (previous, next) {
      if (previous?.valueOrNull?.id != next.valueOrNull?.id) {
        notifyListeners();
      }
    });

    // We DO NOT listen to manifestProvider here. The splash screen manually
    // listens to it to execute the cinematic context.go('/home') transition.
  }
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) => RouterNotifier(ref));

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    navigatorKey: AppRouter.rootNavKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      final authState = ref.read(authStateProvider);
      final user = authState.valueOrNull;
      
      final bool isLoggedIn = user != null;
      final bool onSplash = state.matchedLocation == '/splash';
      final bool onCallback = state.matchedLocation == '/login-callback';

      // Protection: if not logged in and trying to access an internal route
      if (!isLoggedIn && !onSplash && !onCallback) {
        return '/splash';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      // Silent callback route for Supabase OAuth redirects
      GoRoute(
        path: '/login-callback',
        builder: (context, state) {
          return const SizedBox.shrink(); 
        },
      ),
    // Stateful Shell Route for multi-branch navigation state preservation
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => 
          AppShell(navigationShell: navigationShell),
      branches: [
        // Home Branch
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              pageBuilder: (context, state) => _quickPage(const HomeScreen(), state),
            ),
            _detailsRoute(),
          ],
        ),
        // Search Branch
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) => _quickPage(const SearchScreen(), state),
            ),
            _detailsRoute(),
          ],
        ),
        // Watchlist Branch
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/watchlist',
              pageBuilder: (context, state) => _quickPage(const WatchlistScreen(), state),
            ),
            _detailsRoute(),
          ],
        ),
        // Downloads Branch
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/downloads',
              pageBuilder: (context, state) => _quickPage(const DownloadsScreen(), state),
            ),
            _detailsRoute(),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) => _quickPage(const ProfileScreen(), state),
    ),
    GoRoute(
      path: '/account-settings',
      pageBuilder: (context, state) => _quickPage(const AccountSettingsScreen(), state),
    ),
    GoRoute(
      path: '/admin-console',
      pageBuilder: (context, state) => _quickPage(const AdminConsoleScreen(), state),
    ),
    GoRoute(
      path: '/admin-console/manage-entries/:category',
      pageBuilder: (context, state) {
        final category = state.pathParameters['category'] ?? 'newly_added';
        return _quickPage(ManageEntriesScreen(category: category), state);
      },
    ),
    GoRoute(
      path: '/admin-console/admin-message',
      pageBuilder: (context, state) => _quickPage(const AdminMessageScreen(), state),
    ),
    GoRoute(
      path: '/admin-console/manage-admins',
      pageBuilder: (context, state) => _quickPage(const ManageAdminsScreen(), state),
    ),
    GoRoute(
      path: '/notifications',
      pageBuilder: (context, state) => _quickPage(const NotificationsScreen(), state),
    ),
    GoRoute(
      path: '/notification-settings',
      pageBuilder: (context, state) => _quickPage(const NotificationSettingsScreen(), state),
    ),
    GoRoute(
      path: '/security-settings',
      pageBuilder: (context, state) => _quickPage(const PlaceholderScreen(title: 'Security Settings'), state),
    ),
    GoRoute(
      path: '/placeholder/:title',
      pageBuilder: (context, state) {
        final title = state.pathParameters['title'] ?? 'Coming Soon';
        return _quickPage(PlaceholderScreen(title: title), state);
      },
    ),
  ],
    errorBuilder: (context, state) => PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Page Not Found',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                state.error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE91E63),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Go to Home'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

// Helper to keep details route definition DRY across branches
GoRoute _detailsRoute() {
  return GoRoute(
    path: '/details/:mediaType/:id',
    pageBuilder: (context, state) {
      final mediaType = state.pathParameters['mediaType']!;
      final id = int.parse(state.pathParameters['id']!);
      return _quickPage(DetailsScreen(tmdbId: id, mediaType: mediaType), state);
    },
  );
}
