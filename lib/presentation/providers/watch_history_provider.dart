import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single watch-history entry persisted to SharedPreferences.
class WatchHistoryItem {
  final int tmdbId;
  final String mediaType;
  final String title;
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final double currentTime; // seconds
  final double duration; // seconds
  final String? posterUrl;
  final String? thumbnailUrl;
  final String? playUrl;
  final int timestamp; // millisecondsSinceEpoch

  WatchHistoryItem({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.season,
    this.episode,
    this.episodeTitle,
    required this.currentTime,
    required this.duration,
    this.posterUrl,
    this.thumbnailUrl,
    this.playUrl,
    required this.timestamp,
  });

  /// Unique key for deduplication: same show + season + episode = same entry
  String get uniqueKey => '${tmdbId}_${season ?? 0}_${episode ?? 0}';

  /// Progress as a 0.0–1.0 fraction
  double get progress =>
      duration > 0 ? (currentTime / duration).clamp(0.0, 1.0) : 0.0;

  /// Human-readable time remaining, e.g. "23 min left" or "5:30 left"
  String get timeRemainingText {
    final remaining = (duration - currentTime).clamp(0, double.infinity);
    final minutes = (remaining / 60).floor();
    final seconds = (remaining % 60).floor();
    if (minutes >= 60) {
      final hours = (minutes / 60).floor();
      final mins = minutes % 60;
      return '${hours}h ${mins}m left';
    }
    if (minutes > 0) return '${minutes}m ${seconds}s left';
    return '${seconds}s left';
  }

  /// Display subtitle: "S01 E03" or movie title
  String get displaySubtitle {
    if (mediaType != 'movie' && season != null && episode != null) {
      final epTitle = episodeTitle ?? 'Episode $episode';
      return 'S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}: $epTitle';
    }
    return title;
  }

  /// Whether this item is basically finished (>95% watched)
  bool get isFinished => progress > 0.95;

  Map<String, dynamic> toJson() => {
        'tmdbId': tmdbId,
        'mediaType': mediaType,
        'title': title,
        'season': season,
        'episode': episode,
        'episodeTitle': episodeTitle,
        'currentTime': currentTime,
        'duration': duration,
        'posterUrl': posterUrl,
        'thumbnailUrl': thumbnailUrl,
        'playUrl': playUrl,
        'timestamp': timestamp,
      };

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) {
    return WatchHistoryItem(
      tmdbId: json['tmdbId'] as int? ?? 0,
      mediaType: json['mediaType'] as String? ?? 'movie',
      title: json['title'] as String? ?? '',
      season: json['season'] as int?,
      episode: json['episode'] as int?,
      episodeTitle: json['episodeTitle'] as String?,
      currentTime: (json['currentTime'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      posterUrl: json['posterUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      playUrl: json['playUrl'] as String?,
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }
}

// ─── Provider ────────────────────────────────────────────────────────────────

class WatchHistoryNotifier extends StateNotifier<List<WatchHistoryItem>> {
  static const _storageKey = 'daniewatch_watch_history';
  static const _maxItems = 10;

  WatchHistoryNotifier() : super([]) {
    _loadFromStorage();
  }

  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        state = decoded
            .map((e) => WatchHistoryItem.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
    } catch (_) {
      // Corrupted data — start fresh
      state = [];
    }
  }

  Future<void> _persistToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(state.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, json);
  }

  /// Save or update watch progress for a video.
  /// Deduplicates by tmdbId + season + episode. Keeps most recent 10.
  Future<void> saveProgress(WatchHistoryItem item) async {
    // Don't save very short watches (< 10 seconds)
    if (item.currentTime < 10) return;

    final key = item.uniqueKey;
    final updated = <WatchHistoryItem>[item];
    for (final existing in state) {
      if (existing.uniqueKey != key) {
        updated.add(existing);
      }
    }
    // Sort by most recent first, cap at max items
    updated.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    state = updated.take(_maxItems).toList();
    await _persistToStorage();
  }

  /// Remove a specific item from watch history (e.g. when finished)
  Future<void> removeItem(int tmdbId, {int? season, int? episode}) async {
    final key = '${tmdbId}_${season ?? 0}_${episode ?? 0}';
    state = state.where((e) => e.uniqueKey != key).toList();
    await _persistToStorage();
  }

  /// Clear all watch history
  Future<void> clearAll() async {
    state = [];
    await _persistToStorage();
  }
}

final watchHistoryProvider =
    StateNotifierProvider<WatchHistoryNotifier, List<WatchHistoryItem>>(
  (ref) => WatchHistoryNotifier(),
);
