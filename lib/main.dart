import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'data/local/database.dart';
import 'data/local/download_manager.dart';
import 'data/services/database_sync_service.dart';
import 'core/utils/restart_widget.dart';
import 'pip/pip_controller.dart';
import 'core/services/notification_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/app_update_service.dart';
import 'services/extraction/movie_site_scraper_service.dart';

/// Global completer so splash/router can await Supabase readiness.
final Completer<void> supabaseReady = Completer<void>();

/// Synchronous session heuristic read during startup (before Supabase init).
/// Set to true after first successful login, cleared on logout.
bool hasPersistedSession = false;

Future<void> main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Validate required environment variables are configured via --dart-define
  Env.validate();

  try {
    // Override the default release-mode blank screen error behavior
    ErrorWidget.builder = (FlutterErrorDetails details) {
      debugPrint('----------------------------------------');
      debugPrint('CRITICAL UI BUILD ERROR DETECTED');
      debugPrint('Exception: ${details.exception}');
      debugPrint('Stack Trace: \n${details.stack}');
      debugPrint('----------------------------------------');

      return Material(
        color: const Color(0xFF0F0F0F),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: Color(0xFFFF3B30), size: 48),
                const SizedBox(height: 16),
                Text(
                  'UI Build Error',
                  style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  details.exception.toString(),
                  style: GoogleFonts.inter(fontSize: 14, color: Colors.white60),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    };

    // System styling (synchronous / non-blocking)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0A0A0A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // ── PHASE 1: ONLY instant local work before UI (<200ms) ──────────────
    // Read session flag synchronously so we know whether to skip splash.
    final prefs = await SharedPreferences.getInstance();
    hasPersistedSession = prefs.getBool('has_session') ?? false;

    await Future.wait([
      Env.loadAppVersion(),
      AppDatabase.instance.initialize(),
      MovieSiteScraperService.instance.loadDiskCache(),
    ]);

    // Remove native splash immediately — launch UI NOW!
    FlutterNativeSplash.remove();

    runApp(
      const RestartWidget(
        child: ProviderScope(
          child: DanieWatchApp(),
        ),
      ),
    );

    // ── PHASE 2: Background init — Supabase + services AFTER UI renders ──
    Future.microtask(() async {
      try {
        // Supabase is the heaviest — network-bound 1-2.5s.
        // UI is already visible, so this runs in parallel.
        await Supabase.initialize(
          url: Env.supabaseUrl,
          anonKey: Env.supabaseAnonKey,
        );
        if (!supabaseReady.isCompleted) supabaseReady.complete();
        debugPrint('[Startup] ✅ Supabase ready');

        // Persist session flag for next cold start
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          prefs.setBool('has_session', true);
        }

        // Non-critical services — fire & forget
        PipController.instance.init();
        DownloadManager.instance.initialize();
        NotificationService.instance.initialize();
        DeepLinkService.instance.initialize();
        AppUpdateService.instance.cleanupIfNeeded();
        DatabaseSyncService.instance.syncIndex();
      } catch (e) {
        debugPrint('[Startup] Background service init warning: $e');
        if (!supabaseReady.isCompleted) supabaseReady.completeError(e);
      }
    });
  } catch (e, stackTrace) {
    // Ensure splash is removed even on failure to show error UI
    FlutterNativeSplash.remove();

    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.red[900],
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Failed to Initialize App',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Text(e.toString(),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 16),
                  Text(stackTrace.toString(),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
