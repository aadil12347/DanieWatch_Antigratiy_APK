/// Model classes for parsing posting_record.json from GitHub.
/// This file tracks which posts were recently added and their batch order,
/// used to prioritize display ordering across all Explore tabs.

class PostingRecord {
  final String lastUpdated;
  final int totalPosts;
  final int totalBatches;
  final List<PostingBatch> batches;

  const PostingRecord({
    required this.lastUpdated,
    required this.totalPosts,
    required this.totalBatches,
    required this.batches,
  });

  factory PostingRecord.fromJson(Map<String, dynamic> json) {
    return PostingRecord(
      lastUpdated: json['last_updated']?.toString() ?? '',
      totalPosts: (json['total_posts'] as num?)?.toInt() ?? 0,
      totalBatches: (json['total_batches'] as num?)?.toInt() ?? 0,
      batches: (json['batches'] as List<dynamic>?)
              ?.map((e) => PostingBatch.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Build a priority map: key = "tmdbId-type" → priority value.
  /// Lower priority = should appear first within the same year.
  /// Encoding: (sortedIndex * 100000) + positionInBatch
  ///
  /// Batches are sorted by batch_id DESC (highest first) so that the newest
  /// batch always gets the lowest priority values and appears on top.
  /// Within each batch, posts keep their original order.
  Map<String, int> buildPriorityMap() {
    final map = <String, int>{};

    // Sort batches: highest batch_id first (descending).
    // Batch 3 on top → Batch 2 → Batch 1 at the bottom.
    final sorted = List<PostingBatch>.from(batches);
    sorted.sort((a, b) {
      // Primary: batch_id descending (highest batch = newest content = top)
      final idCmp = b.batchId.compareTo(a.batchId);
      if (idCmp != 0) return idCmp;
      // Fallback: timestamp descending
      return b.timestamp.compareTo(a.timestamp);
    });

    for (int bIdx = 0; bIdx < sorted.length; bIdx++) {
      final batch = sorted[bIdx];
      for (int pIdx = 0; pIdx < batch.posts.length; pIdx++) {
        final post = batch.posts[pIdx];
        final key = '${post.tmdbId}-${post.type}';
        // Only store the first occurrence (latest batch wins)
        if (!map.containsKey(key)) {
          map[key] = (bIdx * 100000) + pIdx;
        }
      }
    }
    return map;
  }
}

class PostingBatch {
  final int batchId;
  final String dateKey;
  final String date;
  final String timestamp;
  final int totalInBatch;
  final List<PostingPost> posts;

  const PostingBatch({
    required this.batchId,
    required this.dateKey,
    required this.date,
    required this.timestamp,
    required this.totalInBatch,
    required this.posts,
  });

  factory PostingBatch.fromJson(Map<String, dynamic> json) {
    return PostingBatch(
      batchId: (json['batch_id'] as num?)?.toInt() ?? 0,
      dateKey: json['date_key']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      totalInBatch: (json['total_in_batch'] as num?)?.toInt() ?? 0,
      posts: (json['posts'] as List<dynamic>?)
              ?.map((e) => PostingPost.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class PostingPost {
  final String title;
  final int tmdbId;
  final String imdbId;
  final String type;
  final int year;

  const PostingPost({
    required this.title,
    required this.tmdbId,
    required this.imdbId,
    required this.type,
    required this.year,
  });

  factory PostingPost.fromJson(Map<String, dynamic> json) {
    return PostingPost(
      title: json['title']?.toString() ?? '',
      tmdbId: int.tryParse(json['tmdb_id']?.toString() ?? '') ?? 0,
      imdbId: json['imdb_id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'movie',
      year: int.tryParse(json['year']?.toString() ?? '') ?? 0,
    );
  }
}
