library;

/// Source selector bottom sheet — pick streaming source during playback.
///
/// Shows all extracted sources grouped by provider with quality tags,
/// loading status indicators, and one-tap switching.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import '../player_controller.dart';
import '../../../../services/extraction/models.dart';
import '../../../../services/extraction/provider_registry.dart';

class SourceSelectorSheet extends StatelessWidget {
  final PlayerController controller;

  const SourceSelectorSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sources = controller.sources;
        final currentSource = controller.currentSource;
        final statuses = controller.providerStatuses;

        // Group sources by provider
        final grouped = <String, List<ExtractorLink>>{};
        for (final source in sources) {
          grouped.putIfAbsent(source.sourceName, () => []).add(source);
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 440,
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
                                Icons.dns_rounded,
                                color: AppColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Servers',
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${sources.length}',
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
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

                      // Provider status indicators
                      if (statuses.values.any((s) => s == ProviderStatus.loading))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Searching other servers in background...',
                                style: GoogleFonts.inter(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),

                      Divider(
                        color: Colors.white.withValues(alpha: 0.08),
                        height: 1,
                      ),

                      // Source list grouped by provider
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          children: grouped.entries.map((entry) {
                            final providerName = entry.key;
                            final providerSources = entry.value;
                            final status = statuses[providerName];

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Provider header
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                                  child: Row(
                                    children: [
                                      Text(
                                        providerName.toUpperCase(),
                                        style: GoogleFonts.inter(
                                          color: Colors.white54,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (status == ProviderStatus.loading)
                                        const SizedBox(
                                          width: 10,
                                          height: 10,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      if (status == ProviderStatus.done)
                                        const Icon(Icons.check_circle_rounded,
                                            color: Colors.green, size: 12),
                                    ],
                                  ),
                                ),

                                // Source items
                                ...providerSources.map((source) {
                                  final isActive = currentSource?.url == source.url;
                                  return _SourceItem(
                                    source: source,
                                    isActive: isActive,
                                    onTap: () {
                                      controller.switchSource(source);
                                      Navigator.of(context).pop();
                                    },
                                  );
                                }),

                                const SizedBox(height: 4),
                              ],
                            );
                          }).toList(),
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

class _SourceItem extends StatelessWidget {
  final ExtractorLink source;
  final bool isActive;
  final VoidCallback onTap;

  const _SourceItem({
    required this.source,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.06),
            width: isActive ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.play_circle_filled_rounded : Icons.radio_button_unchecked_rounded,
              color: isActive ? AppColors.primary : Colors.white38,
              size: 18,
            ),
            const SizedBox(width: 12),

            // Source info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.displayName,
                    style: GoogleFonts.inter(
                      color: isActive ? Colors.white : Colors.white70,
                      fontSize: 14,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (source.qualityTags != null &&
                      source.qualityTags!.isNotEmpty)
                    Text(
                      source.qualityTags!,
                      style: GoogleFonts.inter(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Quality badge
            if (source.quality > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _qualityColor(source.quality),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  source.qualityLabel,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

            // File size
            if (source.fileSize != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  source.fileSize!,
                  style: GoogleFonts.inter(
                      color: Colors.white38, fontSize: 11),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _qualityColor(int quality) {
    if (quality >= 2160) return Colors.purple;
    if (quality >= 1080) return Colors.blue;
    if (quality >= 720) return Colors.green;
    if (quality >= 480) return Colors.orange;
    return Colors.grey;
  }
}

/// Player settings bottom sheet — speed, audio, subtitles, resize.
class PlayerSettingsSheet extends StatelessWidget {
  final PlayerController controller;

  const PlayerSettingsSheet({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1A1A2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.settings, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Player Settings',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Playback speed
              _buildSection(
                icon: Icons.speed,
                title: 'Playback Speed',
                child: _SpeedSelector(
                  currentSpeed: controller.playbackSpeed,
                  onSpeedChanged: (speed) {
                    controller.setPlaybackSpeed(speed);
                  },
                ),
              ),

              const Divider(color: Colors.white12, indent: 20, endIndent: 20),

              // Resize mode
              _buildSection(
                icon: Icons.aspect_ratio,
                title: 'Resize Mode',
                child: _ResizeModeSelector(
                  currentMode: controller.resizeMode,
                  onModeChanged: (mode) {
                    controller.setResizeMode(mode);
                  },
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _SpeedSelector extends StatelessWidget {
  final double currentSpeed;
  final Function(double) onSpeedChanged;

  const _SpeedSelector({
    required this.currentSpeed,
    required this.onSpeedChanged,
  });

  static const speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: speeds.map((speed) {
        final isActive = (speed - currentSpeed).abs() < 0.01;
        return GestureDetector(
          onTap: () => onSpeedChanged(speed),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? Colors.red : Colors.white12,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              speed == 1.0 ? 'Normal' : '${speed}x',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ResizeModeSelector extends StatelessWidget {
  final VideoResizeMode currentMode;
  final Function(VideoResizeMode) onModeChanged;

  const _ResizeModeSelector({
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _resizeModeChip('Fit', VideoResizeMode.fit, Icons.fit_screen),
        const SizedBox(width: 8),
        _resizeModeChip('Fill', VideoResizeMode.fill, Icons.crop_free),
        const SizedBox(width: 8),
        _resizeModeChip('Zoom', VideoResizeMode.zoom, Icons.zoom_out_map),
      ],
    );
  }

  Widget _resizeModeChip(
      String label, VideoResizeMode mode, IconData icon) {
    final isActive = currentMode == mode;
    return GestureDetector(
      onTap: () => onModeChanged(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.red : Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
