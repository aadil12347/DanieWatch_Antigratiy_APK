import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// 3-color palette extracted from poster images.
class PosterColorPalette {
  final Color primary;
  final Color secondary;
  final Color tertiary;

  const PosterColorPalette({
    required this.primary,
    required this.secondary,
    required this.tertiary,
  });

  static const fallback = PosterColorPalette(
    primary: Color(0xFF0D0D0D),
    secondary: Color(0xFF080808),
    tertiary: Color(0xFF050505),
  );

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

/// Extracts 3 rich, vivid colors from poster images.
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
    final Color rawPrimary = gen.vibrantColor?.color ??
        gen.dominantColor?.color ??
        gen.darkVibrantColor?.color ??
        PosterColorPalette.fallback.primary;

    final Color rawSecondary = gen.darkVibrantColor?.color ??
        gen.darkMutedColor?.color ??
        gen.mutedColor?.color ??
        PosterColorPalette.fallback.secondary;

    final Color rawTertiary = gen.lightVibrantColor?.color ??
        gen.lightMutedColor?.color ??
        gen.dominantColor?.color ??
        PosterColorPalette.fallback.tertiary;

    return PosterColorPalette(
      primary: _richDarken(rawPrimary, 0.20),
      secondary: _richDarken(rawSecondary, 0.12),
      tertiary: _richDarken(rawTertiary, 0.08),
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
