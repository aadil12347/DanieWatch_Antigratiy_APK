import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../player_controller.dart';
import 'vidstack_icons.dart';
import 'vidstack_theme.dart';
import 'vidstack_button.dart';
import 'vidstack_slider.dart';
import 'vidstack_volume_slider.dart';
import 'vidstack_settings_popover.dart';

/// Complete Vidstack 1:1 Player Overlay Layout.
/// Matches layout arrangement, icons, micro-animations, and features of Vidstack Player.
class VidstackPlayerOverlay extends StatefulWidget {
  final PlayerController controller;
  final VoidCallback? onBack;
  final VoidCallback? onPipTap;
  final VoidCallback? onSourceTap;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onAudioTap;
  final VoidCallback? onSubtitleTap;
  final VoidCallback? onSpeedTap;

  const VidstackPlayerOverlay({
    super.key,
    required this.controller,
    this.onBack,
    this.onPipTap,
    this.onSourceTap,
    this.onSettingsTap,
    this.onAudioTap,
    this.onSubtitleTap,
    this.onSpeedTap,
  });

  @override
  State<VidstackPlayerOverlay> createState() => _VidstackPlayerOverlayState();
}

class _VidstackPlayerOverlayState extends State<VidstackPlayerOverlay> {
  bool _showSettingsPopover = false;
  VidstackSettingsSubmenu _popoverSubmenu = VidstackSettingsSubmenu.root;
  bool _showCountdownTime = false;

  void _toggleSettingsPopover([VidstackSettingsSubmenu menu = VidstackSettingsSubmenu.root]) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_showSettingsPopover && _popoverSubmenu == menu) {
        _showSettingsPopover = false;
      } else {
        _popoverSubmenu = menu;
        _showSettingsPopover = true;
      }
    });
  }

  void _closeSettingsPopover() {
    if (_showSettingsPopover) {
      setState(() {
        _showSettingsPopover = false;
        _popoverSubmenu = VidstackSettingsSubmenu.root;
      });
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        // Locked mode: only show floating unlock pill
        if (widget.controller.isLocked) {
          return _buildLockedOverlay();
        }

        // Loading or Error states always visible
        if (widget.controller.state == PlaybackState.extracting ||
            widget.controller.state == PlaybackState.error) {
          return _buildFullOverlay(context, alwaysVisible: true);
        }

        // Normal mode: animated controls with 250ms cubic ease
        final visible = widget.controller.controlsVisible || _showSettingsPopover;

        return AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: VidstackTheme.normalAnim,
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: !visible,
            child: _buildFullOverlay(context),
          ),
        );
      },
    );
  }

  // ─── LOCKED OVERLAY ──────────────────────────────────────────────────────

  Widget _buildLockedOverlay() {
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned(
            right: 28,
            top: 0,
            bottom: 0,
            child: Center(
              child: VidstackButton(
                isCircle: false,
                size: 44,
                backgroundColor: VidstackTheme.surfaceGlass,
                border: Border.all(color: VidstackTheme.brand, width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.controller.toggleLock();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VidstackIcon.unlock(color: VidstackTheme.brand, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Tap to Unlock',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── FULL CONTROLS OVERLAY ───────────────────────────────────────────────

  Widget _buildFullOverlay(BuildContext context, {bool alwaysVisible = false}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _closeSettingsPopover,
      child: Container(
        decoration: const BoxDecoration(
          // Subtle overall background tint for contrast
          color: Colors.transparent,
        ),
        child: Stack(
          children: [
            // Top Scrim
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: IgnorePointer(
                child: Container(decoration: const BoxDecoration(gradient: VidstackTheme.topScrim)),
              ),
            ),

            // Bottom Scrim
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 140,
              child: IgnorePointer(
                child: Container(decoration: const BoxDecoration(gradient: VidstackTheme.bottomScrim)),
              ),
            ),

            // 1. Top Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(context),
            ),

            // 2. Center Playback Controls
            Center(
              child: _buildCenterControls(),
            ),

            // 3. Floating Vidstack Settings Popover (Anchored bottom right)
            if (_showSettingsPopover)
              Positioned(
                right: 20,
                bottom: 60,
                child: VidstackSettingsPopover(
                  controller: widget.controller,
                  onClose: _closeSettingsPopover,
                  initialMenu: _popoverSubmenu,
                ),
              ),

            // 4. Bottom Controls Deck (Slider + Action Row)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomDeck(context),
            ),
          ],
        ),
      ),
    );
  }

  // ─── TOP BAR ────────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Back Button (Vidstack frosted circular disc)
            VidstackButton(
              isCircle: true,
              size: 40,
              backgroundColor: VidstackTheme.surfaceGlass,
              border: Border.all(color: VidstackTheme.borderSubtle),
              tooltip: 'Back',
              onTap: widget.onBack ?? () => Navigator.of(context).pop(),
              child: VidstackIcon.chevronLeft(size: 20, color: Colors.white),
            ),

            const SizedBox(width: 14),

            // Title & Episode Badge
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.controller.isTvShow &&
                      widget.controller.season != null &&
                      widget.controller.episode != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: VidstackTheme.brand,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: const [
                          BoxShadow(color: VidstackTheme.brandGlow, blurRadius: 8),
                        ],
                      ),
                      child: Text(
                        'S${widget.controller.season.toString().padLeft(2, '0')}:E${widget.controller.episode.toString().padLeft(2, '0')}',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      widget.controller.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        shadows: const [
                          Shadow(color: Colors.black87, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Source Server Quick Button (if available)
            if (widget.controller.sources.isNotEmpty)
              VidstackButton(
                tooltip: 'Select Source Server',
                backgroundColor: VidstackTheme.surfaceGlass,
                border: Border.all(color: VidstackTheme.borderSubtle),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                size: 34,
                onTap: widget.onSourceTap ?? _toggleSettingsPopover,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VidstackIcon.server(size: 15, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      widget.controller.sources.length > 1
                          ? 'Server (${widget.controller.sources.length})'
                          : 'Server 1',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(width: 8),

            // Lock Screen Button
            VidstackButton(
              isCircle: true,
              size: 36,
              backgroundColor: VidstackTheme.surfaceGlass,
              border: Border.all(color: VidstackTheme.borderSubtle),
              tooltip: 'Lock Controls',
              onTap: widget.controller.toggleLock,
              child: VidstackIcon.lock(size: 17, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ─── CENTER PLAYBACK CONTROLS ──────────────────────────────────────────

  Widget _buildCenterControls() {
    switch (widget.controller.state) {
      case PlaybackState.extracting:
        return const SizedBox.shrink();
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
        // Skip Backward 10s (Vidstack circular icon)
        VidstackButton(
          isCircle: true,
          size: 56,
          backgroundColor: VidstackTheme.surfaceGlass,
          border: Border.all(color: VidstackTheme.borderMedium),
          tooltip: 'Rewind 10 seconds',
          onTap: () {
            HapticFeedback.lightImpact();
            widget.controller.skipBackward();
          },
          child: VidstackIcon.seekBackward10(size: 28, color: Colors.white),
        ),

        const SizedBox(width: 38),

        // Center Play / Pause / Replay Button (Vidstack Large Disc)
        VidstackButton(
          isCircle: true,
          size: 76,
          backgroundColor: VidstackTheme.brand,
          border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
          tooltip: isCompleted ? 'Replay' : (widget.controller.isPlaying ? 'Pause' : 'Play'),
          onTap: () {
            HapticFeedback.mediumImpact();
            if (isCompleted) {
              widget.controller.seekTo(Duration.zero);
            } else {
              widget.controller.togglePlayPause();
            }
          },
          child: showLoading
              ? const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : AnimatedSwitcher(
                  duration: VidstackTheme.fastAnim,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: isCompleted
                      ? VidstackIcon.replay(key: const ValueKey('replay'), size: 36, color: Colors.white)
                      : (widget.controller.isPlaying
                          ? VidstackIcon.pause(key: const ValueKey('pause'), size: 36, color: Colors.white)
                          : VidstackIcon.play(key: const ValueKey('play'), size: 36, color: Colors.white)),
                ),
        ),

        const SizedBox(width: 38),

        // Skip Forward 10s (Vidstack circular icon)
        VidstackButton(
          isCircle: true,
          size: 56,
          backgroundColor: VidstackTheme.surfaceGlass,
          border: Border.all(color: VidstackTheme.borderMedium),
          tooltip: 'Forward 10 seconds',
          onTap: () {
            HapticFeedback.lightImpact();
            widget.controller.skipForward();
          },
          child: VidstackIcon.seekForward10(size: 28, color: Colors.white),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: VidstackTheme.surfaceElevate,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: VidstackTheme.borderMedium),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: VidstackTheme.brand, size: 40),
          const SizedBox(height: 12),
          Text(
            widget.controller.errorMessage ?? 'Playback error occurred',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: widget.controller.retry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: VidstackTheme.brand,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── BOTTOM CONTROLS DECK ───────────────────────────────────────────────

  Widget _buildBottomDeck(BuildContext context) {
    final position = widget.controller.position;
    final duration = widget.controller.duration;
    final buffered = widget.controller.buffered;

    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;
    final bufferProgress = duration.inMilliseconds > 0
        ? buffered.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Vidstack Interactive Scrubber Slider
            VidstackSlider(
              progress: progress,
              bufferProgress: bufferProgress,
              position: position,
              duration: duration,
              onSeek: (pos) => widget.controller.seekTo(pos),
            ),

            // 2. Vidstack Controls Row
            Row(
              children: [
                // ─── LEFT CLUSTER ────────────────────────────────────────
                // Mini Play / Pause Toggle
                VidstackButton(
                  tooltip: widget.controller.isPlaying ? 'Pause (k)' : 'Play (k)',
                  onTap: widget.controller.togglePlayPause,
                  child: widget.controller.isPlaying
                      ? VidstackIcon.pause(size: 20)
                      : VidstackIcon.play(size: 20),
                ),

                const SizedBox(width: 4),

                // Mini Skip Backward 10s
                VidstackButton(
                  tooltip: 'Seek -10s (j)',
                  onTap: widget.controller.skipBackward,
                  child: VidstackIcon.seekBackward10(size: 19),
                ),

                const SizedBox(width: 4),

                // Mini Skip Forward 10s
                VidstackButton(
                  tooltip: 'Seek +10s (l)',
                  onTap: widget.controller.skipForward,
                  child: VidstackIcon.seekForward10(size: 19),
                ),

                const SizedBox(width: 4),

                // Vidstack Volume Button + Expandable Mini Slider
                const VidstackVolumeControl(),

                const SizedBox(width: 8),

                // Time Display with countdown toggle
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _showCountdownTime = !_showCountdownTime);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatDuration(position),
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        _showCountdownTime
                            ? ' / -${_formatDuration(duration - position > Duration.zero ? duration - position : Duration.zero)}'
                            : ' / ${_formatDuration(duration)}',
                        style: GoogleFonts.inter(
                          color: VidstackTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ─── RIGHT CLUSTER ───────────────────────────────────────
                // Subtitles / Captions Button
                VidstackButton(
                  tooltip: 'Subtitles (c)',
                  isActive: widget.controller.isSubtitleActive,
                  onTap: widget.onSubtitleTap ?? () => _toggleSettingsPopover(VidstackSettingsSubmenu.subtitles),
                  child: VidstackIcon.captions(
                    size: 20,
                    isActive: widget.controller.isSubtitleActive,
                  ),
                ),

                const SizedBox(width: 2),

                // Audio Tracks Button
                VidstackButton(
                  tooltip: 'Audio Track',
                  onTap: widget.onAudioTap ?? () => _toggleSettingsPopover(VidstackSettingsSubmenu.audio),
                  child: VidstackIcon.audio(size: 20),
                ),

                const SizedBox(width: 2),

                // Settings Gear Button (Opens Vidstack Popover)
                VidstackButton(
                  tooltip: 'Settings',
                  isActive: _showSettingsPopover,
                  onTap: () => _toggleSettingsPopover(VidstackSettingsSubmenu.root),
                  child: VidstackIcon.settings(size: 20),
                ),

                const SizedBox(width: 2),

                // Picture-in-Picture Button
                VidstackButton(
                  tooltip: 'Picture in Picture (p)',
                  onTap: widget.onPipTap,
                  child: VidstackIcon.pip(size: 20),
                ),

                const SizedBox(width: 2),

                // Aspect Ratio / Fullscreen Button
                VidstackButton(
                  tooltip: 'Resize Mode: ${widget.controller.resizeModeLabel}',
                  onTap: widget.controller.cycleResizeMode,
                  child: VidstackIcon.aspect(size: 20),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
