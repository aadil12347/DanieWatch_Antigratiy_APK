import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';

/// Main application widget.
///
/// DanieWatch is an offline-first streaming catalog app that:
/// - Caches manifest from Supabase Storage for offline access
/// - Enriches content with TMDB API data
/// - Supports local watchlist and continue watching features
class DanieWatchApp extends ConsumerWidget {
  const DanieWatchApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    return MaterialApp.router(
      title: 'DanieWatch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) {
        return child ?? const SizedBox();
      },
    );
  }
}
