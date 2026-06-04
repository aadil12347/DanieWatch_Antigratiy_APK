import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/poster_color_service.dart';

/// Async provider that extracts and caches poster colors for a given image URL.
/// Usage: ref.watch(posterColorProvider('https://image.tmdb.org/...'))
final posterColorProvider =
    FutureProvider.family<PosterColorPalette, String>((ref, imageUrl) async {
  return PosterColorService.instance.extractFromUrl(imageUrl);
});

/// Holds the currently active gradient palette for the home hero carousel.
/// Updated when the carousel's active index changes.
final activeGradientProvider = StateProvider<PosterColorPalette>((ref) {
  return PosterColorPalette.fallback;
});

/// Holds the gradient palette for the poster the user is currently touching.
/// Reset to null when the user lifts their finger.
final touchedPosterGradientProvider = StateProvider<PosterColorPalette?>((ref) {
  return null;
});
