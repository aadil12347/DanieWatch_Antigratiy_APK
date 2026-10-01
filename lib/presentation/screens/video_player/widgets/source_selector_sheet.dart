library;

/// Source selector bottom sheet — pick streaming source during playback.
///
/// Shows all extracted sources grouped by provider with quality tags,
/// loading status indicators, and one-tap switching.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
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
                    const Icon(Icons.layers, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Sources',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${sources.length} available',
                      style: GoogleFonts.inter(
                          color: Colors.white54, fontSize: 13),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Provider status indicators
              if (statuses.values.any((s) => s == ProviderStatus.loading))
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.amber),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Still searching...',
                        style: GoogleFonts.inter(
                            color: Colors.amber, fontSize: 12),
                      ),
                    ],
                  ),
                ),

              const Divider(color: Colors.white12, height: 1),

              // Source list grouped by provider
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: grouped.entries.map((entry) {
                    final providerName = entry.key;
                    final providerSources = entry.value;
                    final status = statuses[providerName];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Provider header
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 6),
                          child: Row(
                            children: [
                              Text(
                                providerName,
                                style: GoogleFonts.inter(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (status == ProviderStatus.loading)
                                const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: Colors.amber,
                                  ),
                                ),
                              if (status == ProviderStatus.done)
                                const Icon(Icons.check_circle,
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
            ],
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
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        color: isActive ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
        child: Row(
          children: [
            // Playing indicator
            if (isActive)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.play_circle_filled,
                    color: Colors.red, size: 20),
              ),

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
