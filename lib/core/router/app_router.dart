import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/screens/shell/app_shell.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/movies/movies_screen.dart';
import '../../presentation/screens/tv/tv_screen.dart';
import '../../presentation/screens/anime/anime_screen.dart';
import '../../presentation/screens/search/search_screen.dart';
import '../../presentation/screens/details/details_screen.dart';
import '../../presentation/screens/watchlist/watchlist_screen.dart';
import '../../presentation/screens/downloads/downloads_screen.dart';
import '../../presentation/screens/korean/korean_screen.dart';
import '../../presentation/screens/splash/splash_screen.dart';

final rootNavKey = GlobalKey<NavigatorState>();
final _shellNavKey = GlobalKey<NavigatorState>();

/// Smooth slide-up + fade + scale transition for tab pages
CustomTransitionPage<void> _fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
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

final appRouter = GoRouter(
  navigatorKey: rootNavKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    // Shell route with bottom navigation
    ShellRoute(
      navigatorKey: _shellNavKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => _fadePage(const HomeScreen(), state),
        ),
        GoRoute(
          path: '/movies',
          pageBuilder: (context, state) =>
              _fadePage(const MoviesScreen(), state),
        ),
        GoRoute(
          path: '/tv',
          pageBuilder: (context, state) => _fadePage(const TvScreen(), state),
        ),
        GoRoute(
          path: '/anime',
          pageBuilder: (context, state) =>
              _fadePage(const AnimeScreen(), state),
        ),
        GoRoute(
          path: '/korean',
          pageBuilder: (context, state) =>
              _fadePage(const KoreanScreen(), state),
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (context, state) =>
              _fadePage(const SearchScreen(), state),
        ),
        GoRoute(
          path: '/watchlist',
          pageBuilder: (context, state) =>
              _fadePage(const WatchlistScreen(), state),
        ),
        GoRoute(
          path: '/downloads',
          pageBuilder: (context, state) =>
              _fadePage(const DownloadsScreen(), state),
        ),
        // Detail route INSIDE shell so bottom nav stays visible
        GoRoute(
          path: '/details/:mediaType/:id',
          pageBuilder: (context, state) {
            final mediaType = state.pathParameters['mediaType']!;
            final id = int.parse(state.pathParameters['id']!);
            return CustomTransitionPage<void>(
              key: state.pageKey,
              child: DetailsScreen(tmdbId: id, mediaType: mediaType),
              transitionDuration: const Duration(milliseconds: 400),
              reverseTransitionDuration: const Duration(milliseconds: 350),
              transitionsBuilder:
                  (context, animation, secondaryAnimation, child) {
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
        ),
      ],
    ),
    // Root-level details route for navigation from search (which is outside the ShellRoute)
    GoRoute(
      path: '/search-details/:mediaType/:id',
      parentNavigatorKey: rootNavKey,
      pageBuilder: (context, state) {
        final mediaType = state.pathParameters['mediaType']!;
        final id = int.parse(state.pathParameters['id']!);
        return CustomTransitionPage<void>(
          key: state.pageKey,
          child: DetailsScreen(tmdbId: id, mediaType: mediaType),
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
