import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:daniewatch_app/core/theme/app_theme.dart';
import 'player_controller.dart';

class PlayerOverlay extends StatelessWidget {
  final PlayerController controller;
  final VoidCallback? onBack;
  final VoidCallback? onSourceTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onPipTap;
  final VoidCallback? onAudioTap;
  final VoidCallback? onSubtitleTap;
  final VoidCallback? onSpeedTap;

  const PlayerOverlay({
    super.key,
    required this.controller,
    this.onBack,
    this.onSourceTap,
    this.onSettingsTap,
    this.onPipTap,
    this.onAudioTap,
    this.onSubtitleTap,
    this.onSpeedTap,
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
      right: 24,
      top: 0,
      bottom: 0,
      child: Center(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            controller.toggleLock();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text(
                  'Tap to Unlock',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullOverlay(BuildContext context, {bool alwaysVisible = false}) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.90),
          ],
          stops: const [0.0, 0.25, 0.70, 1.0],
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

          // Center controls (strictly 3 buttons: 10s back, play/pause, 10s forward)
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Back button
            _AnimatedTapScale(
              onTap: onBack ?? () => Navigator.of(context).pop(),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: const Center(
                  child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Title + subtitle badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      // Episode badge if TV show
                      if (controller.isTvShow && controller.season != null && controller.episode != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'S${controller.season.toString().padLeft(2, '0')}E${controller.episode.toString().padLeft(2, '0')}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          controller.title,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (controller.currentSource != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        controller.currentSource!.displayName,
                        style: GoogleFonts.inter(
                          color: Colors.white.withValues(alpha: 0.65),
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),

            // Subtitle track button
            _buildTopActionButton(
              icon: Icons.subtitles_rounded,
              tooltip: 'Subtitles',
              onTap: onSubtitleTap,
              isActive: controller.currentSubtitleSource != null,
            ),

            const SizedBox(width: 6),

            // Audio track button
            _buildTopActionButton(
              icon: Icons.audiotrack_rounded,
              tooltip: 'Audio Tracks',
              onTap: onAudioTap,
              isActive: controller.hasAudioTracks,
            ),

            const SizedBox(width: 6),

            // Speed button (pill)
            _AnimatedTapScale(
              onTap: onSpeedTap ?? () => _cycleSpeed(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: controller.playbackSpeed != 1.0
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: controller.playbackSpeed != 1.0
                        ? AppColors.primary
                        : Colors.white.withValues(alpha: 0.15),
                  ),
                ),
                child: Text(
                  '${controller.playbackSpeed}x',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 6),

            // Aspect ratio button
            _buildTopActionButton(
              icon: controller.resizeMode == VideoResizeMode.fit
                  ? Icons.fit_screen_rounded
                  : (controller.resizeMode == VideoResizeMode.fill
                      ? Icons.crop_free_rounded
                      : Icons.aspect_ratio_rounded),
              tooltip: 'Aspect Ratio',
              onTap: controller.cycleResizeMode,
            ),

            const SizedBox(width: 6),

            // Lock button
            _buildTopActionButton(
              icon: Icons.lock_outline_rounded,
              tooltip: 'Lock Screen',
              onTap: controller.toggleLock,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    bool isActive = false,
  }) {
    return _AnimatedTapScale(
      onTap: onTap ?? () {},
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.6)
                : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Center(
          child: Icon(
            icon,
            color: isActive ? AppColors.primary : Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }

  void _cycleSpeed() {
    const speeds = [1.0, 1.25, 1.5, 2.0, 0.5, 0.75];
    final currentIdx = speeds.indexOf(controller.playbackSpeed);
    final nextIdx = (currentIdx + 1) % speeds.length;
    controller.setPlaybackSpeed(speeds[nextIdx]);
  }

  // ─── Center Controls (strictly Rewind 10s, Play/Pause, Forward 10s) ───

  Widget _buildCenterControls() {
    switch (controller.state) {
      case PlaybackState.extracting:
        return const SizedBox.shrink(); // Cinematic loader handles extraction
      case PlaybackState.buffering:
        return _buildPlaybackButtons(showLoading: true);
      case PlaybackState.error:
        return _buildErrorView();
      case PlaybackState.playing:
      case PlaybackState.paused:
        return _buildPlaybackButtons();
      case PlaybackState.completed:
        return _buildPlaybackButtons(isCompleted: true);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPlaybackButtons({bool showLoading = false, bool isCompleted = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Skip backward 10s
        _AnimatedTapScale(
          onTap: () {
            HapticFeedback.lightImpact();
            controller.skipBackward();
          },
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.replay_10_rounded, color: Colors.white, size: 30),
            ),
          ),
        ),

        const SizedBox(width: 36),

        // Play/Pause center button (DanieWatch Red glowing circle)
        _AnimatedTapScale(
          onTap: () {
            HapticFeedback.mediumImpact();
            if (isCompleted) {
              controller.seekTo(Duration.zero);
            } else {
              controller.togglePlayPause();
            }
          },
          child: Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFE50914),
                  Color(0xFFB81D24),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE50914).withValues(alpha: 0.4),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: showLoading
                  ? const SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.8,
                        color: Colors.white,
                      ),
                    )
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return ScaleTransition(scale: animation, child: child);
                      },
                      child: Icon(
                        isCompleted
                            ? Icons.replay_rounded
                            : (controller.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded),
                        key: ValueKey<bool>(controller.isPlaying),
                        color: Colors.white,
                        size: 46,
                      ),
                    ),
            ),
          ),
        ),

        const SizedBox(width: 36),

        // Skip forward 10s
        _AnimatedTapScale(
          onTap: () {
            HapticFeedback.lightImpact();
            controller.skipForward();
          },
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.65),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 12,
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.forward_10_rounded, color: Colors.white, size: 30),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.primary, size: 44),
          const SizedBox(height: 12),
          Text(
            controller.errorMessage ?? 'Playback error occurred',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: controller.retry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Bottom Bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context) {
    final position = controller.position;
    final duration = controller.duration;
    final buffered = controller.buffered;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final bufferProgress = duration.inMilliseconds > 0
        ? buffered.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Seek bar with buffer progress in DanieWatch Red
            SizedBox(
              height: 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Buffer progress track (secondary)
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
                      activeTrackColor: Colors.white.withValues(alpha: 0.35),
                      inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                      thumbColor: Colors.transparent,
                      overlayShape: SliderComponentShape.noOverlay,
                    ),
                    child: Slider(
                      value: bufferProgress.clamp(0.0, 1.0),
                      onChanged: (_) {},
                    ),
                  ),
                  // Active seek slider (primary DanieWatch red)
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: AppColors.primary,
                      overlayColor: AppColors.primary.withValues(alpha: 0.25),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
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
                ],
              ),
            ),

            // Time + controls row (strictly NO episode button)
            Row(
              children: [
                // Time display
                Text(
                  _formatDuration(position),
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ' / ${_formatDuration(duration)}',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const Spacer(),

                // Sources button (if multiple sources available)
                if (controller.sources.isNotEmpty)
                  GestureDetector(
                    onTap: onSourceTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.dns_rounded, color: Colors.white70, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            controller.sources.length > 1
                                ? 'Server (${controller.sources.length})'
                                : 'Server 1',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Aspect ratio indicator
                GestureDetector(
                  onTap: controller.cycleResizeMode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Text(
                      controller.resizeModeLabel,
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
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

// ─── Animated Tap Scale Widget ──────────────────────────────────────────────

class _AnimatedTapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _AnimatedTapScale({required this.child, required this.onTap});

  @override
  State<_AnimatedTapScale> createState() => _AnimatedTapScaleState();
}

class _AnimatedTapScaleState extends State<_AnimatedTapScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}
