import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'vidstack_theme.dart';

/// Vidstack Interactive Timeline Scrubber.
/// Features:
/// - Smooth track expansion animation (3.5px → 6.0px on touch)
/// - Elastic thumb scale animation (8px → 15px)
/// - Floating timestamp bubble tooltip with caret pointer tracking drag position
/// - Distinct buffered vs played progress layers
/// - Generous touch-target padding
class VidstackSlider extends StatefulWidget {
  final double progress; // 0.0 to 1.0
  final double bufferProgress; // 0.0 to 1.0
  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onSeekStart;
  final VoidCallback? onSeekEnd;

  const VidstackSlider({
    super.key,
    required this.progress,
    required this.bufferProgress,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.onSeekStart,
    this.onSeekEnd,
  });

  @override
  State<VidstackSlider> createState() => _VidstackSliderState();
}

class _VidstackSliderState extends State<VidstackSlider>
    with SingleTickerProviderStateMixin {
  double? _dragProgress;
  late final AnimationController _expandAnim;
  late final Animation<double> _trackHeight;
  late final Animation<double> _thumbScale;

  @override
  void initState() {
    super.initState();
    _expandAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 220),
    );

    _trackHeight = Tween<double>(begin: 3.5, end: 6.0).animate(
      CurvedAnimation(parent: _expandAnim, curve: Curves.easeOutCubic),
    );

    _thumbScale = Tween<double>(begin: 0.7, end: 1.25).animate(
      CurvedAnimation(parent: _expandAnim, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _expandAnim.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details, double totalWidth) {
    if (totalWidth <= 0) return;
    _expandAnim.forward();
    HapticFeedback.selectionClick();
    widget.onSeekStart?.call();
    _updateProgress(details.localPosition.dx, totalWidth);
  }

  void _onDragUpdate(DragUpdateDetails details, double totalWidth) {
    if (totalWidth <= 0) return;
    _updateProgress(details.localPosition.dx, totalWidth);
  }

  void _onDragEnd(DragEndDetails _, double totalWidth) {
    _expandAnim.reverse();
    if (_dragProgress != null && widget.duration.inMilliseconds > 0) {
      final seekMillis = (_dragProgress! * widget.duration.inMilliseconds).toInt();
      widget.onSeek(Duration(milliseconds: seekMillis));
      HapticFeedback.lightImpact();
    }
    setState(() => _dragProgress = null);
    widget.onSeekEnd?.call();
  }

  void _onTapDown(TapDownDetails details, double totalWidth) {
    if (totalWidth <= 0) return;
    final p = (details.localPosition.dx / totalWidth).clamp(0.0, 1.0);
    if (widget.duration.inMilliseconds > 0) {
      final seekMillis = (p * widget.duration.inMilliseconds).toInt();
      widget.onSeek(Duration(milliseconds: seekMillis));
      HapticFeedback.lightImpact();
    }
  }

  void _updateProgress(double localX, double totalWidth) {
    setState(() {
      _dragProgress = (localX / totalWidth).clamp(0.0, 1.0);
    });
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = (_dragProgress ?? widget.progress).clamp(0.0, 1.0);
    final effectiveBuffer = widget.bufferProgress.clamp(0.0, 1.0);
    final isDragging = _dragProgress != null;

    final seekPosition = isDragging
        ? Duration(milliseconds: (effectiveProgress * widget.duration.inMilliseconds).toInt())
        : widget.position;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) => _onDragStart(d, totalWidth),
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, totalWidth),
          onHorizontalDragEnd: (d) => _onDragEnd(d, totalWidth),
          onTapDown: (d) => _onTapDown(d, totalWidth),
          child: AnimatedBuilder(
            animation: _expandAnim,
            builder: (context, _) {
              final th = _trackHeight.value;
              final ts = _thumbScale.value;

              return SizedBox(
                height: 36, // Generous hit area
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.centerLeft,
                  children: [
                    // 1. Background Track
                    Container(
                      width: totalWidth,
                      height: th,
                      decoration: BoxDecoration(
                        color: VidstackTheme.trackBackground,
                        borderRadius: BorderRadius.circular(th / 2),
                      ),
                    ),

                    // 2. Buffered Range Track
                    Container(
                      width: totalWidth * effectiveBuffer,
                      height: th,
                      decoration: BoxDecoration(
                        color: VidstackTheme.trackBuffer,
                        borderRadius: BorderRadius.circular(th / 2),
                      ),
                    ),

                    // 3. Played Progress Track
                    Container(
                      width: totalWidth * effectiveProgress,
                      height: th,
                      decoration: BoxDecoration(
                        color: VidstackTheme.trackProgress,
                        borderRadius: BorderRadius.circular(th / 2),
                        boxShadow: [
                          BoxShadow(
                            color: VidstackTheme.brand.withValues(alpha: 0.45),
                            blurRadius: isDragging ? 8 : 4,
                            spreadRadius: isDragging ? 1 : 0,
                          ),
                        ],
                      ),
                    ),

                    // 4. Elastic Scrubber Thumb
                    Positioned(
                      left: (totalWidth * effectiveProgress - (7 * ts))
                          .clamp(0.0, totalWidth - (14 * ts)),
                      child: Transform.scale(
                        scale: ts,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: VidstackTheme.brand,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.6),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                              BoxShadow(
                                color: VidstackTheme.brand.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 5. Vidstack Floating Timestamp Bubble Tooltip
                    if (isDragging)
                      Positioned(
                        left: (totalWidth * effectiveProgress - 32)
                            .clamp(8.0, totalWidth - 72.0),
                        top: -34,
                        child: _VidstackScrubTooltip(
                          timeText: _formatDuration(seekPosition),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Floating scrub tooltip with caret pointing down.
class _VidstackScrubTooltip extends StatelessWidget {
  final String timeText;

  const _VidstackScrubTooltip({required this.timeText});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Bubble
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: VidstackTheme.surfaceElevate,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: VidstackTheme.borderMedium, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            timeText,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
        ),

        // Caret pointing down
        CustomPaint(
          size: const Size(8, 4),
          painter: _CaretPainter(),
        ),
      ],
    );
  }
}

class _CaretPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = VidstackTheme.surfaceElevate
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CaretPainter oldDelegate) => false;
}
