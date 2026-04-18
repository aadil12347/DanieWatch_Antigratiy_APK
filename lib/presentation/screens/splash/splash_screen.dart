import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/manifest_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/splash_provider.dart';
import '../auth/auth_screen.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/notification_service.dart';

class SplashScreen extends ConsumerStatefulWidget {

  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  List<String> col1 = [];
  List<String> col2 = [];
  List<String> col3 = [];
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _showAuthModal = false;
  bool _isLogin = false;
  late DateTime _startTime;

  ProviderSubscription<AsyncValue<dynamic>>? _authSub;
  ProviderSubscription<AsyncValue<dynamic>>? _manifestSub;
  ProviderSubscription<AsyncValue<List<String>>>? _postersSub;

  // TWO-LOCK navigation system:
  // _isTransitioning: temporary lock that prevents concurrent async executions
  // _hasNavigated: permanent one-way latch — once true, context.go() is NEVER called again
  // Both must be checked SYNCHRONOUSLY before any await
  bool _isTransitioning = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _startTime = DateTime.now();
    _checkFirstRun();

    // CRITICAL FIX: To listen outside of build, we must use ref.listenManual
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Evaluate immediately on first frame
      _evaluateTransition();

      _authSub = ref.listenManual(authStateProvider, (previous, next) {
        debugPrint('SplashScreen: auth changed. User: ${next.valueOrNull?.id}');
        _evaluateTransition();
      });

      _manifestSub = ref.listenManual(manifestProvider, (previous, next) {
        debugPrint('SplashScreen: manifest changed. Available: ${next.valueOrNull != null}');
        _evaluateTransition();
      });

      _postersSub = ref.listenManual<AsyncValue<List<String>>>(trendingPostersProvider, (previous, next) {
        if (next.hasValue && next.value != null) {
          _initializePosters(next.value!);
        }
      });
    });
  }

  void _initializePosters(List<String> allPosters) {
    if (allPosters.isEmpty || col1.isNotEmpty) return;
    final shuffled = List<String>.from(allPosters)..shuffle();
    final count = (shuffled.length / 3).floor();
    if (mounted) {
      setState(() {
        col1 = shuffled.sublist(0, count);
        col2 = shuffled.sublist(count, count * 2);
        col3 = shuffled.sublist(count * 2);
      });
    }
  }

  Future<void> _checkFirstRun() async {
    final prefs = await SharedPreferences.getInstance();
    final isFirstRun = prefs.getBool('is_first_run') ?? true;
    if (mounted) {
      setState(() => _isLogin = !isFirstRun);
    }
    if (isFirstRun) {
      await prefs.setBool('is_first_run', false);
    }
  }

  void _evaluateTransition() async {
    // SYNCHRONOUS GUARD — checked before ANY await so there is zero race window.
    if (_hasNavigated || _isTransitioning) return;

    _isTransitioning = true;

    final authState = ref.read(authStateProvider);
    final user = authState.valueOrNull;
    final manifestAsync = ref.read(manifestProvider);
    final manifest = manifestAsync.valueOrNull;

    // ── CASE 1: Auth is still resolving ──────────────────────────────────────
    if (authState.isLoading) {
      _isTransitioning = false; // Release lock — wait for listener to call us again
      return;
    }

    // ── CASE 2: User IS logged in ─────────────────────────────────────────────
    if (user != null) {
      if (manifest == null) {
        // Manifest not ready yet. Release lock and wait for manifest listener.
        _isTransitioning = false;
        return;
      }

      // Both user and manifest confirmed. Enforce minimum splash display time.
      final elapsed = DateTime.now().difference(_startTime);
      const minDuration = Duration(milliseconds: 5000);
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }

      // After every await: check mounted and _hasNavigated before continuing.
      if (!mounted || _hasNavigated) return;

      // Play the exit animation
      await _fadeController.forward();

      // Check again after animation completes
      if (!mounted || _hasNavigated) return;

      // SET THE PERMANENT LATCH synchronously — this guarantees context.go()
      // is called EXACTLY once, no matter how many listeners fire.
      _hasNavigated = true;
      try {
        // Check for pending notification deep link
        final pending = NotificationService.instance.consumePendingPayload();
        final navigateTo = pending?['navigate_to']?.toString();

        if (navigateTo == 'notifications') {
          // Notification tap: go to notifications page (bell icon)
          // Re-set highlightTmdbId from payload so NotificationsScreen can read it
          final hlId = pending?['highlight_tmdb_id']?.toString();
          if (hlId != null && hlId.isNotEmpty) {
            NotificationService.instance.highlightTmdbId = hlId;
          }
          debugPrint('📱 Deep linking to /notifications (highlight=$hlId)');
          if (AppRouter.rootNavKey.currentContext != null) {
            AppRouter.rootNavKey.currentContext!.go('/notifications');
          } else if (context.mounted) {
            context.go('/notifications');
          }
        } else {
          // Normal app launch
          if (AppRouter.rootNavKey.currentContext != null) {
            AppRouter.rootNavKey.currentContext!.go('/home');
          } else if (context.mounted) {
            context.go('/home');
          }
        }
        // Fetch new posters in background for next launch
        fetchAndCachePosters();
      } catch (e) {
        debugPrint('SplashScreen: Exception during context.go: $e');
      }
      return;
    }

    // ── CASE 3: User is NOT logged in — show auth modal ──────────────────────
    final elapsed = DateTime.now().difference(_startTime);
    const minDuration = Duration(milliseconds: 5000);
    if (elapsed < minDuration) {
      await Future.delayed(minDuration - elapsed);
    }

    if (!mounted) return;

    setState(() => _showAuthModal = true);

    // Release the lock here — NOT _hasNavigated — because the user still needs
    // to log in, and when they do, _evaluateTransition must run again (Case 2).
    _isTransitioning = false;
  }

  @override
  void dispose() {
    debugPrint('SplashScreen: DISPOSED.');
    _authSub?.close();
    _manifestSub?.close();
    _postersSub?.close();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // build() is for UI ONLY. Zero ref.listen calls here — they are all in initState.

    // ref.watch is safe in build() because it does not register a navigation callback.
    // It only causes a rebuild, which is harmless since build() has no side effects.
    final postersAsync = ref.watch(trendingPostersProvider);
    if (postersAsync.hasValue && col1.isEmpty) {
      Future.microtask(() => _initializePosters(postersAsync.value!));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            if (col1.isNotEmpty)
              Row(
                children: [
                  Expanded(child: MarqueeColumn(images: col1, speed: 40, isReverse: false)),
                  const SizedBox(width: 8),
                  Expanded(child: MarqueeColumn(images: col2, speed: 30, isReverse: true)),
                  const SizedBox(width: 8),
                  Expanded(child: MarqueeColumn(images: col3, speed: 50, isReverse: false)),
                ],
              ),

            Positioned(
              top: 0, left: 0, right: 0, height: 250,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.95),
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0, left: 0, right: 0, height: 350,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(1.0),
                      Colors.black.withOpacity(0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              bottom: 50, left: 0, right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_showAuthModal)
                    const SizedBox(
                      width: 24, height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    'Created by Daniyal',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),

            if (_showAuthModal)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.6),
                  child: Center(
                    child: AuthScreen(
                      isLogin: _isLogin,
                      onToggle: () => setState(() => _isLogin = !_isLogin),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class MarqueeColumn extends StatefulWidget {
  final List<String> images;
  final double speed;
  final bool isReverse;

  const MarqueeColumn({
    super.key,
    required this.images,
    required this.speed,
    this.isReverse = false,
  });

  @override
  State<MarqueeColumn> createState() => _MarqueeColumnState();
}

class _MarqueeColumnState extends State<MarqueeColumn> {
  late ScrollController _scrollController;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: widget.isReverse ? 2000 : 0,
    );
    
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() {
    const duration = Duration(milliseconds: 30);
    
    _timer = Timer.periodic(duration, (timer) {
      if (!mounted || !_scrollController.hasClients) {
        timer.cancel();
        return;
      }
      
      try {
        double maxScroll = _scrollController.position.maxScrollExtent;
        double currentScroll = _scrollController.offset;
        
        if (widget.isReverse) {
          double nextScroll = currentScroll - (widget.speed / 100);
          if (nextScroll <= 0) {
            _scrollController.jumpTo(maxScroll / 2);
          } else {
            _scrollController.jumpTo(nextScroll);
          }
        } else {
          double nextScroll = currentScroll + (widget.speed / 100);
          if (nextScroll >= maxScroll) {
            _scrollController.jumpTo(maxScroll / 2);
          } else {
            _scrollController.jumpTo(nextScroll);
          }
        }
      } catch (e) {
        // Safe catch for controller disposal issues during transition
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    if (_timer.isActive) _timer.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extendedImages = [...widget.images, ...widget.images, ...widget.images, ...widget.images];
    
    return ListView.builder(
      controller: _scrollController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: extendedImages.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: extendedImages[index],
              height: 170,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                height: 170,
                color: Colors.white10,
              ),
              errorWidget: (context, url, error) => Container(
                height: 170,
                color: Colors.white10,
                child: const Icon(Icons.movie_filter_outlined, color: Colors.white24),
              ),
            ),
          ),
        );
      },
    );
  }
}
