import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../presentation/providers/auth_provider.dart';

import '../../presentation/screens/shell/app_shell.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/search/search_screen.dart';
import '../../presentation/screens/details/details_screen.dart';
import '../../presentation/screens/watchlist/watchlist_screen.dart';
import '../../presentation/screens/downloads/downloads_screen.dart';
import '../../presentation/screens/splash/splash_screen.dart';
import '../../presentation/screens/profile/profile_screen.dart';

final rootNavKey = GlobalKey<NavigatorState>();

/// Smooth slide-up + fade + scale transition for tab pages
CustomTransitionPage<void> _fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: ShellPopScope(child: child),
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Incoming page: slide up + fade + scale
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.03),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation);
      final fade = CurveTween(curve: Curves.easeOut).animate(animation);
      final scale = Tween<double>(begin: 0.97, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic))
          .animate(animation);

      // Exiting page: subtle fade + scale down
      final secondaryFade = Tween<double>(begin: 1.0, end: 0.92)
          .chain(CurveTween(curve: Curves.easeIn))
          .animate(secondaryAnimation);
      final secondaryScale = Tween<double>(begin: 1.0, end: 0.96)
          .chain(CurveTween(curve: Curves.easeIn))
          .animate(secondaryAnimation);

      return FadeTransition(
        opacity: secondaryFade,
        child: ScaleTransition(
          scale: secondaryScale,
          child: SlideTransition(
            position: slide,
            child: FadeTransition(
              opacity: fade,
              child: ScaleTransition(
                scale: scale,
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Notifier that bridges Riverpod's Auth State with GoRouter's Listenable
class RouterNotifier extends ChangeNotifier {
  final Ref _ref;

  RouterNotifier(this._ref) {
    _ref.listen(authStateProvider, (previous, next) {
      // Use microtask to avoid notifying during a build phase
      Future.microtask(() => notifyListeners());
    });
  }
}

final routerNotifierProvider = Provider<RouterNotifier>((ref) => RouterNotifier(ref));

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = ref.watch(routerNotifierProvider);

  return GoRouter(
    navigatorKey: rootNavKey,
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: (context, state) {
      // Use ref.read to get the current state without triggering a provider rebuild
      final authState = ref.read(authStateProvider);
      final user = authState.valueOrNull;
      final isSplash = state.matchedLocation == '/splash';
      
      // If NOT logged in and not on splash, force to splash
      if (user == null && !isSplash) {
        return '/splash';
      }

      // If logged in and on splash, we handle transition inside Splash or redirect here
      // But we let Splash handle its own initialization first.
      
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
        // This is a landing spot for redirects. 
        // Supabase package will capture the session from the URL automatically.
        // We just redirect to Home.
        return const SizedBox.shrink(); 
      },
      redirect: (context, state) => '/home',
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
              pageBuilder: (context, state) => _fadePage(const HomeScreen(), state),
            ),
            _detailsRoute(),
          ],
        ),
        // Search Branch
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/search',
              pageBuilder: (context, state) => _fadePage(const SearchScreen(), state),
            ),
            _detailsRoute(),
          ],
        ),
        // Watchlist Branch
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/watchlist',
              pageBuilder: (context, state) => _fadePage(const WatchlistScreen(), state),
            ),
            _detailsRoute(),
          ],
        ),
        // Downloads Branch
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/downloads',
              pageBuilder: (context, state) => _fadePage(const DownloadsScreen(), state),
            ),
            _detailsRoute(),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
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
      return CustomTransitionPage<void>(
        key: state.pageKey,
        child: ShellPopScope(
          child: DetailsScreen(tmdbId: id, mediaType: mediaType),
        ),
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
            ),
            child: child,
          );
        },
      );
    },
  );
}
