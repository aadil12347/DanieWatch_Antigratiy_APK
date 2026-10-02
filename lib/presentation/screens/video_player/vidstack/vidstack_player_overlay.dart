import 'dart:async';
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

class _VidstackPlayerOverlayState extends State<VidstackPlayerOverlay>
    with SingleTickerProviderStateMixin {
  bool _showSettingsPopover = false;
  VidstackSettingsSubmenu _popoverSubmenu = VidstackSettingsSubmenu.root;
  bool _showCountdownTime = false;

  late final AnimationController _popoverAnimController;
  late final Animation<double> _popoverScaleAnim;
  late final Animation<double> _popoverFadeAnim;

  // ─── Locked State Auto-Vanish ──────────────────────────────────────────
  bool _showUnlockButton = true;
  Timer? _unlockVanishTimer;

  @override
  void initState() {
    super.initState();
    _startUnlockVanishTimer();
    _popoverAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _popoverScaleAnim = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _popoverAnimController,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      ),
    );
    _popoverFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _popoverAnimController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );
  }

  @override
  void dispose() {
    _unlockVanishTimer?.cancel();
    _popoverAnimController.dispose();
    super.dispose();
  }

  void _startUnlockVanishTimer() {
    _unlockVanishTimer?.cancel();
    _unlockVanishTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showUnlockButton = false);
      }
    });
  }

  void _revealUnlockButton() {
    setState(() => _showUnlockButton = true);
    _startUnlockVanishTimer();
  }

  void _toggleSettingsPopover([VidstackSettingsSubmenu menu = VidstackSettingsSubmenu.root]) {
    if (_showSettingsPopover && _popoverSubmenu == menu) {
      _closeSettingsPopover();
    } else {
      widget.controller.setModalOpen(true);
      setState(() {
        _popoverSubmenu = menu;
        _showSettingsPopover = true;
      });
      _popoverAnimController.forward(from: 0.0);
    }
  }

  void _closeSettingsPopover() {
    if (_showSettingsPopover) {
      widget.controller.setModalOpen(false);
      _popoverAnimController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _showSettingsPopover = false;
            _popoverSubmenu = VidstackSettingsSubmenu.root;
          });
        }
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

  String _getCleanTitle() {
    var t = widget.controller.title.trim();
    if (widget.controller.isTvShow) {
      t = t.replaceAll(RegExp(r'[\s\-–—:]+(?:Season\s*\d+\s*)?(?:Episode|Ep\.?)\s*\d+.*$', caseSensitive: false), '');
      t = t.replaceAll(RegExp(r'[\s\-–—:]+S\d+\s*E\d+.*$', caseSensitive: false), '');
      t = t.replaceAll(RegExp(r'[\s\-–—:]+Season\s*\d+.*$', caseSensitive: false), '');
      t = t.replaceAll(RegExp(r'^(?:Season\s*\d+\s*)?(?:Episode|Ep\.?)\s*\d+[\s\-–—:]*', caseSensitive: false), '');
    }
    t = t.trim();
    return t.isEmpty ? widget.controller.title : t;
  }

  double _getPopoverRightOffset(BuildContext context) {
    final safeRight = MediaQuery.of(context).padding.right;

    switch (_popoverSubmenu) {
      case VidstackSettingsSubmenu.subtitles:
        return safeRight + 65.0;
      case VidstackSettingsSubmenu.audio:
        return safeRight + 25.0;
      case VidstackSettingsSubmenu.root:
      case VidstackSettingsSubmenu.speed:
      case VidstackSettingsSubmenu.quality:
      case VidstackSettingsSubmenu.servers:
      case VidstackSettingsSubmenu.aspect:
      default:
        return safeRight + 16.0;
    }
  }

  Alignment _getPopoverAlignment() {
    switch (_popoverSubmenu) {
      case VidstackSettingsSubmenu.subtitles:
      case VidstackSettingsSubmenu.audio:
        return Alignment.bottomCenter;
      case VidstackSettingsSubmenu.root:
      case VidstackSettingsSubmenu.speed:
      case VidstackSettingsSubmenu.quality:
      case VidstackSettingsSubmenu.servers:
      case VidstackSettingsSubmenu.aspect:
      default:
        return const Alignment(0.24, 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        // Locked mode: only show floating unlock pill with auto-vanish
        if (widget.controller.isLocked) {
          return _buildLockedOverlay();
        }

        // Loading or Error states always visible
        if (widget.controller.state == PlaybackState.extracting ||
            widget.controller.state == PlaybackState.error) {
          return _buildFullOverlay(context, alwaysVisible: true);
        }

        // Normal mode: animated controls with 250ms cubic ease
        final visible = widget.controller.controlsVisible;

        // Auto close popover if controls were hidden
        if (!visible && _showSettingsPopover) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _showSettingsPopover) {
              _closeSettingsPopover();
            }
          });
        }

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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _revealUnlockButton,
      child: SizedBox.expand(
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      const Spacer(),
                      AnimatedOpacity(
                        opacity: _showUnlockButton ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        child: IgnorePointer(
                          ignoring: !_showUnlockButton,
                          child: VidstackButton(
                            isCircle: true,
                            size: 38,
                            backgroundColor: VidstackTheme.surfaceGlass,
                            border: Border.all(color: VidstackTheme.brand, width: 1.5),
                            tooltip: 'Unlock Controls',
                            onTap: () {
                              widget.controller.toggleLock();
                            },
                            child: VidstackIcon.unlock(size: 18, color: VidstackTheme.brand),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── FULL CONTROLS OVERLAY ───────────────────────────────────────────────

  Widget _buildFullOverlay(BuildContext context, {bool alwaysVisible = false}) {
    final popoverBottom = MediaQuery.of(context).padding.bottom + 78.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_showSettingsPopover) {
          _closeSettingsPopover();
        } else {
          widget.controller.toggleControls();
        }
      },
      onDoubleTapDown: (details) {
        final screenWidth = MediaQuery.of(context).size.width;
        if (details.localPosition.dx < screenWidth * 0.35) {
          widget.controller.skipBackward();
        } else if (details.localPosition.dx > screenWidth * 0.65) {
          widget.controller.skipForward();
        } else {
          HapticFeedback.lightImpact();
          widget.controller.togglePlayPause();
        }
      },
      onDoubleTap: () {},
      child: Container(
        decoration: const BoxDecoration(
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

            // 1. Top Bar (Back on Left, Clean Title Center, Lock on Right only)
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

            // 3. Bottom Controls Deck (Slider + Action Row)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomDeck(context),
            ),

            // 4. Floating Vidstack Settings Popover (Rendered AFTER Bottom Deck so it is on TOP of slider)
            if (_showSettingsPopover)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                right: _getPopoverRightOffset(context),
                bottom: popoverBottom,
                child: FadeTransition(
                  opacity: _popoverFadeAnim,
                  child: ScaleTransition(
                    scale: _popoverScaleAnim,
                    alignment: _getPopoverAlignment(),
                    child: VidstackSettingsPopover(
                      controller: widget.controller,
                      onClose: _closeSettingsPopover,
                      initialMenu: _popoverSubmenu,
                    ),
                  ),
                ),
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
              size: 38,
              backgroundColor: VidstackTheme.surfaceGlass,
              border: Border.all(color: VidstackTheme.borderSubtle),
              tooltip: 'Back',
              onTap: widget.onBack ?? () => Navigator.of(context).pop(),
              child: VidstackIcon.chevronLeft(size: 20, color: Colors.white),
            ),

            // Top Center: FIRST the S01 E01 Red Badge, THEN the Clean Single-Line Title
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.controller.isTvShow &&
                          widget.controller.season != null &&
                          widget.controller.episode != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: VidstackTheme.brand, // Exact red matching center play button
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: VidstackTheme.brand.withValues(alpha: 0.45),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            'S${widget.controller.season.toString().padLeft(2, '0')} E${widget.controller.episode.toString().padLeft(2, '0')}',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          _getCleanTitle(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            shadows: const [
                              Shadow(color: Colors.black87, blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Lock Screen Button (top right only, matches unlock position)
            VidstackButton(
              isCircle: true,
              size: 38,
              backgroundColor: VidstackTheme.surfaceGlass,
              border: Border.all(color: VidstackTheme.borderSubtle),
              tooltip: 'Lock Controls',
              onTap: () {
                _revealUnlockButton();
                widget.controller.toggleLock();
              },
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
            HapticFeedback.lightImpact(); // minor vibration on play pause
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

    final isSubtitlesOpen = _showSettingsPopover && _popoverSubmenu == VidstackSettingsSubmenu.subtitles;
    final isAudioOpen = _showSettingsPopover && _popoverSubmenu == VidstackSettingsSubmenu.audio;
    final isSettingsOpen = _showSettingsPopover && (
      _popoverSubmenu == VidstackSettingsSubmenu.root ||
      _popoverSubmenu == VidstackSettingsSubmenu.speed ||
      _popoverSubmenu == VidstackSettingsSubmenu.quality ||
      _popoverSubmenu == VidstackSettingsSubmenu.servers ||
      _popoverSubmenu == VidstackSettingsSubmenu.aspect
    );

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

            const SizedBox(height: 2),

            // 2. Vidstack Controls Row
            Row(
              children: [
                // ─── LEFT CLUSTER ────────────────────────────────────────
                // Mini Play / Pause Toggle
                VidstackButton(
                  tooltip: widget.controller.isPlaying ? 'Pause (k)' : 'Play (k)',
                  onTap: () {
                    HapticFeedback.lightImpact(); // minor vibration on play pause
                    widget.controller.togglePlayPause();
                  },
                  child: widget.controller.isPlaying
                      ? VidstackIcon.pause(size: 20)
                      : VidstackIcon.play(size: 20),
                ),

                const SizedBox(width: 4),

                // Vidstack Volume Button + Expandable Mini Slider
                const VidstackVolumeControl(),

                const SizedBox(width: 8),

                // Time Display with countdown toggle
                GestureDetector(
                  onTap: () {
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
                // Subtitles / Captions Button (opens sleek popover directly to subtitles tab)
                VidstackButton(
                  tooltip: 'Subtitles (c)',
                  isActive: isSubtitlesOpen || widget.controller.isSubtitleActive,
                  onTap: () => _toggleSettingsPopover(VidstackSettingsSubmenu.subtitles),
                  child: AnimatedScale(
                    scale: isSubtitlesOpen ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    child: VidstackIcon.captions(
                      size: 20,
                      isActive: isSubtitlesOpen || widget.controller.isSubtitleActive,
                    ),
                  ),
                ),

                const SizedBox(width: 2),

                // Audio Tracks Button (opens sleek popover directly to audio tab)
                VidstackButton(
                  tooltip: 'Audio Track',
                  isActive: isAudioOpen,
                  onTap: () => _toggleSettingsPopover(VidstackSettingsSubmenu.audio),
                  child: AnimatedScale(
                    scale: isAudioOpen ? 1.15 : 1.0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    child: VidstackIcon.audio(
                      size: 20,
                      color: isAudioOpen ? VidstackTheme.brand : Colors.white,
                    ),
                  ),
                ),

                const SizedBox(width: 2),

                // Settings Gear Button (Opens Vidstack Popover)
                VidstackButton(
                  tooltip: 'Settings',
                  isActive: isSettingsOpen,
                  onTap: () => _toggleSettingsPopover(VidstackSettingsSubmenu.root),
                  child: AnimatedRotation(
                    turns: isSettingsOpen ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    child: AnimatedScale(
                      scale: isSettingsOpen ? 1.12 : 1.0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutBack,
                      child: VidstackIcon.settings(
                        size: 20,
                        color: isSettingsOpen ? VidstackTheme.brand : Colors.white,
                      ),
                    ),
                  ),
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
