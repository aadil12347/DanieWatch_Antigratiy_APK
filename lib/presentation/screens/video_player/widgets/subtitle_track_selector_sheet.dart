import 'dart:ui';
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
        final isOff = currentSub == null ||
            currentSub.type == BetterPlayerSubtitlesSourceType.none ||
            currentSub.name == 'Off';

        final availableSubs = subtitles
            .where((s) => s.type != BetterPlayerSubtitlesSourceType.none && s.name != 'Off')
            .toList();

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
              maxHeight: 380,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xF2101016),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.85),
                        blurRadius: 40,
                        spreadRadius: 4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.subtitles_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Subtitles',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (availableSubs.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${availableSubs.length}',
                                  style: GoogleFonts.inter(
                                    color: Colors.white70,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 18),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.white.withValues(alpha: 0.06),
                                padding: const EdgeInsets.all(6),
                                minimumSize: const Size(28, 28),
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                      ),

                      Divider(
                        color: Colors.white.withValues(alpha: 0.08),
                        height: 1,
                      ),

                      // Options List
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          children: [
                            // Off option
                            GestureDetector(
                              onTap: () {
                                controller.disableSubtitles();
                                Navigator.of(context).pop();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isOff
                                      ? AppColors.primary.withValues(alpha: 0.14)
                                      : Colors.white.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isOff
                                        ? AppColors.primary.withValues(alpha: 0.6)
                                        : Colors.white.withValues(alpha: 0.06),
                                    width: isOff ? 1.2 : 0.8,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isOff
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      color: isOff ? AppColors.primary : Colors.white38,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Off (Disable Subtitles)',
                                      style: GoogleFonts.inter(
                                        color: isOff ? Colors.white : Colors.white70,
                                        fontSize: 14,
                                        fontWeight: isOff ? FontWeight.w700 : FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Subtitle Tracks
                            if (availableSubs.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
                                child: Text(
                                  'No additional subtitle tracks available',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: Colors.white38,
                                    fontSize: 13,
                                  ),
                                ),
                              ),

                            ...availableSubs.map((source) {
                              final isSelected = currentSub?.name == source.name && !isOff;
                              final label = source.name ?? 'Subtitle Track';

                              return GestureDetector(
                                onTap: () {
                                  controller.setSubtitleSource(source);
                                  Navigator.of(context).pop();
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppColors.primary.withValues(alpha: 0.14)
                                        : Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppColors.primary.withValues(alpha: 0.6)
                                          : Colors.white.withValues(alpha: 0.06),
                                      width: isSelected ? 1.2 : 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected
                                            ? Icons.check_circle_rounded
                                            : Icons.radio_button_unchecked_rounded,
                                        color: isSelected ? AppColors.primary : Colors.white38,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          label,
                                          style: GoogleFonts.inter(
                                            color: isSelected ? Colors.white : Colors.white70,
                                            fontSize: 14,
                                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'CC',
                                          style: GoogleFonts.inter(
                                            color: Colors.white60,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
