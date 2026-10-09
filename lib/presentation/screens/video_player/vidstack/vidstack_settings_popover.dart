import 'dart:ui';
import 'package:flutter/material.dart';
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
}

/// Vidstack Nested Popover Settings Menu.
/// Features:
/// - Ultra-premium obsidian frosted glass card with BackdropFilter blur
/// - Adaptive responsive height & width for all screen sizes (never overflows)
/// - Speed, Quality, and Audio submenus (Resize, Server, and Subtitle removed)
/// - Smooth animated transitions and checkmark indicators
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
    if (widget.controller.selectedResolution.isNotEmpty) {
      return widget.controller.selectedResolution.toUpperCase();
    }
    final cur = widget.controller.currentSource;
    if (cur != null) {
      if (cur.quality > 0) return '${cur.quality}p'.toUpperCase();
      final match = RegExp(r'(\d{3,4}p|4k)', caseSensitive: false).firstMatch(cur.displayName);
      if (match != null) return match.group(1)!.toUpperCase();
    }
    return '720P';
  }

  String _getAudioLabel() {
    final cur = widget.controller.currentAudioTrack;
    if (cur != null) {
      return cur.label ?? cur.language ?? 'Default';
    }
    return widget.controller.audioTracks.isNotEmpty
        ? (widget.controller.audioTracks.first.label ?? 'Default')
        : 'Default';
  }

  double _getCaretRightPadding() {
    switch (_currentMenu) {
      case VidstackSettingsSubmenu.subtitles:
        return 124.0;
      case VidstackSettingsSubmenu.audio:
        return 88.0;
      case VidstackSettingsSubmenu.root:
      case VidstackSettingsSubmenu.speed:
      case VidstackSettingsSubmenu.quality:
        return 52.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final popoverWidth = (media.size.width * 0.65).clamp(210.0, 260.0);
    final popoverMaxHeight = (media.size.height * 0.72).clamp(160.0, 275.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: popoverWidth,
            maxHeight: popoverMaxHeight,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: popoverWidth,
                decoration: BoxDecoration(
                  color: const Color(0xF210121C), // Deep obsidian frosted glass
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1.0,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black87,
                      blurRadius: 36,
                      spreadRadius: 2,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final inOffset = _isForward
                        ? const Offset(0.12, 0.0)
                        : const Offset(-0.12, 0.0);
                    return SlideTransition(
                      position: Tween<Offset>(begin: inOffset, end: Offset.zero).animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _buildSubmenuView(popoverMaxHeight),
                ),
              ),
            ),
          ),
        ),
        // Caret pointer pointing down towards the active button
        Padding(
          padding: EdgeInsets.only(right: _getCaretRightPadding()),
          child: const CustomPaint(
            size: Size(14, 7),
            painter: _CaretPainter(
              color: Color(0xF210121C),
              borderColor: Color(0x28FFFFFF),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubmenuView(double maxHeight) {
    switch (_currentMenu) {
      case VidstackSettingsSubmenu.root:
        return _buildRootMenu(maxHeight);
      case VidstackSettingsSubmenu.speed:
        return _buildSpeedMenu(maxHeight);
      case VidstackSettingsSubmenu.quality:
        return _buildQualityMenu(maxHeight);
      case VidstackSettingsSubmenu.audio:
        return _buildAudioMenu(maxHeight);
      case VidstackSettingsSubmenu.subtitles:
        return _buildSubtitleMenu(maxHeight);
    }
  }

  // ─── ROOT MENU ─────────────────────────────────────────────────────────

  Widget _buildRootMenu(double maxHeight) {
    return SingleChildScrollView(
      key: const ValueKey('root'),
      physics: const BouncingScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
            child: Row(
              children: [
                VidstackIcon.settings(size: 15, color: VidstackTheme.textMuted),
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
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, size: 14, color: VidstackTheme.textMuted),
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: VidstackTheme.borderSubtle, height: 1),

          // 1. Playback Speed
          _buildRootRow(
            icon: VidstackIcon.speed(size: 17),
            title: 'Speed',
            value: _getSpeedLabel(widget.controller.playbackSpeed),
            onTap: () => _navigateTo(VidstackSettingsSubmenu.speed),
          ),

          // 2. Quality
          _buildRootRow(
            icon: VidstackIcon.quality(size: 17),
            title: 'Quality',
            value: _getQualityLabel(),
            onTap: () => _navigateTo(VidstackSettingsSubmenu.quality),
          ),

          // 3. Audio Track
          _buildRootRow(
            icon: VidstackIcon.audio(size: 17),
            title: 'Audio',
            value: _getAudioLabel(),
            onTap: () => _navigateTo(VidstackSettingsSubmenu.audio),
          ),

          const SizedBox(height: 6),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
              constraints: const BoxConstraints(maxWidth: 95),
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
            VidstackIcon.chevronRight(size: 13, color: VidstackTheme.textMuted),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
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
                  VidstackIcon.chevronLeft(size: 15, color: Colors.white),
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
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
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

  Widget _buildSpeedMenu(double maxHeight) {
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
          constraints: BoxConstraints(maxHeight: maxHeight - 48),
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
        const SizedBox(height: 4),
      ],
    );
  }

  // ─── QUALITY SUBMENU ───────────────────────────────────────────────────

  Widget _buildQualityMenu(double maxHeight) {
    final Map<String, String> allResolutions =
        Map.from(widget.controller.availableResolutions);
    for (final s in widget.controller.sources) {
      String resKey;
      if (s.quality > 0) {
        resKey = '${s.quality}p';
      } else {
        final match =
            RegExp(r'(\d{3,4}p|4k)', caseSensitive: false).firstMatch(s.displayName);
        resKey = match != null ? match.group(1)!.toLowerCase() : '720p';
      }
      if (!allResolutions.containsKey(resKey)) {
        allResolutions[resKey] = s.url;
      }
    }

    final selectedRes = widget.controller.selectedResolution.toLowerCase();

    // Sort descending: 2160p/4k > 1080p > 720p > 480p > 360p
    final sortedResKeys = allResolutions.keys.toList()
      ..sort((a, b) {
        int getVal(String k) {
          if (k.toLowerCase().contains('4k') || k.contains('2160')) return 2160;
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
          constraints: BoxConstraints(maxHeight: maxHeight - 48),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (sortedResKeys.isNotEmpty) ...[
                  ...sortedResKeys.map((resKey) {
                    final lowerKey = resKey.toLowerCase();
                    final isCur = selectedRes.contains(lowerKey) ||
                        lowerKey.contains(selectedRes);

                    String subtitle;
                    if (lowerKey.contains('2160') || lowerKey.contains('4k')) {
                      subtitle = 'Ultra HD (4K)';
                    } else if (lowerKey.contains('1080')) {
                      subtitle = 'Full HD (1080p)';
                    } else if (lowerKey.contains('720')) {
                      subtitle = 'High Definition (720p)';
                    } else if (lowerKey.contains('480')) {
                      subtitle = 'Standard Definition (480p)';
                    } else {
                      subtitle = 'Resolution $resKey';
                    }

                    return _buildOptionRow(
                      title: resKey.toUpperCase(),
                      subtitle: subtitle,
                      isSelected: isCur,
                      onTap: () {
                        widget.controller.switchResolution(resKey);
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
        const SizedBox(height: 4),
      ],
    );
  }

  // ─── AUDIO SUBMENU ─────────────────────────────────────────────────────

  Widget _buildAudioMenu(double maxHeight) {
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
          icon: VidstackIcon.audio(size: 15, color: Colors.white),
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
            constraints: BoxConstraints(maxHeight: maxHeight - 48),
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
        const SizedBox(height: 4),
      ],
    );
  }

  // ─── SUBTITLES SUBMENU ──────────────────────────────────────────────────

  Widget _buildSubtitleMenu(double maxHeight) {
    final subs = widget.controller.subtitleSources;
    final current = widget.controller.currentSubtitleSource;
    final isOff = widget.controller.subtitlesExplicitlyDisabled ||
        current == null ||
        current.type == BetterPlayerSubtitlesSourceType.none ||
        current.name == 'Off';
    final availableSubs = subs
        .where((s) => s.type != BetterPlayerSubtitlesSourceType.none && s.name != 'Off')
        .toList();
    final bool isDirect = widget.initialMenu == VidstackSettingsSubmenu.subtitles;

    return Column(
      key: const ValueKey('subtitles'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSubmenuHeader(
          'Subtitles',
          icon: VidstackIcon.captions(size: 15, color: Colors.white),
        ),
        const Divider(color: VidstackTheme.borderSubtle, height: 1),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight - 48),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // "Off" option (Subtitles turned off)
                _buildOptionRow(
                  title: 'Off',
                  subtitle: 'Disable subtitles',
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
                if (availableSubs.isEmpty && isOff)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Text(
                      'No additional subtitle tracks available',
                      style: GoogleFonts.inter(
                        color: VidstackTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ...availableSubs.map((s) {
                  final isSelected = !isOff && (current.name == s.name);
                  final label = s.name ?? 'Subtitle Track';
                  return _buildOptionRow(
                    title: label,
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
        const SizedBox(height: 4),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
                size: 15,
                color: VidstackTheme.brand,
              )
            else
              const SizedBox(width: 15),
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
