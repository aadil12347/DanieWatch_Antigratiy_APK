import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:volume_controller/volume_controller.dart';
import 'vidstack_icons.dart';
import 'vidstack_theme.dart';
import 'vidstack_button.dart';

/// Vidstack Volume Control with dynamic icon and expandable mini slider.
class VidstackVolumeControl extends StatefulWidget {
  const VidstackVolumeControl({super.key});

  @override
  State<VidstackVolumeControl> createState() => _VidstackVolumeControlState();
}

class _VidstackVolumeControlState extends State<VidstackVolumeControl> {
  double _volume = 0.5;
  double _lastNonZeroVolume = 0.5;
  bool _isMuted = false;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _initVolume();
  }

  Future<void> _initVolume() async {
    try {
      final vol = await VolumeController.instance.getVolume();
      if (mounted) {
        setState(() {
          _volume = vol;
          _isMuted = vol <= 0.01;
          if (vol > 0.01) _lastNonZeroVolume = vol;
        });
      }
    } catch (_) {}
  }

  void _toggleMute() {
    HapticFeedback.lightImpact();
    if (_isMuted) {
      final target = _lastNonZeroVolume > 0.05 ? _lastNonZeroVolume : 0.5;
      VolumeController.instance.setVolume(target);
      setState(() {
        _volume = target;
        _isMuted = false;
      });
    } else {
      _lastNonZeroVolume = _volume;
      VolumeController.instance.setVolume(0.0);
      setState(() {
        _volume = 0.0;
        _isMuted = true;
      });
    }
  }

  void _setVolume(double newVol) {
    final clamped = newVol.clamp(0.0, 1.0);
    VolumeController.instance.setVolume(clamped);
    setState(() {
      _volume = clamped;
      _isMuted = clamped <= 0.01;
      if (clamped > 0.01) _lastNonZeroVolume = clamped;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget volumeIcon;
    if (_isMuted || _volume <= 0.01) {
      volumeIcon = VidstackIcon.volumeMute(size: 20);
    } else if (_volume < 0.5) {
      volumeIcon = VidstackIcon.volumeLow(size: 20);
    } else {
      volumeIcon = VidstackIcon.volumeHigh(size: 20);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isExpanded = true),
      onExit: (_) => setState(() => _isExpanded = false),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dynamic Speaker Button
          VidstackButton(
            tooltip: _isMuted ? 'Unmute' : 'Mute',
            onTap: _toggleMute,
            child: volumeIcon,
          ),

          // Expandable Mini Volume Slider
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: _isExpanded ? 72.0 : 0.0,
            height: 28,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0, left: 2.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  if (totalWidth <= 10) return const SizedBox.shrink();

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (details) {
                      final p = (details.localPosition.dx / totalWidth).clamp(0.0, 1.0);
                      _setVolume(p);
                    },
                    onTapDown: (details) {
                      final p = (details.localPosition.dx / totalWidth).clamp(0.0, 1.0);
                      _setVolume(p);
                    },
                    child: Center(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          // Base track
                          Container(
                            height: 3.5,
                            width: totalWidth,
                            decoration: BoxDecoration(
                              color: VidstackTheme.trackBackground,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          // Active volume track
                          Container(
                            height: 3.5,
                            width: totalWidth * _volume,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          // Thumb dot
                          Positioned(
                            left: (totalWidth * _volume - 5).clamp(0.0, totalWidth - 10),
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: Colors.black45, blurRadius: 4),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
