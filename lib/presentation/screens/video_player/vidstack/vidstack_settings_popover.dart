import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:better_player_plus/better_player_plus.dart';
import '../player_controller.dart';
import 'vidstack_icons.dart';
import 'vidstack_theme.dart';

enum VidstackSettingsSubmenu {
  root,
  speed,
  quality,
  audio,
  subtitles,
  servers,
  aspect,
}

/// Vidstack Nested Popover Settings Menu.
/// Features:
/// - Floating obsidian frosted glass card with BackdropFilter blur
/// - Smooth horizontal slide-drilldown into submenus
/// - Active checkmark indicators
/// - Clean typography and Vidstack iconography
class VidstackSettingsPopover extends StatefulWidget {
  final PlayerController controller;
  final VoidCallback onClose;
  final VidstackSettingsSubmenu initialMenu;

  const VidstackSettingsPopover({
    super.key,
    required this.controller,
    required this.onClose,
    this.initialMenu = VidstackSettingsSubmenu.root,
  });

  @override
  State<VidstackSettingsPopover> createState() => _VidstackSettingsPopoverState();
}

class _VidstackSettingsPopoverState extends State<VidstackSettingsPopover>
    with SingleTickerProviderStateMixin {
  late VidstackSettingsSubmenu _currentMenu;
  bool _isForward = true;

  @override
  void initState() {
    super.initState();
    _currentMenu = widget.initialMenu;
  }

  void _navigateTo(VidstackSettingsSubmenu menu) {
    HapticFeedback.selectionClick();
    setState(() {
      _isForward = true;
      _currentMenu = menu;
    });
  }

  void _navigateBack() {
    HapticFeedback.selectionClick();
    setState(() {
      _isForward = false;
      _currentMenu = VidstackSettingsSubmenu.root;
    });
  }

  String _getSpeedLabel(double speed) {
    if (speed == 1.0) return '1.0x (Normal)';
    return '${speed}x';
  }

  String _getQualityLabel() {
    final bp = widget.controller.betterPlayerController;
    if (bp == null) return 'Auto';
    final tracks = bp.betterPlayerAsmsTracks;
    if (tracks.isEmpty) return 'Auto (1080p)';
    return 'Auto';
  }

  String _getAudioLabel() {
    final cur = widget.controller.currentAudioTrack;
    if (cur != null) {
      return cur.label ?? cur.language ?? 'Track 1';
    }
    return widget.controller.audioTracks.isNotEmpty
        ? (widget.controller.audioTracks.first.label ?? 'Default')
        : 'Default';
  }

  String _getSubtitleLabel() {
    final cur = widget.controller.currentSubtitleSource;
    if (cur == null || cur.name == 'Off' || cur.type == BetterPlayerSubtitlesSourceType.none) {
      return 'Off';
    }
    return cur.name ?? 'On';
  }

  String _getServerLabel() {
    final cur = widget.controller.currentSource;
    if (cur != null) {
      final name = cur.displayName.isNotEmpty
          ? cur.displayName
          : (cur.sourceName.isNotEmpty ? cur.sourceName : 'Server 1');
      return name;
    }
    return 'Default';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(VidstackTheme.cardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: VidstackTheme.blurRadius,
          sigmaY: VidstackTheme.blurRadius,
        ),
        child: Container(
          width: 275,
          decoration: BoxDecoration(
            color: VidstackTheme.surfaceElevate.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(VidstackTheme.cardRadius),
            border: Border.all(color: VidstackTheme.borderMedium, width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 28,
                spreadRadius: 2,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final inOffset = _isForward
                  ? const Offset(0.20, 0.0)
                  : const Offset(-0.20, 0.0);
              return SlideTransition(
                position: Tween<Offset>(begin: inOffset, end: Offset.zero).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _buildSubmenuView(),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmenuView() {
    switch (_currentMenu) {
      case VidstackSettingsSubmenu.root:
        return _buildRootMenu();
      case VidstackSettingsSubmenu.speed:
        return _buildSpeedMenu();
      case VidstackSettingsSubmenu.quality:
        return _buildQualityMenu();
      case VidstackSettingsSubmenu.audio:
        return _buildAudioMenu();
      case VidstackSettingsSubmenu.subtitles:
        return _buildSubtitleMenu();
      case VidstackSettingsSubmenu.servers:
        return _buildServerMenu();
      case VidstackSettingsSubmenu.aspect:
        return _buildAspectMenu();
    }
  }

  // ─── ROOT MENU ─────────────────────────────────────────────────────────

  Widget _buildRootMenu() {
    return Column(
      key: const ValueKey('root'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              VidstackIcon.settings(size: 16, color: VidstackTheme.textMuted),
              const SizedBox(width: 8),
              Text(
                'Settings',
                style: GoogleFonts.inter(
                  color: VidstackTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onClose,
                child: const Icon(Icons.close_rounded, size: 18, color: VidstackTheme.textMuted),
              ),
            ],
          ),
        ),

        const Divider(color: VidstackTheme.borderSubtle, height: 1),

        // 1. Playback Speed
        _buildRootRow(
          icon: VidstackIcon.speed(size: 18),
          title: 'Speed',
          value: _getSpeedLabel(widget.controller.playbackSpeed),
          onTap: () => _navigateTo(VidstackSettingsSubmenu.speed),
        ),

        // 2. Quality
        _buildRootRow(
          icon: VidstackIcon.quality(size: 18),
          title: 'Quality',
          value: _getQualityLabel(),
          onTap: () => _navigateTo(VidstackSettingsSubmenu.quality),
        ),

        // 3. Audio Track
        _buildRootRow(
          icon: VidstackIcon.audio(size: 18),
          title: 'Audio',
          value: _getAudioLabel(),
          onTap: () => _navigateTo(VidstackSettingsSubmenu.audio),
        ),

        // 4. Subtitles
        _buildRootRow(
          icon: VidstackIcon.captions(
            size: 18,
            isActive: widget.controller.isSubtitleActive,
          ),
          title: 'Subtitles',
          value: _getSubtitleLabel(),
          onTap: () => _navigateTo(VidstackSettingsSubmenu.subtitles),
        ),

        // 5. Server Source
        if (widget.controller.sources.isNotEmpty)
          _buildRootRow(
            icon: VidstackIcon.server(size: 18),
            title: 'Server',
            value: _getServerLabel(),
            onTap: () => _navigateTo(VidstackSettingsSubmenu.servers),
          ),

        // 6. Video Fit / Aspect Ratio
        _buildRootRow(
          icon: VidstackIcon.aspect(size: 18),
          title: 'Resize Mode',
          value: widget.controller.resizeModeLabel,
          onTap: () => _navigateTo(VidstackSettingsSubmenu.aspect),
        ),

        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildRootRow({
    required Widget icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.white10,
      highlightColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            SizedBox(width: 22, height: 22, child: Center(child: icon)),
            const SizedBox(width: 10),
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: GoogleFonts.inter(
                  color: VidstackTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 6),
            VidstackIcon.chevronRight(size: 14, color: VidstackTheme.textMuted),
          ],
        ),
      ),
    );
  }

  // ─── SUBMENU HEADER ────────────────────────────────────────────────────

  Widget _buildSubmenuHeader(String title) {
    return InkWell(
      onTap: _navigateBack,
      splashColor: Colors.white10,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            VidstackIcon.chevronLeft(size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SPEED SUBMENU ─────────────────────────────────────────────────────

  Widget _buildSpeedMenu() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentSpeed = widget.controller.playbackSpeed;

    return Column(
      key: const ValueKey('speed'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader('Playback Speed'),
        const Divider(color: VidstackTheme.borderSubtle, height: 1),
        ...speeds.map((s) {
          final isSelected = (currentSpeed - s).abs() < 0.01;
          return _buildOptionRow(
            title: s == 1.0 ? '1.0x (Normal)' : '${s}x',
            isSelected: isSelected,
            onTap: () {
              widget.controller.setPlaybackSpeed(s);
              _navigateBack();
            },
          );
        }),
        const SizedBox(height: 6),
      ],
    );
  }

  // ─── QUALITY SUBMENU ───────────────────────────────────────────────────

  Widget _buildQualityMenu() {
    final bp = widget.controller.betterPlayerController;
    final tracks = bp?.betterPlayerAsmsTracks ?? [];

    return Column(
      key: const ValueKey('quality'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader('Quality'),
        const Divider(color: VidstackTheme.borderSubtle, height: 1),
        _buildOptionRow(
          title: 'Auto (Recommended)',
          subtitle: 'Automatically adapts to bandwidth',
          isSelected: true,
          onTap: () {
            if (bp != null) {
              bp.setTrack(BetterPlayerAsmsTrack.defaultTrack());
            }
            _navigateBack();
          },
        ),
        ...tracks.map((t) {
          final label = t.height != null && t.height! > 0
              ? '${t.height}p'
              : (t.bitrate != null ? '${(t.bitrate! / 1000).round()} kbps' : 'Stream');
          return _buildOptionRow(
            title: label,
            isSelected: false,
            onTap: () {
              if (bp != null) {
                bp.setTrack(t);
              }
              _navigateBack();
            },
          );
        }),
        const SizedBox(height: 6),
      ],
    );
  }

  // ─── AUDIO SUBMENU ─────────────────────────────────────────────────────

  Widget _buildAudioMenu() {
    final tracks = widget.controller.audioTracks;
    final current = widget.controller.currentAudioTrack;

    return Column(
      key: const ValueKey('audio'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader('Audio Track'),
        const Divider(color: VidstackTheme.borderSubtle, height: 1),
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Default audio track active',
              style: GoogleFonts.inter(color: VidstackTheme.textMuted, fontSize: 12),
            ),
          )
        else
          ...tracks.map((t) {
            final isSelected = current != null && current.id == t.id;
            final label = t.label ?? t.language ?? 'Audio Track';
            return _buildOptionRow(
              title: label,
              isSelected: isSelected,
              onTap: () {
                widget.controller.setAudioTrack(t);
                _navigateBack();
              },
            );
          }),
        const SizedBox(height: 6),
      ],
    );
  }

  // ─── SUBTITLE SUBMENU ──────────────────────────────────────────────────

  Widget _buildSubtitleMenu() {
    final sources = widget.controller.subtitleSources;
    final current = widget.controller.currentSubtitleSource;
    final isOff = current == null ||
        current.name == 'Off' ||
        current.type == BetterPlayerSubtitlesSourceType.none;

    return Column(
      key: const ValueKey('subtitles'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader('Subtitles'),
        const Divider(color: VidstackTheme.borderSubtle, height: 1),
        _buildOptionRow(
          title: 'Off',
          isSelected: isOff,
          onTap: () {
            widget.controller.disableSubtitles();
            _navigateBack();
          },
        ),
        ...sources
            .where((s) => s.type != BetterPlayerSubtitlesSourceType.none && s.name != 'Off')
            .map((s) {
          final isSelected = !isOff && current?.name == s.name;
          return _buildOptionRow(
            title: s.name ?? 'Subtitle Track',
            isSelected: isSelected,
            onTap: () {
              widget.controller.setSubtitleSource(s);
              _navigateBack();
            },
          );
        }),
        const SizedBox(height: 6),
      ],
    );
  }

  // ─── SERVER SUBMENU ────────────────────────────────────────────────────

  Widget _buildServerMenu() {
    final sources = widget.controller.sources;
    final current = widget.controller.currentSource;

    return Column(
      key: const ValueKey('servers'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader('Source Server'),
        const Divider(color: VidstackTheme.borderSubtle, height: 1),
        ...sources.map((s) {
          final isSelected = current == s;
          final title = s.displayName.isNotEmpty ? s.displayName : s.sourceName;
          final subtitle = s.quality > 0
              ? '${s.quality}p${s.qualityTags != null ? ' • ${s.qualityTags}' : ''}'
              : (s.qualityTags);
          return _buildOptionRow(
            title: title,
            subtitle: subtitle,
            isSelected: isSelected,
            onTap: () {
              widget.controller.switchSource(s);
              _navigateBack();
            },
          );
        }),
        const SizedBox(height: 6),
      ],
    );
  }

  // ─── ASPECT RATIO SUBMENU ──────────────────────────────────────────────

  Widget _buildAspectMenu() {
    final curMode = widget.controller.resizeMode;

    return Column(
      key: const ValueKey('aspect'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader('Resize Mode'),
        const Divider(color: VidstackTheme.borderSubtle, height: 1),
        _buildOptionRow(
          title: 'Fit (Letterbox)',
          subtitle: 'Maintains original aspect ratio',
          isSelected: curMode == VideoResizeMode.fit,
          onTap: () {
            widget.controller.setResizeMode(VideoResizeMode.fit);
            _navigateBack();
          },
        ),
        _buildOptionRow(
          title: 'Fill (Crop)',
          subtitle: 'Fills display without black bars',
          isSelected: curMode == VideoResizeMode.fill,
          onTap: () {
            widget.controller.setResizeMode(VideoResizeMode.fill);
            _navigateBack();
          },
        ),
        _buildOptionRow(
          title: 'Stretch (Full)',
          subtitle: 'Stretches content to screen edges',
          isSelected: curMode == VideoResizeMode.zoom,
          onTap: () {
            widget.controller.setResizeMode(VideoResizeMode.zoom);
            _navigateBack();
          },
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildOptionRow({
    required String title,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      splashColor: Colors.white10,
      highlightColor: Colors.white.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: isSelected ? Colors.white : VidstackTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        color: VidstackTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              VidstackIcon.check(
                size: 16,
                color: VidstackTheme.brand,
              )
            else
              const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}
