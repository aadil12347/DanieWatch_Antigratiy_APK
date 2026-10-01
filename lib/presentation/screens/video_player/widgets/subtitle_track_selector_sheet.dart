import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../player_controller.dart';

class SubtitleTrackSelectorSheet extends StatelessWidget {
  final PlayerController controller;

  const SubtitleTrackSelectorSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final subtitles = controller.subtitleSources;
        final currentSub = controller.currentSubtitleSource;
        final isOff = currentSub == null || currentSub.type == BetterPlayerSubtitlesSourceType.none;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.65,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F14),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.8),
                blurRadius: 30,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.subtitles_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Subtitles',
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              const Divider(color: Colors.white10, height: 1),

              // Options
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    // Off option
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: isOff
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isOff
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: ListTile(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          controller.disableSubtitles();
                          Navigator.of(context).pop();
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        leading: Icon(
                          isOff ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          color: isOff ? AppColors.primary : Colors.white38,
                          size: 20,
                        ),
                        title: Text(
                          'Off (Disable Subtitles)',
                          style: GoogleFonts.inter(
                            color: isOff ? Colors.white : Colors.white70,
                            fontSize: 15,
                            fontWeight: isOff ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),

                    // Subtitle Tracks
                    if (subtitles.where((s) => s.type != BetterPlayerSubtitlesSourceType.none).isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                        child: Text(
                          'No subtitle tracks available for this stream',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),

                    ...subtitles
                        .where((s) => s.type != BetterPlayerSubtitlesSourceType.none)
                        .map((source) {
                      final isSelected = currentSub?.name == source.name && !isOff;
                      final label = source.name ?? 'Subtitle Track';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: ListTile(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            controller.setSubtitleSource(source);
                            Navigator.of(context).pop();
                          },
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: isSelected ? AppColors.primary : Colors.white38,
                            size: 20,
                          ),
                          title: Text(
                            label,
                            style: GoogleFonts.inter(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 15,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
