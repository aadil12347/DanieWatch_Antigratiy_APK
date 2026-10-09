import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/env.dart';
import '../../data/local/database.dart';
import '../../services/extraction/movie_site_scraper_service.dart';

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

/// StreamProvider that performs app initialization.
///
/// SHELL-FIRST: Yields `isComplete = true` IMMEDIATELY so the UI renders
/// without waiting. All heavy work (DB, cache, Supabase) runs in background.
final appInitProvider = StreamProvider<AppInitState>((ref) async* {
  // ═══════════════════════════════════════════════════════════════════════════
  // INSTANT YIELD — UI can render NOW, zero blocking
  // ═══════════════════════════════════════════════════════════════════════════
  yield const AppInitState(
    phase: InitPhase.ready,
    message: 'Ready!',
    progress: 1.0,
    isComplete: true,
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKGROUND INIT — fire and forget, does NOT block the stream or UI
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void>(() async {
    final sw = Stopwatch()..start();

    // Step 0: Version check + cache clear
    bool cacheCleared = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastVersion = prefs.getString(_lastVersionKey);
      final currentVersion = Env.appVersion;

      if (lastVersion == null || lastVersion != currentVersion) {
        debugPrint('[AppInit] 🔄 Version changed ($lastVersion → $currentVersion) — clearing old caches');
        await MovieSiteScraperService.instance.clearDiskCache();
        MovieSiteScraperService.instance.clearCache();
        cacheCleared = true;
        await prefs.setString(_lastVersionKey, currentVersion);
        debugPrint('[AppInit] ✅ Old caches cleared');
      } else {
        debugPrint('[AppInit] ✅ Same version ($currentVersion) — caches valid');
      }
    } catch (e) {
      debugPrint('[AppInit] ⚠️ Version check error: $e');
    }

    // Step 1: Database init
    try {
      await AppDatabase.instance.initialize();
      debugPrint('[AppInit] ✅ Database initialized in ${sw.elapsedMilliseconds}ms');

      if (cacheCleared) {
        try {
          await AppDatabase.instance.db.delete('tmdb_cache');
          debugPrint('[AppInit] ✅ TMDB cache table cleared');
        } catch (e) {
          debugPrint('[AppInit] ⚠️ TMDB cache clear error: $e');
        }
      }
    } catch (e) {
      debugPrint('[AppInit] ⚠️ Database init error: $e');
    }

    // Step 2: Load disk cache / bundled base data (instant)
    try {
      await MovieSiteScraperService.instance.loadDiskCache();
      debugPrint('[AppInit] ✅ Disk cache / base data loaded in ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('[AppInit] ⚠️ Disk cache load error: $e');
    }

    sw.stop();
    debugPrint('[AppInit] 🚀 All foreground init complete in ${sw.elapsedMilliseconds}ms');
  });
});

/// Simple boolean shortcut: true when initialization is fully complete.
final appInitCompleteProvider = Provider<bool>((ref) {
  final state = ref.watch(appInitProvider);
  return state.valueOrNull?.isComplete ?? false;
});
