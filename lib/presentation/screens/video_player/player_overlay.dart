import 'package:flutter/material.dart';
import 'player_controller.dart';
import 'vidstack/vidstack_player_overlay.dart';

/// PlayerOverlay delegate connecting DanieWatch to the Vidstack Player UI.
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
    return VidstackPlayerOverlay(
      controller: controller,
      onBack: onBack,
      onPipTap: onPipTap,
      onSourceTap: onSourceTap,
      onSettingsTap: onSettingsTap,
      onAudioTap: onAudioTap,
      onSubtitleTap: onSubtitleTap,
      onSpeedTap: onSpeedTap,
    );
  }
}
