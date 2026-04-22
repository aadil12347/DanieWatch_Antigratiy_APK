import 'dart:math';
import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../providers/search_provider.dart';
import '../providers/filter_modal_provider.dart';

/// Magnifying glass icon with animated handle line.
class _MagnifyingGlassPainter extends CustomPainter {
  final double handleProgress; // 1 = handle visible, 0 = hidden
  final Color color;
  final double strokeWidth;

  _MagnifyingGlassPainter({
    required this.handleProgress,
    required this.color,
    this.strokeWidth = 2.2,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final cx = size.width * 0.40;
    final cy = size.height * 0.40;
    final radius = size.width * 0.28;

    // Draw circle
    canvas.drawCircle(Offset(cx, cy), radius, paint);

    // Draw handle
    if (handleProgress > 0.01) {
      const angle = pi / 4; // 45 degrees
      final hx = cx + radius * cos(angle);
      final hy = cy + radius * sin(angle);
      final endX = hx + size.width * 0.22 * handleProgress;
      final endY = hy + size.height * 0.22 * handleProgress;
      canvas.drawLine(Offset(hx, hy), Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MagnifyingGlassPainter old) =>
      handleProgress != old.handleProgress || color != old.color;
}

/// Animated close (X) button painter.
class _CloseXPainter extends CustomPainter {
  final double progress; // 0 = hidden, 1 = fully visible
  final Color color;

  _CloseXPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress < 0.01) return;
    final paint = Paint()
      ..color = color.withValues(alpha: progress.clamp(0.0, 1.0))
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final c = Offset(size.width / 2, size.height / 2);
    final half = size.width * 0.3;

    // Line 1 (appears first half)
    final t1 = Curves.easeOutBack.transform((progress * 2).clamp(0.0, 1.0));
    if (t1 > 0) {
      final dx1 = half * t1;
      canvas.drawLine(Offset(c.dx - dx1, c.dy - dx1), Offset(c.dx + dx1, c.dy + dx1), paint);
    }

    // Line 2 (appears second half)
    final t2 = Curves.easeOutBack.transform(((progress - 0.3) / 0.7).clamp(0.0, 1.0));
    if (t2 > 0) {
      final dx2 = half * t2;
      canvas.drawLine(Offset(c.dx + dx2, c.dy - dx2), Offset(c.dx - dx2, c.dy + dx2), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CloseXPainter old) =>
      progress != old.progress || color != old.color;
}

/// Pinned header row with morphing search animation.
/// Search icon morphs from magnifying glass circle → expanded search bar.
class MorphingSearchHeaderRow extends ConsumerStatefulWidget {
  final String title;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final Function(String) onSearchChanged;
  final String contextId;
  final bool showFilterButton;

  const MorphingSearchHeaderRow({
    super.key,
    required this.title,
    required this.searchController,
    required this.searchFocus,
    required this.onSearchChanged,
    this.contextId = 'explore',
    this.showFilterButton = true,
  });

  @override
  ConsumerState<MorphingSearchHeaderRow> createState() =>
      _MorphingSearchHeaderRowState();
}

class _MorphingSearchHeaderRowState
    extends ConsumerState<MorphingSearchHeaderRow>
    with TickerProviderStateMixin {
  // Phase 1: handle morph (200ms)
  late AnimationController _morphCtrl;
  // Phase 2: expand circle → bar (400ms)
  late AnimationController _expandCtrl;
  // Close X lines
  late AnimationController _closeCtrl;
  // Glow pulse
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  bool _isOpen = false;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _morphCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _expandCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _closeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _glowAnim = Tween<double>(begin: 0.15, end: 0.4)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    // If already has text, open immediately
    if (widget.searchController.text.isNotEmpty) {
      _isOpen = true;
      _morphCtrl.value = 1.0;
      _expandCtrl.value = 1.0;
      _closeCtrl.value = 1.0;
    }
    widget.searchFocus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.searchFocus.removeListener(_onFocusChange);
    _morphCtrl.dispose();
    _expandCtrl.dispose();
    _closeCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    ref.read(searchFocusProvider.notifier).state = widget.searchFocus.hasFocus;
    if (widget.searchFocus.hasFocus) {
      _glowCtrl.repeat(reverse: true);
    } else {
      _glowCtrl.stop();
      _glowCtrl.value = 0;
    }
    // Auto-close when unfocused and empty
    if (!widget.searchFocus.hasFocus && _isOpen) {
      if (widget.searchController.text.isEmpty) {
        _closeSearch();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _openSearch() async {
    if (_animating) return;
    _animating = true;
    setState(() => _isOpen = true);

    // Phase 1: Handle disappears (backin curve)
    await _morphCtrl.animateTo(1.0, curve: Curves.easeInBack);
    // Phase 2: Expand to full bar
    await _expandCtrl.animateTo(1.0, curve: Curves.easeInOutCubic);
    // Show close X
    _closeCtrl.forward();

    _animating = false;
    if (mounted) setState(() {});
    // Don't auto-focus keyboard — user must tap the field
  }

  Future<void> _closeSearch() async {
    if (_animating) return;
    _animating = true;

    widget.searchFocus.unfocus();
    _glowCtrl.stop();
    _glowCtrl.value = 0;

    // Hide close X
    _closeCtrl.reverse();
    // Brief delay
    await Future.delayed(const Duration(milliseconds: 300));
    // Phase 1: Shrink bar → circle
    await _expandCtrl.animateTo(0.0, curve: Curves.easeInOutCubic);
    // Phase 2: Handle reappears
    await _morphCtrl.animateTo(0.0, curve: Curves.easeInOut);

    if (mounted) setState(() => _isOpen = false);
    _animating = false;
  }

  void _onClearTapped() {
    widget.searchController.clear();
    widget.onSearchChanged('');
    widget.searchFocus.requestFocus();
  }

  void _onCloseTapped() {
    widget.searchController.clear();
    widget.onSearchChanged('');
    _closeSearch();
  }

  @override
  Widget build(BuildContext context) {
    final r = Responsive(context);
    final filterSize = r.d(38).clamp(34.0, 44.0);
    final circleSize = filterSize; // Match filter button exactly
    final barH = filterSize; // Same height as filter button
    final hPad = r.w(16);

    return Container(
      color: AppColors.background,
      padding: EdgeInsets.fromLTRB(hPad, r.h(5), hPad, r.h(12)),
      child: LayoutBuilder(
        builder: (context, box) {
          final filterW =
              widget.showFilterButton ? filterSize + r.w(10) : 0.0;
          final mainW = box.maxWidth - filterW;

          return Row(
            children: [
              SizedBox(
                width: mainW,
                height: barH,
                child: AnimatedBuilder(
                  animation:
                      Listenable.merge([_morphCtrl, _expandCtrl, _glowAnim]),
                  builder: (context, _) {
                    final morphT = _morphCtrl.value;
                    final expandT = _expandCtrl.value;
                    final searchW =
                        circleSize + (mainW - circleSize) * expandT;
                    final titleOp = (1.0 - expandT * 3.0).clamp(0.0, 1.0);

                    return Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        // Title
                        if (titleOp > 0)
                          Opacity(
                            opacity: titleOp,
                            child: Transform.translate(
                              offset: Offset(-expandT * 30, 0),
                              child: Text(
                                widget.title,
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textPrimary,
                                  fontSize: r.f(26).clamp(20.0, 32.0),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.8,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        // Morphing search
                        Positioned(
                          right: 0,
                          child: _buildMorphContainer(
                              r, searchW, barH, circleSize, morphT, expandT),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (widget.showFilterButton) ...[
                SizedBox(width: r.w(10)),
                _buildFilterBtn(r, filterSize),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildMorphContainer(Responsive r, double w, double h,
      double circleSize, double morphT, double expandT) {
    final focused = widget.searchFocus.hasFocus;
    final expanded = expandT > 0.95;
    final hasText = widget.searchController.text.isNotEmpty;
    final radius = r.w(12);

    // Glassmorphism-style decoration
    final borderCol = focused && expanded
        ? AppColors.primary.withValues(alpha: 0.55)
        : Colors.white
            .withValues(alpha: lerpDouble(0.08, 0.06, expandT) ?? 0.07);
    final bw = focused && expanded ? 1.2 : 0.8;

    return GestureDetector(
      onTap: !_isOpen ? _openSearch : null,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                  const Color(0xFF222226), const Color(0xFF1E1E22), expandT)!,
              Color.lerp(
                  const Color(0xFF1C1C20), const Color(0xFF1A1A1E), expandT)!,
              focused && expanded
                  ? AppColors.primary.withValues(alpha: 0.05)
                  : Color.lerp(const Color(0xFF1C1C20),
                      const Color(0xFF18181C), expandT)!,
            ],
          ),
          borderRadius: BorderRadius.circular(radius),
          // Rounded square matching filter button
          border: Border.all(color: borderCol, width: bw),
          boxShadow: focused && expanded
              ? [
                  BoxShadow(
                    color:
                        AppColors.primary.withValues(alpha: _glowAnim.value),
                    blurRadius: 20,
                    spreadRadius: -2,
                  ),
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    blurRadius: 40,
                    spreadRadius: 2,
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Magnifying glass icon (fades out when expanded)
            if (expandT < 0.9)
              Opacity(
                opacity: (1.0 - expandT * 1.5).clamp(0.0, 1.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CustomPaint(
                    painter: _MagnifyingGlassPainter(
                      handleProgress: 1.0 - morphT,
                      color: Colors.white.withValues(alpha: 0.6),
                      strokeWidth: 2.2,
                    ),
                  ),
                ),
              ),
            // Search field (fades in when expanding)
            if (_isOpen && expandT > 0.5)
              Opacity(
                opacity: ((expandT - 0.5) * 2.0).clamp(0.0, 1.0),
                child: Row(
                  children: [
                    SizedBox(width: r.w(16)),
                    Icon(
                      Icons.search_rounded,
                      color: focused
                          ? AppColors.primary.withValues(alpha: 0.9)
                          : Colors.white.withValues(alpha: 0.3),
                      size: r.d(20).clamp(18.0, 24.0),
                    ),
                    SizedBox(width: r.w(8)),
                    Expanded(
                      child: TextField(
                        controller: widget.searchController,
                        focusNode: widget.searchFocus,
                        maxLines: 1,
                        textAlignVertical: TextAlignVertical.center,
                        textInputAction: TextInputAction.done,
                        cursorColor: AppColors.primary,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: r.f(14).clamp(13.0, 17.0),
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0.1,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search movies, shows...',
                          hintStyle: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.28),
                            fontSize: r.f(14).clamp(12.0, 16.0),
                            fontWeight: FontWeight.w400,
                          ),
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                        ),
                        onChanged: widget.onSearchChanged,
                        onSubmitted: (_) => widget.searchFocus.unfocus(),
                      ),
                    ),
                    // Clear text button removed per design
                    // Animated close X — smaller but with easy touch target
                    AnimatedBuilder(
                      animation: _closeCtrl,
                      builder: (ctx, _) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _onCloseTapped,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CustomPaint(
                              painter: _CloseXPainter(
                                progress: _closeCtrl.value,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: r.w(4)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBtn(Responsive r, double size) {
    return GestureDetector(
      onTap: () {
        widget.searchFocus.unfocus();
        final cur = ref.read(filterModalProvider);
        if (cur.isOpen) {
          ref.read(filterModalProvider.notifier).state =
              const FilterModalState(view: FilterView.none);
        } else {
          ref.read(filterModalProvider.notifier).state = FilterModalState(
            view: FilterView.mainPanel,
            contextId: widget.contextId,
          );
        }
      },
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD42A30), AppColors.primary, Color(0xFF8E1519)],
          ),
          borderRadius: BorderRadius.circular(r.w(12)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(Icons.tune_rounded,
            color: Colors.white, size: r.d(20).clamp(18.0, 24.0)),
      ),
    );
  }
}
