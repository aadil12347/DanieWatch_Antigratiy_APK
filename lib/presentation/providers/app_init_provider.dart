import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';
import '../../data/local/database.dart';
import '../../services/extraction/movie_site_scraper_service.dart';
import '../../main.dart' show supabaseReady;

/// Describes the current phase of app initialization.
enum InitPhase {
  pending,
  cacheClear,
  database,
  cache,
  supabase,
  ready,
}

/// State object for the initialization progress.
class AppInitState {
  final InitPhase phase;
  final String message;
  final double progress; // 0.0 to 1.0
  final bool isComplete;

  const AppInitState({
    this.phase = InitPhase.pending,
    this.message = 'Starting up…',
    this.progress = 0.0,
    this.isComplete = false,
  });

  AppInitState copyWith({
    InitPhase? phase,
    String? message,
    double? progress,
    bool? isComplete,
  }) =>
      AppInitState(
        phase: phase ?? this.phase,
        message: message ?? this.message,
        progress: progress ?? this.progress,
        isComplete: isComplete ?? this.isComplete,
      );
}

/// Key used to track the last app version that ran — for cache invalidation.
const _lastVersionKey = 'daniewatch_last_app_version';

/// StreamProvider that performs app initialization step-by-step.
/// Each step yields progress so the UI can show a loading overlay.
///
/// Steps:
/// 0. Check if app was updated — clear old caches so fresh data is fetched
/// 1. Initialize SQLite database
/// 2. Load disk cache for instant homepage data (only if not cleared)
/// 3. Wait for Supabase readiness (fires in parallel from main.dart Phase 2)
///
/// The provider completes with `isComplete = true` when all steps are done.
final appInitProvider = StreamProvider<AppInitState>((ref) async* {
  final sw = Stopwatch()..start();

  // Step 0: Check if app was updated — clear stale caches
  yield const AppInitState(
    phase: InitPhase.cacheClear,
    message: 'Checking for updates…',
    progress: 0.05,
  );

  bool cacheCleared = false;
  try {
    final prefs = await SharedPreferences.getInstance();
    final lastVersion = prefs.getString(_lastVersionKey);
    final currentVersion = Env.appVersion;

    if (lastVersion == null || lastVersion != currentVersion) {
      debugPrint('[AppInit] 🔄 Version changed ($lastVersion → $currentVersion) — clearing old caches');

      // Clear scraper disk cache (SharedPreferences-based home/category cache)
      await MovieSiteScraperService.instance.clearDiskCache();
      MovieSiteScraperService.instance.clearCache();

      // Clear TMDB response cache from SQLite (will be rebuilt gradually)
      // Note: DB might not be initialized yet, so we just flag it for later
      cacheCleared = true;

      // Save current version
      await prefs.setString(_lastVersionKey, currentVersion);
      debugPrint('[AppInit] ✅ Old caches cleared, version saved as $currentVersion');
    } else {
      debugPrint('[AppInit] ✅ Same version ($currentVersion) — caches valid');
    }
  } catch (e) {
    debugPrint('[AppInit] ⚠️ Version check error: $e');
  }

  // Yield a frame so the UI thread can breathe
  await Future<void>.delayed(Duration.zero);

  // Step 1: Database init
  yield const AppInitState(
    phase: InitPhase.database,
    message: 'Setting up database…',
    progress: 0.20,
  );

  try {
    await AppDatabase.instance.initialize();
    debugPrint('[AppInit] ✅ Database initialized in ${sw.elapsedMilliseconds}ms');

    // If caches were cleared due to version update, also clear TMDB cache table
    if (cacheCleared) {
      try {
        await AppDatabase.instance.db.delete('tmdb_cache');
        debugPrint('[AppInit] ✅ TMDB cache table cleared after version update');
      } catch (e) {
        debugPrint('[AppInit] ⚠️ TMDB cache clear error: $e');
      }
    }
  } catch (e) {
    debugPrint('[AppInit] ⚠️ Database init error: $e');
    // Non-fatal — continue; the app can still function with degraded caching
  }

  // Yield a frame
  await Future<void>.delayed(Duration.zero);

  // Step 2: Load disk cache (for instant homepage content)
  // Skip if we just cleared caches — they'll be rebuilt from Vega/Rog scraping
  yield AppInitState(
    phase: InitPhase.cache,
    message: cacheCleared ? 'Preparing fresh content…' : 'Loading content cache…',
    progress: 0.50,
  );

  if (!cacheCleared) {
    try {
      await MovieSiteScraperService.instance.loadDiskCache();
      debugPrint('[AppInit] ✅ Disk cache loaded in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[AppInit] ⚠️ Disk cache load error: $e');
    }
  } else {
    debugPrint('[AppInit] ℹ️ Skipping disk cache load — caches were cleared for fresh rebuild');
  }

  // Yield a frame
  await Future<void>.delayed(Duration.zero);

  // Step 3: Wait for Supabase (already initializing in main.dart Phase 2)
  yield const AppInitState(
    phase: InitPhase.supabase,
    message: 'Connecting to services…',
    progress: 0.80,
  );

  try {
    // Wait up to 5 seconds for Supabase; don't block forever
    await supabaseReady.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('[AppInit] ⚠️ Supabase timeout — continuing without');
      },
    );
    debugPrint('[AppInit] ✅ Supabase ready in ${sw.elapsedMilliseconds}ms');
  } catch (e) {
    debugPrint('[AppInit] ⚠️ Supabase wait error: $e');
  }

  // Done!
  sw.stop();
  debugPrint('[AppInit] 🚀 All init complete in ${sw.elapsedMilliseconds}ms');

  yield const AppInitState(
    phase: InitPhase.ready,
    message: 'Ready!',
    progress: 1.0,
    isComplete: true,
  );
});

/// Simple boolean shortcut: true when initialization is fully complete.
final appInitCompleteProvider = Provider<bool>((ref) {
  final state = ref.watch(appInitProvider);
  return state.valueOrNull?.isComplete ?? false;
});
