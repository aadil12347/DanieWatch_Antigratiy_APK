import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import 'player_controller.dart';

class PlayerGestures extends StatefulWidget {
  final PlayerController controller;
  final Widget child;

  const PlayerGestures({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<PlayerGestures> createState() => _PlayerGesturesState();
}

class _PlayerGesturesState extends State<PlayerGestures>
    with TickerProviderStateMixin {
  // ─── Gesture state ──────────────────────────────────────────────────────
  bool _isHorizontalDrag = false;
  bool _isVerticalDrag = false;
  bool _isLeftSide = false;

  // ─── Double-tap seek ────────────────────────────────────────────────────
  bool _showLeftSeek = false;
  bool _showRightSeek = false;
  int _seekSeconds = 0;
  Timer? _seekResetTimer;

  // ─── Long-press 2x speed ───────────────────────────────────────────────
  bool _isLongPressing = false;
  double _savedSpeed = 1.0;

  // ─── Swipe seek ────────────────────────────────────────────────────────
  Duration _seekPreviewPosition = Duration.zero;
  Duration _seekStartPosition = Duration.zero;
  bool _showSeekPreview = false;

  // ─── Volume/Brightness ─────────────────────────────────────────────────
  double _currentVolume = 0.5;
  double _currentBrightness = 0.5;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;

  // ─── Pinch-to-zoom (YouTube style: Zoomed to fill vs Original) ───────────
  final Map<int, Offset> _pointerPositions = {};
  double? _initialPinchDistance;
  bool _pinchTriggered = false;
  bool _showPinchToast = false;
  bool _pinchToastIsFill = false;
  Timer? _pinchToastTimer;

  // ─── Animations ────────────────────────────────────────────────────────
  late AnimationController _leftSeekAnim;
  late AnimationController _rightSeekAnim;
  late AnimationController _speedPillAnim;

  @override
  void initState() {
    super.initState();
    _leftSeekAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _rightSeekAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _speedPillAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _initVolumeAndBrightness();
  }

  Future<void> _initVolumeAndBrightness() async {
    try {
      VolumeController.instance.showSystemUI = false;
      _currentVolume = await VolumeController.instance.getVolume();
      _currentBrightness = await ScreenBrightness().current;
    } catch (_) {
      _currentVolume = 0.5;
      _currentBrightness = 0.5;
    }
  }

  @override
  void dispose() {
    _pinchToastTimer?.cancel();
    _seekResetTimer?.cancel();
    _leftSeekAnim.dispose();
    _rightSeekAnim.dispose();
    _speedPillAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Stack(
      children: [
        // Video layer + gesture detector wrapped with raw multi-touch listener for pinch
        Listener(
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onTap,
            onDoubleTapDown: (details) => _onDoubleTapDown(details, context),
            onDoubleTap: () {},
            onLongPressStart: _onLongPressStart,
            onLongPressEnd: _onLongPressEnd,
            onVerticalDragStart: _onVerticalDragStart,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            onHorizontalDragStart: _onHorizontalDragStart,
            onHorizontalDragUpdate: _onHorizontalDragUpdate,
            onHorizontalDragEnd: _onHorizontalDragEnd,
            child: widget.child,
          ),
        ),

        // YouTube-style Pinch-to-Zoom Toast Pill (Top Center)
        if (_showPinchToast)
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, val, child) {
                  return Opacity(
                    opacity: val,
                    child: Transform.scale(
                      scale: 0.90 + (0.10 * val),
                      child: child,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xE614151F),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                      width: 1.0,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black87,
                        blurRadius: 18,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _pinchToastIsFill ? Icons.fullscreen_rounded : Icons.fit_screen_rounded,
                        color: _pinchToastIsFill ? const Color(0xFFE50914) : Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _pinchToastIsFill ? 'Zoomed to fill' : 'Original',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Left double-tap seek ripple
        if (_showLeftSeek)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: screenWidth * 0.4,
            child: _SeekRipple(
              isForward: false,
              seconds: _seekSeconds,
              animation: _leftSeekAnim,
            ),
          ),

        // Right double-tap seek ripple
        if (_showRightSeek)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: screenWidth * 0.4,
            child: _SeekRipple(
              isForward: true,
              seconds: _seekSeconds,
              animation: _rightSeekAnim,
            ),
          ),

        // 2X Speed subtle minimal indicator (top center)
        if (_isLongPressing)
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Center(
              child: FadeTransition(
                opacity: _speedPillAnim,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fast_forward_rounded, color: Colors.white70, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        '2x',
                        style: GoogleFonts.inter(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Horizontal swipe seek preview overlay
        if (_showSeekPreview)
          Center(
            child: _buildSwipeSeekOverlay(),
          ),

        // Volume indicator (right side)
        if (_showVolumeIndicator)
          Positioned(
            right: 28,
            top: 0,
            bottom: 0,
            child: Center(
              child: _VerticalIndicator(
                value: _currentVolume,
                icon: _currentVolume > 0.5
                    ? Icons.volume_up_rounded
                    : (_currentVolume > 0 ? Icons.volume_down_rounded : Icons.volume_mute_rounded),
                label: '${(_currentVolume * 100).toInt()}%',
                title: 'Volume',
              ),
            ),
          ),

        // Brightness indicator (left side)
        if (_showBrightnessIndicator)
          Positioned(
            left: 28,
            top: 0,
            bottom: 0,
            child: Center(
              child: _VerticalIndicator(
                value: _currentBrightness,
                icon: _currentBrightness > 0.6
                    ? Icons.brightness_7_rounded
                    : (_currentBrightness > 0.3 ? Icons.brightness_6_rounded : Icons.brightness_5_rounded),
                label: '${(_currentBrightness * 100).toInt()}%',
                title: 'Brightness',
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSwipeSeekOverlay() {
    final diff = _seekPreviewPosition - _seekStartPosition;
    final isForward = diff.inMilliseconds >= 0;
    final diffSeconds = (diff.inMilliseconds.abs() / 1000).round();
    final diffText = isForward ? '+$diffSeconds s' : '-$diffSeconds s';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 20,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
                color: isForward ? const Color(0xFF00E5FF) : AppColors.primary,
                size: 26,
              ),
              const SizedBox(width: 8),
              Text(
                diffText,
                style: GoogleFonts.plusJakartaSans(
                  color: isForward ? const Color(0xFF00E5FF) : AppColors.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatDuration(_seekPreviewPosition)} / ${_formatDuration(widget.controller.duration)}',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Single tap ─────────────────────────────────────────────────────────

  void _onTap() {
    if (widget.controller.isLocked) {
      widget.controller.showControls();
      return;
    }
    widget.controller.toggleControls();
  }

  // ─── Pinch-to-zoom Pointer Handlers (YouTube style) ──────────────────────

  void _onPointerDown(PointerDownEvent event) {
    _pointerPositions[event.pointer] = event.position;
    if (_pointerPositions.length == 2) {
      final pts = _pointerPositions.values.toList();
      _initialPinchDistance = (pts[0] - pts[1]).distance;
      _pinchTriggered = false;
      // Abort any ongoing vertical / horizontal drag so it doesn't conflict with pinch
      if (_isVerticalDrag) {
        _isVerticalDrag = false;
        _showVolumeIndicator = false;
        _showBrightnessIndicator = false;
      }
      if (_isHorizontalDrag) {
        _isHorizontalDrag = false;
        _showSeekPreview = false;
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointerPositions[event.pointer] = event.position;
    if (_pointerPositions.length >= 2 &&
        _initialPinchDistance != null &&
        _initialPinchDistance! > 20) {
      final pts = _pointerPositions.values.toList();
      final currentDistance = (pts[0] - pts[1]).distance;
      final scale = currentDistance / _initialPinchDistance!;

      if (!_pinchTriggered) {
        if (scale >= 1.15) {
          // Pinch Zoom Out / Spread fingers -> Zoomed to fill (BoxFit.cover)
          _pinchTriggered = true;
          _triggerPinch(fill: true);
        } else if (scale <= 0.85) {
          // Pinch Zoom In / Contract fingers -> Original / Fit screen (BoxFit.contain)
          _pinchTriggered = true;
          _triggerPinch(fill: false);
        }
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointerPositions.remove(event.pointer);
    if (_pointerPositions.length < 2) {
      _initialPinchDistance = null;
      _pinchTriggered = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointerPositions.remove(event.pointer);
    if (_pointerPositions.length < 2) {
      _initialPinchDistance = null;
      _pinchTriggered = false;
    }
  }

  void _triggerPinch({required bool fill}) {
    if (widget.controller.isLocked) return;

    final targetMode = fill ? VideoResizeMode.fill : VideoResizeMode.fit;
    widget.controller.setResizeMode(targetMode);
    widget.controller.hideControls();

    _pinchToastTimer?.cancel();
    setState(() {
      _pinchToastIsFill = fill;
      _showPinchToast = true;
    });

    _pinchToastTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _showPinchToast = false);
      }
    });
  }

  // ─── Double-tap seek ────────────────────────────────────────────────────

  void _onDoubleTapDown(TapDownDetails details, BuildContext context) {
    if (widget.controller.isLocked || _pointerPositions.length >= 2) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = details.globalPosition.dx;
    final isLeft = tapX < screenWidth / 2;

    _seekSeconds = 10;

    if (isLeft) {
      widget.controller.skipBackward();
      setState(() {
        _showLeftSeek = true;
        _showRightSeek = false;
      });
      _leftSeekAnim.forward(from: 0);
    } else {
      widget.controller.skipForward();
      setState(() {
        _showRightSeek = true;
        _showLeftSeek = false;
      });
      _rightSeekAnim.forward(from: 0);
    }

    _seekResetTimer?.cancel();
    _seekResetTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showLeftSeek = false;
          _showRightSeek = false;
        });
      }
    });
  }

  // ─── Long-press 2x speed ───────────────────────────────────────────────

  void _onLongPressStart(LongPressStartDetails details) {
    if (widget.controller.isLocked || _pointerPositions.length >= 2) return;
    _savedSpeed = widget.controller.playbackSpeed;
    widget.controller.setPlaybackSpeed(2.0);
    setState(() => _isLongPressing = true);
    _speedPillAnim.forward();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (widget.controller.isLocked) return;
    widget.controller.setPlaybackSpeed(_savedSpeed);
    setState(() => _isLongPressing = false);
    _speedPillAnim.reverse();
  }

  // ─── Vertical drag (volume/brightness) ──────────────────────────────────

  void _onVerticalDragStart(DragStartDetails details) {
    if (widget.controller.isLocked || _pointerPositions.length >= 2) return;
    final screenWidth = MediaQuery.of(context).size.width;
    _isLeftSide = details.globalPosition.dx < screenWidth / 2;
    _isVerticalDrag = true;

    setState(() {
      if (_isLeftSide) {
        _showBrightnessIndicator = true;
      } else {
        _showVolumeIndicator = true;
      }
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isVerticalDrag || widget.controller.isLocked || _pointerPositions.length >= 2) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final delta = -details.delta.dy / (screenHeight * 0.55);

    if (_isLeftSide) {
      _currentBrightness = (_currentBrightness + delta).clamp(0.0, 1.0);
      try {
        ScreenBrightness().setScreenBrightness(_currentBrightness);
      } catch (_) {}
    } else {
      _currentVolume = (_currentVolume + delta).clamp(0.0, 1.0);
      try {
        VolumeController.instance.showSystemUI = false;
        VolumeController.instance.setVolume(_currentVolume);
      } catch (_) {}
    }

    setState(() {});
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isVerticalDrag = false;
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = false;
          _showBrightnessIndicator = false;
        });
      }
    });
  }

  // ─── Horizontal drag (swipe seek) ───────────────────────────────────────

  void _onHorizontalDragStart(DragStartDetails details) {
    if (widget.controller.isLocked || _pointerPositions.length >= 2) return;
    _isHorizontalDrag = true;
    _seekStartPosition = widget.controller.position;
    _seekPreviewPosition = widget.controller.position;
    setState(() => _showSeekPreview = true);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isHorizontalDrag || widget.controller.isLocked || _pointerPositions.length >= 2) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final delta = details.delta.dx / screenWidth;
    final totalMs = widget.controller.duration.inMilliseconds;
    // Scrub factor
    final seekDeltaMs = (delta * (totalMs > 0 ? totalMs : 60000) * 0.20).toInt();

    _seekPreviewPosition = (_seekPreviewPosition + Duration(milliseconds: seekDeltaMs));
    if (_seekPreviewPosition < Duration.zero) _seekPreviewPosition = Duration.zero;
    if (_seekPreviewPosition > widget.controller.duration && widget.controller.duration > Duration.zero) {
      _seekPreviewPosition = widget.controller.duration;
    }

    setState(() {});
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isHorizontalDrag && !widget.controller.isLocked) {
      widget.controller.seekTo(_seekPreviewPosition);
    }
    _isHorizontalDrag = false;
    setState(() => _showSeekPreview = false);
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// ─── Seek Ripple Widget ────────────────────────────────────────────────────

class _SeekRipple extends StatelessWidget {
  final bool isForward;
  final int seconds;
  final AnimationController animation;

  const _SeekRipple({
    required this.isForward,
    required this.seconds,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.85, end: 0.0).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOut),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isForward ? Alignment.centerRight : Alignment.centerLeft,
            end: isForward ? Alignment.centerLeft : Alignment.centerRight,
            colors: [
              AppColors.primary.withValues(alpha: 0.25),
              Colors.transparent,
            ],
          ),
          borderRadius: isForward
              ? const BorderRadius.only(
                  topLeft: Radius.circular(240),
                  bottomLeft: Radius.circular(240))
              : const BorderRadius.only(
                  topRight: Radius.circular(240),
                  bottomRight: Radius.circular(240)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isForward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
              color: Colors.white,
              size: 44,
            ),
            const SizedBox(height: 6),
            Text(
              '${seconds}s',
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Vertical Volume/Brightness Indicator ──────────────────────────────────

class _VerticalIndicator extends StatelessWidget {
  final double value;
  final IconData icon;
  final String label;
  final String title;

  const _VerticalIndicator({
    required this.value,
    required this.icon,
    required this.label,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final clampedValue = value.clamp(0.0, 1.0);

    return Container(
      width: 48,
      height: 190,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 18,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          // Vertical fill bar
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: clampedValue,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          AppColors.primary,
                          Color(0xFFFF5252),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
