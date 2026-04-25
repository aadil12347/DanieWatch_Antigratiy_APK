import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'data/local/database.dart';
import 'data/local/download_manager.dart';
import 'core/utils/restart_widget.dart';
import 'pip/pip_controller.dart';
import 'core/services/notification_service.dart';

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

    // Force portrait orientation and hide status/nav bars globally
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );

    // Immersive status bar
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0A0A0A),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Initialize local SQLite database
    await AppDatabase.instance.initialize();

    // Initialize Download Manager
    await DownloadManager.instance.initialize();

    // Initialize Supabase
    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
    );

    // Initialize PIP Controller for handling cold recovery
    PipController.instance.init();

    // Initialize Firebase and Notifications
    await NotificationService.instance.initialize();

    // Remove splash screen just before running the app
    FlutterNativeSplash.remove();

    runApp(
      const RestartWidget(
        child: ProviderScope(
          child: DanieWatchApp(),
        ),
      ),
    );
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
