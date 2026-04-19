import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? infoText;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool isDestructive;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.infoText,
    this.trailing,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDestructive 
                  ? AppColors.error.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDestructive 
                      ? AppColors.error.withValues(alpha: 0.1)
                      : AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon, 
                  color: isDestructive ? AppColors.error : AppColors.primary.withValues(alpha: 0.8), 
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDestructive ? AppColors.error : AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (infoText != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: GestureDetector(
                    onTap: () {
                      final overlay = Overlay.of(context);
                      final renderBox = context.findRenderObject() as RenderBox;
                      final offset = renderBox.localToGlobal(Offset.zero);

                      late OverlayEntry entry;
                      entry = OverlayEntry(
                        builder: (ctx) => _InfoTooltipOverlay(
                          text: infoText!,
                          targetOffset: offset,
                          targetSize: renderBox.size,
                          onDismiss: () => entry.remove(),
                        ),
                      );
                      overlay.insert(entry);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.primary.withValues(alpha: 0.6),
                        size: 16,
                      ),
                    ),
                  ),
                ),
              trailing ?? const Icon(
                Icons.chevron_right_rounded, 
                color: AppColors.textMuted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoTooltipOverlay extends StatefulWidget {
  final String text;
  final Offset targetOffset;
  final Size targetSize;
  final VoidCallback onDismiss;

  const _InfoTooltipOverlay({
    required this.text,
    required this.targetOffset,
    required this.targetSize,
    required this.onDismiss,
  });

  @override
  State<_InfoTooltipOverlay> createState() => _InfoTooltipOverlayState();
}

class _InfoTooltipOverlayState extends State<_InfoTooltipOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnim = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();

    // Auto-dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) _dismiss();
    });
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    const tooltipWidth = 260.0;
    final left = (widget.targetOffset.dx + widget.targetSize.width / 2 - tooltipWidth / 2)
        .clamp(16.0, screenWidth - tooltipWidth - 16.0);
    final top = widget.targetOffset.dy - 12;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismiss,
      child: Stack(
        children: [
          Positioned(
            left: left,
            bottom: MediaQuery.of(context).size.height - top,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Container(
                width: tooltipWidth,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.text,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
