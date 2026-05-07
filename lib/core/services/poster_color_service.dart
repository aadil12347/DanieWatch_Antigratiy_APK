import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Represents a cinema-grade color palette extracted from a poster image.
/// All colors are pre-processed to work as dark-mode backgrounds.
class PosterColorPalette {
  final Color dominant;
  final Color accent;
  final Color muted;

  const PosterColorPalette({
    required this.dominant,
    required this.accent,
    required this.muted,
  });

  /// Fallback palette when extraction fails — blends into the dark theme.
  static const fallback = PosterColorPalette(
    dominant: Color(0xFF1A1A19),
    accent: Color(0xFF27272A),
    muted: Color(0xFF141413),
  );

  /// Whether this palette is the fallback (no real colors extracted).
  bool get isFallback =>
      dominant == fallback.dominant &&
      accent == fallback.accent &&
      muted == fallback.muted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PosterColorPalette &&
          dominant == other.dominant &&
          accent == other.accent &&
          muted == other.muted;

  @override
  int get hashCode => Object.hash(dominant, accent, muted);
}

/// Service that extracts dominant colors from poster images and processes
/// them through a "cinema filter" for use as dark-mode backgrounds.
class PosterColorService {
  PosterColorService._();
  static final instance = PosterColorService._();

  /// In-memory cache: imageUrl → palette
  final Map<String, PosterColorPalette> _cache = {};

  /// Extract colors from a network image URL.
  /// Returns cached result if available.
  Future<PosterColorPalette> extractFromUrl(String imageUrl) async {
    if (imageUrl.isEmpty) return PosterColorPalette.fallback;

    // Check cache first
    final cached = _cache[imageUrl];
    if (cached != null) return cached;

    try {
      // Use a small image size for fast extraction
      final paletteGenerator = await PaletteGenerator.fromImageProvider(
        ResizeImage(
          NetworkImage(imageUrl),
          width: 100,
          policy: ResizeImagePolicy.fit,
        ),
        maximumColorCount: 16,
        timeout: const Duration(seconds: 5),
      );

      final palette = _processPalette(paletteGenerator);
      _cache[imageUrl] = palette;
      return palette;
    } catch (_) {
      // Cache fallback too to avoid retrying failed URLs
      _cache[imageUrl] = PosterColorPalette.fallback;
      return PosterColorPalette.fallback;
    }
  }

  /// Process raw palette into cinema-grade background colors.
  PosterColorPalette _processPalette(PaletteGenerator generator) {
    // Pick dominant color — prefer vibrant, then dominant, then darkMuted
    final Color rawDominant = generator.vibrantColor?.color ??
        generator.dominantColor?.color ??
        generator.darkVibrantColor?.color ??
        PosterColorPalette.fallback.dominant;

    // Pick accent — prefer lightVibrant, then mutedColor
    final Color rawAccent = generator.lightVibrantColor?.color ??
        generator.mutedColor?.color ??
        generator.darkMutedColor?.color ??
        PosterColorPalette.fallback.accent;

    // Pick muted — prefer darkMuted, then muted
    final Color rawMuted = generator.darkMutedColor?.color ??
        generator.mutedColor?.color ??
        PosterColorPalette.fallback.muted;

    return PosterColorPalette(
      dominant: _cinemaFilter(rawDominant, darkenAmount: 0.40),
      accent: _cinemaFilter(rawAccent, darkenAmount: 0.30),
      muted: _cinemaFilter(rawMuted, darkenAmount: 0.50),
    );
  }

  /// Cinema filter: reduces saturation and darkens the color so it works
  /// as a background behind white text without eye strain.
  Color _cinemaFilter(Color color, {double darkenAmount = 0.4}) {
    final hsl = HSLColor.fromColor(color);

    // Reduce saturation to 60-70% of original
    final desaturated = hsl.withSaturation((hsl.saturation * 0.65).clamp(0.0, 1.0));

    // Darken significantly for background use
    final darkened = desaturated.withLightness(
      (desaturated.lightness * (1.0 - darkenAmount)).clamp(0.05, 0.35),
    );

    return darkened.toColor();
  }

  /// Pre-warm the cache for a list of URLs (e.g., carousel items).
  Future<void> preWarm(List<String> urls) async {
    await Future.wait(
      urls.where((url) => url.isNotEmpty && !_cache.containsKey(url))
          .map((url) => extractFromUrl(url)),
    );
  }

  /// Clear the cache.
  void clearCache() => _cache.clear();
}
