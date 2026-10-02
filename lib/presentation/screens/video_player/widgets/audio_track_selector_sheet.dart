import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../player_controller.dart';

class AudioTrackSelectorSheet extends StatelessWidget {
  final PlayerController controller;

  const AudioTrackSelectorSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final audioTracks = controller.audioTracks;
        final currentTrack = controller.currentAudioTrack;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
              maxHeight: 360,
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
                                Icons.audiotrack_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Audio Tracks',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (audioTracks.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${audioTracks.length}',
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

                      // Track List
                      Flexible(
                        child: audioTracks.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Default Audio Track',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                itemCount: audioTracks.length,
                                itemBuilder: (context, index) {
                                  final track = audioTracks[index];
                                  final isSelected = currentTrack?.id == track.id ||
                                      (currentTrack == null && index == 0);
                                  final displayName = track.label ?? track.language ?? 'Audio Track ${index + 1}';

                                  return GestureDetector(
                                    onTap: () {
                                      controller.setAudioTrack(track);
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
                                              displayName,
                                              style: GoogleFonts.inter(
                                                color: isSelected ? Colors.white : Colors.white70,
                                                fontSize: 14,
                                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (track.language != null) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.08),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                track.language!.toUpperCase(),
                                                style: GoogleFonts.inter(
                                                  color: Colors.white60,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
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
