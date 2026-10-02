import 'package:flutter/material.dart';

/// Vidstack Design System Tokens & Theme Constants.
/// Faithfully modeled after Vidstack Player (https://vidstack.io/player/demo/).
class VidstackTheme {
  VidstackTheme._();

  // ─── Surfaces & Glassmorphism ──────────────────────────────────────────
  static const Color surface = Color(0xEE0B0D13);
  static const Color surfaceElevate = Color(0xF212141E);
  static const Color surfaceGlass = Color(0x99000000);
  static const Color surfaceOverlay = Color(0xCC08090E);

  // ─── Borders ───────────────────────────────────────────────────────────
  static const Color borderSubtle = Color(0x18FFFFFF);
  static const Color borderMedium = Color(0x28FFFFFF);
  static const Color borderHighlight = Color(0x40FFFFFF);

  // ─── Typography & Icons ────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB8FFFFFF);
  static const Color textMuted = Color(0x70FFFFFF);
  static const Color textDisabled = Color(0x40FFFFFF);

  // ─── Brand & Playback Accents ──────────────────────────────────────────
  static const Color brand = Color(0xFFE50914); // DanieWatch Crimson Accent
  static const Color brandGlow = Color(0x4DE50914);
  static const Color brandSubtle = Color(0x26E50914);

  // ─── Sliders & Progress Tracks ─────────────────────────────────────────
  static const Color trackBackground = Color(0x33FFFFFF);
  static const Color trackBuffer = Color(0x70FFFFFF);
  static const Color trackProgress = Color(0xFFE50914);
  static const Color trackThumb = Color(0xFFFFFFFF);

  // ─── Blur Filter Radii ─────────────────────────────────────────────────
  static const double blurRadius = 20.0;
  static const double cardRadius = 12.0;
  static const double pillRadius = 24.0;
  static const double buttonRadius = 8.0;

  // ─── Animation Timings ─────────────────────────────────────────────────
  static const Duration fastAnim = Duration(milliseconds: 150);
  static const Duration normalAnim = Duration(milliseconds: 250);
  static const Duration springAnim = Duration(milliseconds: 350);

  // ─── Gradients ─────────────────────────────────────────────────────────
  static const LinearGradient topScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xD9000000),
      Color(0x99000000),
      Color(0x00000000),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  static const LinearGradient bottomScrim = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [
      Color(0xE6000000),
      Color(0xA6000000),
      Color(0x00000000),
    ],
    stops: [0.0, 0.50, 1.0],
  );
}
