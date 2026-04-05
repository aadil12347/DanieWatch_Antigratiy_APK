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

  @override
  void initState() {
    super.initState();
    
    // Initialize fade-out animation
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Check for first run to decide between Sign Up / Sign In default
    _checkFirstRun();
    
    // Transition control
    _evaluateTransition();
  }
  
  void _initializePosters(List<String> allPosters) {
    if (allPosters.isEmpty || col1.isNotEmpty) return;
    
    final shuffled = List<String>.from(allPosters)..shuffle();
    final count = (shuffled.length / 3).floor();
    
    setState(() {
      col1 = shuffled.sublist(0, count);
      col2 = shuffled.sublist(count, count * 2);
      col3 = shuffled.sublist(count * 2);
    });
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
    // 1. Mandatory 5 second cinematic delay
    await Future.delayed(const Duration(milliseconds: 5000));

    // 2. Wait until manifest is loaded with a 3-second safety timeout
    bool isLoaded = false;
    int retryCount = 0;
    while (!isLoaded && mounted && retryCount < 6) { // 6 * 500ms = 3 seconds
      final manifestAsync = ref.read(manifestProvider);
      if (!manifestAsync.isLoading) {
        isLoaded = true;
      }
      
      if (!isLoaded) {
        await Future.delayed(const Duration(milliseconds: 500));
        retryCount++;
      }
    }

    if (mounted) {
      // 3. Mark splash as "ready" and transition
      final user = ref.read(authStateProvider).valueOrNull;
      
      if (user == null) {
        // Show Auth Modal if not logged in
        setState(() => _showAuthModal = true);
      } else {
        // Transition to Home if already logged in
        _fadeController.forward().then((_) {
          if (mounted) context.go('/home');
        });
      }
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state changes (e.g., successful login)
    ref.listen<AsyncValue<User?>>(authStateProvider, (previous, next) {
      final user = next.valueOrNull;
      if (user != null && mounted) {
        // 1. Hide modal immediately
        if (_showAuthModal) {
          setState(() => _showAuthModal = false);
        }
        
        // 2. Start the transition to Home if not already transitioning
        if (_fadeController.status != AnimationStatus.forward && 
            _fadeController.status != AnimationStatus.completed) {
          
          _fadeController.forward().then((_) {
            if (mounted) context.go('/home');
          });
        }
      }
    });

    final postersAsync = ref.watch(trendingPostersProvider);
    
    // Initialize posters only once when data arrives
    postersAsync.whenData((posters) => _initializePosters(posters));

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
            // Top Vignette
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 250,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.95),
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Bottom Vignette
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 350,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 1.0),
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            
            // Branding Removed as per request
            // const Center(...) was here

            // Bottom Text & Spinner
            Positioned(
              bottom: 50,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
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
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            
            // Auth Modal Overlay
            if (_showAuthModal)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
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

class _MarqueeColumnState extends State<MarqueeColumn> with SingleTickerProviderStateMixin {
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
      if (!_scrollController.hasClients) return;
      
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
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We duplicate the list to make it look infinite
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
              height: 170, // Reduced height for denser grid
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
