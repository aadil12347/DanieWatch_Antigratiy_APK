import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_init_provider.dart';

/// Premium loading overlay shown during first-time app initialization.
/// Displays a pulsing DanieWatch logo, a progress bar, and step messages.
/// Automatically fades out when initialization completes.
class AppInitOverlay extends ConsumerStatefulWidget {
  const AppInitOverlay({super.key});

  @override
  ConsumerState<AppInitOverlay> createState() => _AppInitOverlayState();
}

class _AppInitOverlayState extends ConsumerState<AppInitOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initState = ref.watch(appInitProvider);
    final state = initState.valueOrNull ?? const AppInitState();

    // Once complete, trigger dismissal
    if (state.isComplete && !_dismissed) {
      _dismissed = true;
    }

    return IgnorePointer(
      ignoring: _dismissed,
      child: AnimatedOpacity(
        opacity: _dismissed ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF0A0A0A),
                  Color(0xFF0D0D0D),
                  Color(0xFF0A0A0A),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(flex: 3),

                  // Pulsing logo
                  AnimatedBuilder2(
                    listenable: _pulseAnimation,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _pulseAnimation.value,
                        child: Transform.scale(
                          scale: 0.95 + (_pulseAnimation.value * 0.05),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFFFFC107),
                                Color(0xFFFF9800),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFC107).withValues(alpha: 0.3),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.black,
                            size: 44,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'DanieWatch',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Progress section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Column(
                      children: [
                        // Step message
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            state.message,
                            key: ValueKey(state.message),
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white54,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Progress bar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            height: 3,
                            child: _AnimatedProgressBar(
                              progress: state.progress.clamp(0.05, 1.0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Subtle bottom text
                  Padding(
                    padding: const EdgeInsets.only(bottom: 32),
                    child: Text(
                      'First-time setup • Please wait',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: Colors.white24,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Simple AnimatedWidget wrapper for pulse animation.
class AnimatedBuilder2 extends AnimatedWidget {
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder2({
    super.key,
    required super.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

/// Animated progress bar that smoothly transitions width.
class _AnimatedProgressBar extends StatelessWidget {
  final double progress;
  const _AnimatedProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Background track
            Container(
              width: constraints.maxWidth,
              height: 3,
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // Animated fill
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              width: constraints.maxWidth * progress,
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFFC107),
                    Color(0xFFFF9800),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
