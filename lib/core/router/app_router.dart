import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../presentation/screens/shell/app_shell.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/movies/movies_screen.dart';
import '../../presentation/screens/tv/tv_screen.dart';
import '../../presentation/screens/anime/anime_screen.dart';
import '../../presentation/screens/korean/korean_screen.dart';
import '../../presentation/screens/search/search_screen.dart';
import '../../presentation/screens/details/details_screen.dart';
import '../../presentation/screens/watchlist/watchlist_screen.dart';
import '../../presentation/screens/downloads/downloads_screen.dart';

final rootNavKey = GlobalKey<NavigatorState>();
final _shellNavKey = GlobalKey<NavigatorState>();

/// Smooth fade + scale transition for tab pages
CustomTransitionPage<void> _fadePage(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurveTween(curve: Curves.easeOut).animate(animation);
      final scale = Tween<double>(begin: 0.96, end: 1.0)
          .chain(CurveTween(curve: Curves.easeOutCubic))
          .animate(animation);
          
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: scale,
          child: child,
        ),
      );
    },
  );
}

final appRouter = GoRouter(
  navigatorKey: rootNavKey,
  initialLocation: '/home',
  routes: [
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
          pageBuilder: (context, state) => _fadePage(const MoviesScreen(), state),
        ),
        GoRoute(
          path: '/tv',
          pageBuilder: (context, state) => _fadePage(const TvScreen(), state),
        ),
        GoRoute(
          path: '/anime',
          pageBuilder: (context, state) => _fadePage(const AnimeScreen(), state),
        ),
        GoRoute(
          path: '/search',
          pageBuilder: (context, state) => _fadePage(const SearchScreen(), state),
        ),
        GoRoute(
          path: '/watchlist',
          pageBuilder: (context, state) => _fadePage(const WatchlistScreen(), state),
        ),
        GoRoute(
          path: '/downloads',
          pageBuilder: (context, state) => _fadePage(const DownloadsScreen(), state),
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
);
