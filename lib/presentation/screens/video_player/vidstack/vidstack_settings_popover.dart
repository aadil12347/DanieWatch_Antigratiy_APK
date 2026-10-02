import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:better_player_plus/better_player_plus.dart';
import '../../../../services/extraction/models.dart';
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

  @override
  void didUpdateWidget(VidstackSettingsPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMenu != oldWidget.initialMenu) {
      setState(() {
        _currentMenu = widget.initialMenu;
        _isForward = true;
      });
    }
  }

  void _navigateTo(VidstackSettingsSubmenu menu) {
    setState(() {
      _isForward = true;
      _currentMenu = menu;
    });
  }

  void _navigateBack() {
    if (widget.initialMenu != VidstackSettingsSubmenu.root &&
        _currentMenu == widget.initialMenu) {
      widget.onClose();
      return;
    }
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
    final cur = widget.controller.currentSource;
    if (cur != null) {
      if (cur.quality > 0) return '${cur.quality}p';
      final match = RegExp(r'(\d{3,4}p|4k)', caseSensitive: false).firstMatch(cur.displayName);
      if (match != null) return match.group(1)!.toUpperCase();
    }
    final bp = widget.controller.betterPlayerController;
    if (bp != null && bp.betterPlayerAsmsTracks.isNotEmpty) {
      return 'Auto';
    }
    return '720p';
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

  double _getCaretRightPadding() {
    switch (_currentMenu) {
      case VidstackSettingsSubmenu.audio:
      case VidstackSettingsSubmenu.subtitles:
        return 123.0;
      case VidstackSettingsSubmenu.root:
      case VidstackSettingsSubmenu.speed:
      case VidstackSettingsSubmenu.quality:
      case VidstackSettingsSubmenu.servers:
      case VidstackSettingsSubmenu.aspect:
      default:
        return 92.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: 260,
          decoration: BoxDecoration(
            color: const Color(0xFF14151F), // 100% solid, fully opaque obsidian background (zero transparency)
            borderRadius: BorderRadius.circular(VidstackTheme.cardRadius),
            border: Border.all(color: const Color(0x38FFFFFF), width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: Colors.black,
                blurRadius: 32,
                spreadRadius: 3,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(VidstackTheme.cardRadius),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final inOffset = _isForward
                    ? const Offset(0.15, 0.0)
                    : const Offset(-0.15, 0.0);
                return SlideTransition(
                  position: Tween<Offset>(begin: inOffset, end: Offset.zero).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: _buildSubmenuView(),
            ),
          ),
        ),
        // Caret pointer pointing down to the active button
        Padding(
          padding: EdgeInsets.only(right: _getCaretRightPadding()),
          child: CustomPaint(
            size: const Size(14, 7),
            painter: const _CaretPainter(
              color: Color(0xFF14151F),
              borderColor: Color(0x38FFFFFF),
            ),
          ),
        ),
      ],
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

  Widget _buildSubmenuHeader(String title, {Widget? icon}) {
    final bool isDirectModal = widget.initialMenu != VidstackSettingsSubmenu.root &&
        _currentMenu == widget.initialMenu;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
      child: Row(
        children: [
          if (isDirectModal) ...[
            if (icon != null) ...[
              icon,
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else ...[
            GestureDetector(
              onTap: _navigateBack,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VidstackIcon.chevronLeft(size: 16, color: Colors.white),
                  const SizedBox(width: 6),
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
          ],
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
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
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: speeds.map((s) {
                final isSelected = (currentSpeed - s).abs() < 0.01;
                return _buildOptionRow(
                  title: s == 1.0 ? '1.0x (Normal)' : '${s}x',
                  isSelected: isSelected,
                  onTap: () {
                    widget.controller.setPlaybackSpeed(s);
                    _navigateBack();
                  },
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  // ─── QUALITY SUBMENU ───────────────────────────────────────────────────

  Widget _buildQualityMenu() {
    final bp = widget.controller.betterPlayerController;
    final asmsTracks = bp?.betterPlayerAsmsTracks ?? [];
    final sources = widget.controller.sources;
    final current = widget.controller.currentSource;

    // Group and pick best server link for each distinct resolution
    final Map<String, ExtractorLink> resolutionMap = {};
    for (final s in sources) {
      String resKey;
      if (s.quality > 0) {
        resKey = '${s.quality}p';
      } else {
        final match = RegExp(r'(\d{3,4}p|4k)', caseSensitive: false).firstMatch(s.displayName);
        resKey = match != null ? match.group(1)!.toLowerCase() : '720p';
      }
      // Prefer Server 2 (FSLv2) if multiple links have the same resolution
      final sLower = s.displayName.toLowerCase();
      if (!resolutionMap.containsKey(resKey) ||
          sLower.contains('fslv2') ||
          sLower.contains('server 2')) {
        resolutionMap[resKey] = s;
      }
    }

    // Sort descending: 2160p/4k > 1080p > 720p > 480p > 360p
    final sortedResKeys = resolutionMap.keys.toList()
      ..sort((a, b) {
        int getVal(String k) {
          if (k.contains('4k') || k.contains('2160')) return 2160;
          return int.tryParse(k.replaceAll(RegExp(r'\D'), '')) ?? 0;
        }
        return getVal(b).compareTo(getVal(a));
      });

    return Column(
      key: const ValueKey('quality'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader('Quality'),
        const Divider(color: VidstackTheme.borderSubtle, height: 1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (asmsTracks.isNotEmpty) ...[
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
                  ...asmsTracks.map((t) {
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
                ] else if (sortedResKeys.isNotEmpty) ...[
                  ...sortedResKeys.map((resKey) {
                    final source = resolutionMap[resKey]!;
                    final isCur = current != null &&
                        (current.quality > 0
                            ? '${current.quality}p'.toLowerCase() == resKey
                            : current.displayName.toLowerCase().contains(resKey.toLowerCase()));

                    String subtitle;
                    if (resKey.contains('2160') || resKey.contains('4k')) {
                      subtitle = 'Ultra HD (4K)';
                    } else if (resKey.contains('1080')) {
                      subtitle = 'Full HD (1080p)';
                    } else if (resKey.contains('720')) {
                      subtitle = 'High Definition (720p)';
                    } else if (resKey.contains('480')) {
                      subtitle = 'Standard Definition (480p)';
                    } else {
                      subtitle = 'Resolution $resKey';
                    }

                    return _buildOptionRow(
                      title: resKey.toUpperCase(),
                      subtitle: subtitle,
                      isSelected: isCur,
                      onTap: () {
                        widget.controller.switchSource(source);
                        _navigateBack();
                      },
                    );
                  }),
                ] else ...[
                  _buildOptionRow(
                    title: 'Auto (720p)',
                    subtitle: 'Optimized stream resolution',
                    isSelected: true,
                    onTap: _navigateBack,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  // ─── AUDIO SUBMENU ─────────────────────────────────────────────────────

  Widget _buildAudioMenu() {
    final tracks = widget.controller.audioTracks;
    final current = widget.controller.currentAudioTrack;
    final bool isDirect = widget.initialMenu == VidstackSettingsSubmenu.audio;

    return Column(
      key: const ValueKey('audio'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader(
          'Audio Track',
          icon: VidstackIcon.audio(size: 16, color: Colors.white),
        ),
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
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: tracks.map((t) {
                  final isSelected = current != null && current.id == t.id;
                  final label = t.label ?? t.language ?? 'Audio Track';
                  return _buildOptionRow(
                    title: label,
                    isSelected: isSelected,
                    onTap: () {
                      widget.controller.setAudioTrack(t);
                      if (isDirect) {
                        widget.onClose();
                      } else {
                        _navigateBack();
                      }
                    },
                  );
                }).toList(),
              ),
            ),
          ),
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
    final bool isDirect = widget.initialMenu == VidstackSettingsSubmenu.subtitles;

    final validSources = sources
        .where((s) => s.type != BetterPlayerSubtitlesSourceType.none && s.name != 'Off')
        .toList();

    return Column(
      key: const ValueKey('subtitles'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader(
          'Subtitles',
          icon: VidstackIcon.captions(size: 16, color: Colors.white),
        ),
        const Divider(color: VidstackTheme.borderSubtle, height: 1),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildOptionRow(
                  title: 'Off',
                  isSelected: isOff,
                  onTap: () {
                    widget.controller.disableSubtitles();
                    if (isDirect) {
                      widget.onClose();
                    } else {
                      _navigateBack();
                    }
                  },
                ),
                ...validSources.map((s) {
                  final isSelected = !isOff && current?.name == s.name;
                  return _buildOptionRow(
                    title: s.name ?? 'Subtitle Track',
                    isSelected: isSelected,
                    onTap: () {
                      widget.controller.setSubtitleSource(s);
                      if (isDirect) {
                        widget.onClose();
                      } else {
                        _navigateBack();
                      }
                    },
                  );
                }),
              ],
            ),
          ),
        ),
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
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: sources.map((s) {
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
              }).toList(),
            ),
          ),
        ),
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
      onTap: onTap,
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

class _CaretPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  const _CaretPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    final fillPaint = Paint()..color = color;
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final strokePath = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(strokePath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
