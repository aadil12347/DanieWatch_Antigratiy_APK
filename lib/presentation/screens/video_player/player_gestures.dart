/// Player gesture handler — Cloudstream-style gestures.
///
/// Gestures implemented:
/// - Double-tap left/right → seek backward/forward 10s with ripple
/// - Long-press → 2x speed with pill indicator (release restores)
/// - Horizontal swipe → seek forward/backward with time preview
/// - Vertical swipe left → brightness control
/// - Vertical swipe right → volume control
/// - Single tap → toggle controls visibility

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:screen_brightness/screen_brightness.dart';
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
  bool _isDragging = false;
  bool _isHorizontalDrag = false;
  bool _isVerticalDrag = false;
  bool _isLeftSide = false;
  double _dragStartX = 0;
  double _dragStartY = 0;

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
  bool _showSeekPreview = false;

  // ─── Volume/Brightness ─────────────────────────────────────────────────
  double _currentVolume = 0.5;
  double _currentBrightness = 0.5;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;

  // ─── Animations ────────────────────────────────────────────────────────
  late AnimationController _leftSeekAnim;
  late AnimationController _rightSeekAnim;
  late AnimationController _speedPillAnim;

  @override
  void initState() {
    super.initState();
    _leftSeekAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _rightSeekAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _speedPillAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _initVolumeAndBrightness();
  }

  Future<void> _initVolumeAndBrightness() async {
    try {
      _currentVolume = await VolumeController.instance.getVolume();
      _currentBrightness = await ScreenBrightness().current;
    } catch (e) {
      _currentVolume = 0.5;
      _currentBrightness = 0.5;
    }
  }

  @override
  void dispose() {
    _seekResetTimer?.cancel();
    _leftSeekAnim.dispose();
    _rightSeekAnim.dispose();
    _speedPillAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Video + gesture detector
        GestureDetector(
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

        // Left seek ripple indicator
        if (_showLeftSeek)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.4,
            child: _SeekRipple(
              isForward: false,
              seconds: _seekSeconds,
              animation: _leftSeekAnim,
            ),
          ),

        // Right seek ripple indicator
        if (_showRightSeek)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.4,
            child: _SeekRipple(
              isForward: true,
              seconds: _seekSeconds,
              animation: _rightSeekAnim,
            ),
          ),

        // 2x speed pill indicator
        if (_isLongPressing)
          Positioned(
            top: 24,
            left: 0,
            right: 0,
            child: Center(
              child: FadeTransition(
                opacity: _speedPillAnim,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fast_forward, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text('2x Speed',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Horizontal swipe seek preview
        if (_showSeekPreview)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatDuration(_seekPreviewPosition),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),

        // Volume indicator (right side)
        if (_showVolumeIndicator)
          Positioned(
            right: 24,
            top: 0,
            bottom: 0,
            child: Center(
              child: _VerticalIndicator(
                value: _currentVolume,
                icon: _currentVolume > 0.5
                    ? Icons.volume_up
                    : (_currentVolume > 0 ? Icons.volume_down : Icons.volume_off),
                label: '${(_currentVolume * 100).toInt()}%',
              ),
            ),
          ),

        // Brightness indicator (left side)
        if (_showBrightnessIndicator)
          Positioned(
            left: 24,
            top: 0,
            bottom: 0,
            child: Center(
              child: _VerticalIndicator(
                value: _currentBrightness,
                icon: _currentBrightness > 0.5
                    ? Icons.brightness_high
                    : Icons.brightness_low,
                label: '${(_currentBrightness * 100).toInt()}%',
              ),
            ),
          ),
      ],
    );
  }

  // ─── Single tap ─────────────────────────────────────────────────────────

  void _onTap() {
    widget.controller.toggleControls();
  }

  // ─── Double-tap seek ────────────────────────────────────────────────────

  void _onDoubleTapDown(TapDownDetails details, BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final tapX = details.globalPosition.dx;
    final isLeft = tapX < screenWidth / 2;

    _seekSeconds = 10;

    if (isLeft) {
      // Seek backward
      widget.controller.seekRelative(const Duration(seconds: -10));
      setState(() {
        _showLeftSeek = true;
        _showRightSeek = false;
      });
      _leftSeekAnim.forward(from: 0);
    } else {
      // Seek forward
      widget.controller.seekRelative(const Duration(seconds: 10));
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
    _savedSpeed = widget.controller.playbackSpeed;
    widget.controller.setPlaybackSpeed(2.0);
    setState(() => _isLongPressing = true);
    _speedPillAnim.forward();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    widget.controller.setPlaybackSpeed(_savedSpeed);
    setState(() => _isLongPressing = false);
    _speedPillAnim.reverse();
  }

  // ─── Vertical drag (volume/brightness) ──────────────────────────────────

  void _onVerticalDragStart(DragStartDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    _isLeftSide = details.globalPosition.dx < screenWidth / 2;
    _dragStartY = details.globalPosition.dy;
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
    if (!_isVerticalDrag) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final delta = -details.delta.dy / (screenHeight * 0.6);

    if (_isLeftSide) {
      // Brightness
      _currentBrightness = (_currentBrightness + delta).clamp(0.0, 1.0);
      ScreenBrightness().setScreenBrightness(_currentBrightness);
    } else {
      // Volume
      _currentVolume = (_currentVolume + delta).clamp(0.0, 1.0);
      VolumeController.instance.setVolume(_currentVolume);
    }

    setState(() {});
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isVerticalDrag = false;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = false;
          _showBrightnessIndicator = false;
        });
      }
    });
  }

  // ─── Horizontal drag (seek) ─────────────────────────────────────────────

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragStartX = details.globalPosition.dx;
    _isHorizontalDrag = true;
    _seekPreviewPosition = widget.controller.position;
    setState(() => _showSeekPreview = true);
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isHorizontalDrag) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final delta = details.delta.dx / screenWidth;
    final seekDelta = Duration(
        milliseconds: (delta * widget.controller.duration.inMilliseconds * 0.15).toInt());

    _seekPreviewPosition = (_seekPreviewPosition + seekDelta);
    if (_seekPreviewPosition < Duration.zero) _seekPreviewPosition = Duration.zero;
    if (_seekPreviewPosition > widget.controller.duration) {
      _seekPreviewPosition = widget.controller.duration;
    }

    setState(() {});
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_isHorizontalDrag) {
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
      opacity: Tween<double>(begin: 0.8, end: 0.0).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOut),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: isForward ? Alignment.centerRight : Alignment.centerLeft,
            end: isForward ? Alignment.centerLeft : Alignment.centerRight,
            colors: [Colors.white24, Colors.transparent],
          ),
          borderRadius: isForward
              ? const BorderRadius.only(
                  topLeft: Radius.circular(200),
                  bottomLeft: Radius.circular(200))
              : const BorderRadius.only(
                  topRight: Radius.circular(200),
                  bottomRight: Radius.circular(200)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isForward ? Icons.fast_forward : Icons.fast_rewind,
              color: Colors.white,
              size: 40,
            ),
            const SizedBox(height: 4),
            Text(
              '${seconds}s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
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

  const _VerticalIndicator({
    required this.value,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 180,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 8),
          SizedBox(
            height: 100,
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: value,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
