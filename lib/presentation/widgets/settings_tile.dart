import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import 'liquid_glass.dart';

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? infoText;
  final Widget? trailing;
  final VoidCallback onTap;
  final bool isDestructive;
  final Color? accentColor;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.infoText,
    this.trailing,
    required this.onTap,
    this.isDestructive = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? (isDestructive ? AppColors.error : AppColors.primary);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: LiquidGlass(
          borderRadius: 16,
          intensity: GlassIntensity.light,
          enableAnimatedBorder: false,
          enableTouchRipple: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              // Icon container with gradient background
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withValues(alpha: 0.20),
                      color.withValues(alpha: 0.06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              // Title + subtitle (infoText shown as subtitle)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDestructive ? AppColors.error : AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null || infoText != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle ?? infoText!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ?? Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted.withValues(alpha: 0.5),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
