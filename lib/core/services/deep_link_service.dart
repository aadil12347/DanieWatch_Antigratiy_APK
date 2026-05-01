import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/widgets.dart';

import '../router/app_router.dart';

/// Singleton service that handles incoming deep links.
///
/// Supported link formats:
///   Custom scheme:  `daniewatch://movie/123`  or  `daniewatch://tv/81355`
///   HTTPS links:    `https://daniewatch-app.vercel.app/movie/123`
///                   `https://daniewatch-app.vercel.app/tv/81355`
///   Legacy HTTPS:   `https://aadil12347.github.io/daniewatch-app.github.io/movie/123`
///
/// The HTTPS format is used for sharing because messaging apps (WhatsApp,
/// Telegram, etc.) only render `https://` URLs as clickable links.
///
/// If the user is logged in and the app is ready, the service navigates immediately.
/// If the user is NOT logged in (splash still showing), the link is saved to
/// SharedPreferences as a "pending deep link" which the splash screen consumes
/// after authentication completes.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const String _pendingLinkKey = 'pending_deep_link';

  /// The HTTPS host used for share links (must match AndroidManifest intent-filter).
  static const String shareHost = 'daniewatch-app.vercel.app';

  /// Legacy GitHub Pages host (for backward compatibility with old shared links).
  static const String _legacyHost = 'aadil12347.github.io';
  static const String _legacyRepoPath = 'daniewatch-app.github.io';

  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  /// Whether the app is in a state where it can navigate (user is logged in,
  /// past the splash screen).
  bool _isAppReady = false;

  /// Marks the app as ready for navigation (called after splash → home transition).
  void setAppReady() {
    _isAppReady = true;
    debugPrint('🔗 DeepLinkService: App is now ready for deep link navigation');
  }

  /// Build a share-friendly HTTPS link for a given media type and TMDB id.
  /// This format is clickable on WhatsApp, Telegram, Instagram, etc.
  static String buildShareLink(String mediaType, int tmdbId) {
    return 'https://$shareHost/$mediaType/$tmdbId';
  }

  /// Initialize the service. Should be called once during app startup.
  Future<void> initialize() async {
    _appLinks = AppLinks();

    // 1. Check for an initial link (app was opened via a deep link from cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('🔗 DeepLinkService: Initial link received: $initialUri');
        await _handleIncomingLink(initialUri);
      }
    } catch (e) {
      debugPrint('🔗 DeepLinkService: Error getting initial link: $e');
    }

    // 2. Listen for links while the app is running (warm start / background)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('🔗 DeepLinkService: Stream link received: $uri');
        _handleIncomingLink(uri);
      },
      onError: (error) {
        debugPrint('🔗 DeepLinkService: Stream error: $error');
      },
    );
  }

  /// Parse and handle an incoming URI.
  Future<void> _handleIncomingLink(Uri uri) async {
    String? mediaType;
    String? id;

    if (uri.scheme == 'daniewatch') {
      // Custom scheme: daniewatch://movie/123
      // uri.host = 'movie', uri.pathSegments = ['123']
      // Or triple slash: daniewatch:///movie/123
      // uri.host = '', uri.pathSegments = ['movie', '123']
      if (uri.host.isNotEmpty && uri.pathSegments.isNotEmpty) {
        mediaType = uri.host;
        id = uri.pathSegments.first;
      } else if (uri.pathSegments.length >= 2) {
        mediaType = uri.pathSegments[0];
        id = uri.pathSegments[1];
      }
    } else if (uri.scheme == 'https' && uri.host == shareHost) {
      // New Vercel link: https://daniewatch-app.vercel.app/movie/123
      // uri.pathSegments = ['movie', '123']
      final segments = uri.pathSegments.toList();
      if (segments.length >= 2) {
        mediaType = segments[0];
        id = segments[1];
      }
    } else if (uri.scheme == 'https' && uri.host == _legacyHost) {
      // Legacy GitHub Pages: https://aadil12347.github.io/daniewatch-app.github.io/movie/123
      final segments = uri.pathSegments.toList();
      if (segments.isNotEmpty && segments.first == _legacyRepoPath) {
        segments.removeAt(0);
      }
      if (segments.length >= 2) {
        mediaType = segments[0];
        id = segments[1];
      }
    }

    if (mediaType == null || id == null) {
      debugPrint('🔗 DeepLinkService: Could not parse link: $uri');
      return;
    }

    // Validate media type
    final normalizedType = mediaType.toLowerCase();
    if (normalizedType != 'movie' && normalizedType != 'tv') {
      debugPrint('🔗 DeepLinkService: Unknown media type: $mediaType');
      return;
    }

    // Validate ID is numeric
    if (int.tryParse(id) == null) {
      debugPrint('🔗 DeepLinkService: Invalid ID: $id');
      return;
    }

    final route = '/details/$normalizedType/$id';

    if (_isAppReady) {
      // App is ready — navigate immediately
      _navigateTo(route);
    } else {
      // App is not ready (still on splash / logging in) — save for later
      debugPrint('🔗 DeepLinkService: App not ready, saving pending link: $route');
      await _savePendingLink(route);
    }
  }

  /// Navigate to a route using the root navigator.
  void _navigateTo(String route) {
    debugPrint('🔗 DeepLinkService: Navigating to $route');
    final context = AppRouter.rootNavKey.currentContext;
    if (context != null) {
      context.push(route);
    } else {
      debugPrint('🔗 DeepLinkService: No context available, saving as pending');
      _savePendingLink(route);
    }
  }

  /// Save a route to SharedPreferences for consumption by the splash screen.
  Future<void> _savePendingLink(String route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingLinkKey, route);
  }

  /// Consume the pending deep link (called by splash screen after auth).
  /// Returns the route string (e.g., '/details/movie/123') or null if none.
  static Future<String?> consumePendingLink() async {
    final prefs = await SharedPreferences.getInstance();
    final link = prefs.getString(_pendingLinkKey);
    if (link != null) {
      await prefs.remove(_pendingLinkKey);
      debugPrint('🔗 DeepLinkService: Consumed pending link: $link');
    }
    return link;
  }

  /// Dispose the stream subscription.
  void dispose() {
    _linkSubscription?.cancel();
  }
}
