import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/manifest_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/splash_provider.dart';
import '../auth/auth_screen.dart';

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
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize fade-out animation
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _startTime = DateTime.now();

    // Check for first run to decide between Sign Up / Sign In default
    _checkFirstRun();
    
    // Initial evaluation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _evaluateTransition();
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
      setState(() {
        _isLogin = !isFirstRun;
      });
    }
    
    if (isFirstRun) {
      await prefs.setBool('is_first_run', false);
    }
  }

  void _evaluateTransition() async {
    if (_isTransitioning) {
      return;
    }
    
    final authState = ref.read(authStateProvider);
    final user = authState.valueOrNull;
    final manifestAsync = ref.read(manifestProvider);
    final manifest = manifestAsync.valueOrNull;

    // 1. Logged in case (Wait for manifest)
    if (user != null) {
      if (manifest == null) return; 

      _isTransitioning = true;
      
      final elapsed = DateTime.now().difference(_startTime);
      final minDuration = const Duration(milliseconds: 5000);
      
      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }

      if (!mounted) return;

      debugPrint('SplashScreen: Starting exit animation...');
      _fadeController.forward().then((_) {
        if (mounted) {
          // Final safety: ensure we are on the current frame and still mounted
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
               debugPrint('SplashScreen: Navigating to HOME via GoRouter.');
               context.go('/home');
            }
          });
        }
      });
    } 
    // 2. Logged out case (Show Auth Modal)
    else if (!authState.isLoading && user == null) {
      _isTransitioning = true;

      final elapsed = DateTime.now().difference(_startTime);
      const minDuration = Duration(milliseconds: 5000);

      if (elapsed < minDuration) {
        await Future.delayed(minDuration - elapsed);
      }

      if (!mounted) return;

      setState(() {
        _showAuthModal = true;
      });
      _isTransitioning = false;
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth state to trigger transitions
    ref.listen(authStateProvider, (previous, next) {
      debugPrint('SplashScreen: authStateProvider changed. Authenticated: ${next.valueOrNull != null}');
      _evaluateTransition();
    });

    // Also watch manifest to trigger transitions when it becomes available
    ref.listen(manifestProvider, (previous, next) {
      debugPrint('SplashScreen: manifestProvider changed. Available: ${next.valueOrNull != null}');
      _evaluateTransition();
    });

    // Listen for posters to initialize columns safely
    ref.listen<AsyncValue<List<String>>>(trendingPostersProvider, (previous, next) {
      if (next.hasValue && next.value != null) {
        _initializePosters(next.value!);
      }
    });

    // Initial check if data is already available
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
            // Background posters marquee
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
            
            // Vignette Effects
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
            
            // Bottom Text & Spinner
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
            
            // Auth Modal Overlay
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
      if (!mounted || _scrollController == null || !_scrollController.hasClients) {
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
            child: Image.network(
              extendedImages[index],
              height: 170,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
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
