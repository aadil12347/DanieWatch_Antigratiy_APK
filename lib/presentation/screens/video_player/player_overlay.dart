/// Player controls overlay — Cloudstream-style player UI.
///
/// Includes:
/// - Top bar: back button, title, settings, lock, PiP
/// - Bottom bar: play/pause, seek bar with buffer, time, source, fullscreen
/// - Center: large play/pause, loading spinner, error with retry
/// - Lock button (when locked)

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'player_controller.dart';
import '../../../services/extraction/models.dart';
import '../../../services/extraction/provider_registry.dart';

class PlayerOverlay extends StatelessWidget {
  final PlayerController controller;
  final VoidCallback? onBack;
  final VoidCallback? onSourceTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onEpisodeTap;
  final VoidCallback? onPipTap;
  final bool showEpisodeButton;

  const PlayerOverlay({
    super.key,
    required this.controller,
    this.onBack,
    this.onSourceTap,
    this.onSettingsTap,
    this.onEpisodeTap,
    this.onPipTap,
    this.showEpisodeButton = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Locked mode: only show unlock button
        if (controller.isLocked) {
          return _buildLockedOverlay();
        }

        // Loading/Error states always visible
        if (controller.state == PlaybackState.extracting ||
            controller.state == PlaybackState.error) {
          return _buildFullOverlay(context, alwaysVisible: true);
        }

        // Normal mode: animated controls
        return AnimatedOpacity(
          opacity: controller.controlsVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            ignoring: !controller.controlsVisible,
            child: _buildFullOverlay(context),
          ),
        );
      },
    );
  }

  Widget _buildLockedOverlay() {
    return Positioned(
      right: 16,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onTap: controller.toggleLock,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Icon(Icons.lock_open, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }

  Widget _buildFullOverlay(BuildContext context, {bool alwaysVisible = false}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black54,
            Colors.transparent,
            Colors.transparent,
            Colors.black54,
          ],
          stops: [0.0, 0.25, 0.75, 1.0],
        ),
      ),
      child: Stack(
        children: [
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopBar(context),
          ),

          // Center controls
          Center(child: _buildCenterControls()),

          // Bottom bar
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomBar(context),
          ),
        ],
      ),
    );
  }

  // ─── Top Bar ────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Back button
            IconButton(
              onPressed: onBack ?? () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              padding: const EdgeInsets.all(8),
            ),

            const SizedBox(width: 8),

            // Title
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    controller.title,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (controller.currentSource != null)
                    Text(
                      controller.currentSource!.displayName,
                      style: GoogleFonts.inter(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Episode button
            if (showEpisodeButton)
              IconButton(
                onPressed: onEpisodeTap,
                icon: const Icon(Icons.playlist_play,
                    color: Colors.white, size: 26),
                tooltip: 'Episodes',
              ),

            // PiP button
            if (onPipTap != null)
              IconButton(
                onPressed: onPipTap,
                icon: const Icon(Icons.picture_in_picture_alt,
                    color: Colors.white, size: 22),
                tooltip: 'Picture in Picture',
              ),

            // Lock button
            IconButton(
              onPressed: controller.toggleLock,
              icon: const Icon(Icons.lock_outline,
                  color: Colors.white, size: 22),
              tooltip: 'Lock',
            ),

            // Settings button
            IconButton(
              onPressed: onSettingsTap,
              icon: const Icon(Icons.settings, color: Colors.white, size: 22),
              tooltip: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  // ─── Center Controls ────────────────────────────────────────────────────

  Widget _buildCenterControls() {
    switch (controller.state) {
      case PlaybackState.extracting:
        return _buildExtractionView();
      case PlaybackState.buffering:
        return const SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Colors.white,
          ),
        );
      case PlaybackState.error:
        return _buildErrorView();
      case PlaybackState.playing:
      case PlaybackState.paused:
        return GestureDetector(
          onTap: controller.togglePlayPause,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Icon(
              controller.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 42,
            ),
          ),
        );
      case PlaybackState.completed:
        return GestureDetector(
          onTap: () => controller.seekTo(Duration.zero),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(40),
            ),
            child: const Icon(Icons.replay, color: Colors.white, size: 42),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildExtractionView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Finding sources...',
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        // Provider status list
        ...controller.providerStatuses.entries.map((e) {
          IconData icon;
          Color color;
          switch (e.value) {
            case ProviderStatus.loading:
              icon = Icons.hourglass_empty;
              color = Colors.amber;
              break;
            case ProviderStatus.done:
              icon = Icons.check_circle;
              color = Colors.green;
              break;
            case ProviderStatus.empty:
              icon = Icons.remove_circle_outline;
              color = Colors.grey;
              break;
            case ProviderStatus.error:
              icon = Icons.error_outline;
              color = Colors.red;
              break;
            default:
              icon = Icons.circle_outlined;
              color = Colors.grey;
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 14),
                const SizedBox(width: 6),
                Text(
                  e.key,
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 48),
        const SizedBox(height: 12),
        Text(
          controller.errorMessage ?? 'Playback error',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: controller.retry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Retry'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white24,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  // ─── Bottom Bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context) {
    final position = controller.position;
    final duration = controller.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek bar
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              activeTrackColor: Colors.red,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.red,
              overlayColor: Colors.red.withOpacity(0.2),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (value) {
                final seekPos = Duration(
                    milliseconds: (value * duration.inMilliseconds).toInt());
                controller.seekTo(seekPos);
              },
            ),
          ),

          // Time + controls row
          Row(
            children: [
              // Time display
              Text(
                '${_formatDuration(position)} / ${_formatDuration(duration)}',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(),

              // Source selector button
              if (controller.sources.length > 1)
                GestureDetector(
                  onTap: onSourceTap,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.layers, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'Sources (${controller.sources.length})',
                          style: GoogleFonts.inter(
                              color: Colors.white, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              // Speed indicator
              if (controller.playbackSpeed != 1.0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${controller.playbackSpeed}x',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 11),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
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
