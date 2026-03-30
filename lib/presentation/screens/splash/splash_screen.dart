import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  final List<String> posters = [
    'poster/animal.webp',
    'poster/attack on titan.webp',
    'poster/avengers endgmae.webp',
    'poster/bahubali the epic.webp',
    'poster/ben 10.webp',
    'poster/bloodhounds.webp',
    'poster/breaking bad.webp',
    'poster/death note.webp',
    'poster/demon slayer.webp',
    'poster/elite.webp',
    'poster/frozen.webp',
    'poster/game of thrones.webp',
    'poster/john wick.webp',
    'poster/justice league.webp',
    'poster/maula jatt.webp',
    'poster/minions.webp',
    'poster/money heist.webp',
    'poster/my demon.webp',
    'poster/my name.webp',
    'poster/nobody.webp',
    'poster/openheimer.webp',
    'poster/pathaan.webp',
    'poster/peaky blinders.webp',
    'poster/solo leveling.webp',
    'poster/squid game.webp',
    'poster/star wars.webp',
    'poster/stranger things.webp',
    'poster/tangled.webp',
    'poster/terminator dark fate.webp',
    'poster/vinsenzo.webp',
    'poster/walking dead.webp',
    'poster/war.webp',
    'poster/when life gives you.webp',
    'poster/x-men.webp',
  ];

  late List<String> col1;
  late List<String> col2;
  late List<String> col3;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    
    // Initialize fade-out animation
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Randomize posters for each column
    var shuffled = List<String>.from(posters)..shuffle();
    col1 = shuffled.sublist(0, (posters.length / 3).floor());
    
    shuffled = List<String>.from(posters)..shuffle();
    col2 = shuffled.sublist(0, (posters.length / 3).floor());
    
    shuffled = List<String>.from(posters)..shuffle();
    col3 = shuffled.sublist(0, (posters.length / 3).floor());

    // Start fade out slightly before 5 seconds
    Timer(const Duration(milliseconds: 4000), () {
      if (mounted) {
        _fadeController.forward();
      }
    });

    Timer(const Duration(milliseconds: 5000), () {
      if (mounted) {
        context.go('/home');
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // Background posters marquee
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
            
            // Centered Branding
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'DANIEWATCH',
                        style: GoogleFonts.outfit(
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 10,
                          color: Colors.white,
                          shadows: [
                            const Shadow(
                              blurRadius: 30,
                              color: Colors.black,
                              offset: Offset(0, 0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'STREAMING REIMAGINED',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 6,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

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
            child: Image.asset(
              extendedImages[index],
              height: 170, // Reduced height for denser grid
              fit: BoxFit.cover,
            ),
          ),
        );
      },
    );
  }
}
