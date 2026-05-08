import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Single dominant color palette extracted from poster images.
/// Only the most dominant color is used; the rest fall back to the default dark background.
class PosterColorPalette {
  final Color primary;
  final Color secondary;
  final Color tertiary;

  const PosterColorPalette({
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  /// Default dark background palette (near-black).
  static const fallback = PosterColorPalette(
    primary: Color(0xFF0D0D0D),
    secondary: Color(0xFF080808),
    tertiary: Color(0xFF050505),
  );

  /// The default dark background color used as the secondary/tertiary.
  static const _defaultDark = Color(0xFF0A0A0A);

  bool get isFallback =>
      primary == fallback.primary &&
      secondary == fallback.secondary &&
      tertiary == fallback.tertiary;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PosterColorPalette &&
          primary == other.primary &&
          secondary == other.secondary &&
          tertiary == other.tertiary;

  @override
  int get hashCode => Object.hash(primary, secondary, tertiary);
}

/// Extracts the single most dominant color from poster images.
class PosterColorService {
  PosterColorService._();
  static final instance = PosterColorService._();

  final Map<String, PosterColorPalette> _cache = {};

  Future<PosterColorPalette> extractFromUrl(String imageUrl) async {
    if (imageUrl.isEmpty) return PosterColorPalette.fallback;

    final cached = _cache[imageUrl];
    if (cached != null) return cached;

    try {
      final generator = await PaletteGenerator.fromImageProvider(
        ResizeImage(
          NetworkImage(imageUrl),
          width: 150,
          policy: ResizeImagePolicy.fit,
        ),
        maximumColorCount: 24,
        timeout: const Duration(seconds: 8),
      );

      final palette = _buildPalette(generator);
      _cache[imageUrl] = palette;
      return palette;
    } catch (_) {
      _cache[imageUrl] = PosterColorPalette.fallback;
      return PosterColorPalette.fallback;
    }
  }

  PosterColorPalette _buildPalette(PaletteGenerator gen) {
    // Use the single most dominant (most found) color in the image.
    // Prefer dominantColor first since it's the most frequently occurring.
    final Color rawDominant = gen.dominantColor?.color ??
        gen.vibrantColor?.color ??
        gen.darkVibrantColor?.color ??
        PosterColorPalette.fallback.primary;

    return PosterColorPalette(
      primary: _richDarken(rawDominant, 0.20),
      // Secondary and tertiary are the default dark background
      secondary: PosterColorPalette._defaultDark,
      tertiary: PosterColorPalette._defaultDark,
    );
  }

  /// Keep full saturation, only darken for background use.
  Color _richDarken(Color color, double targetLightness) {
    final hsl = HSLColor.fromColor(color);
    return HSLColor.fromAHSL(
      1.0,
      hsl.hue,
      hsl.saturation.clamp(0.5, 1.0),
      targetLightness.clamp(0.05, 0.25),
    ).toColor();
  }

  Future<void> preWarm(List<String> urls) async {
    await Future.wait(
      urls.where((url) => url.isNotEmpty && !_cache.containsKey(url))
          .map((url) => extractFromUrl(url)),
    );
  }

  void clearCache() => _cache.clear();
}
