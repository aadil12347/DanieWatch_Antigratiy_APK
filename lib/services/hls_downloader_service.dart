import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:native_muxer/native_muxer.dart';
import '../core/utils/error_sanitizer.dart';

/// Robust HLS segment downloader with:
///  - 12 parallel workers for maximum throughput
///  - Per-segment retry with fast exponential backoff
///  - HTTP Range resume for partial segments
///  - connectivity_plus auto-pause/resume on network changes
///  - Separate video + audio stream support
///  - Native Android MediaMuxer for .mp4 with guaranteed A/V sync
class HlsDownloaderService {
  // â”€â”€ Configuration â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static const int _maxWorkers = 8;
  static const int _maxRetries = 3;
  static const List<int> _retryDelaysMs = [0, 500, 1500];

  late final Dio _dio;

  HlsDownloaderService() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 120),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*',
          'Accept-Encoding': 'identity',
        },
      ),
    );
    // Bypass expired/invalid SSL certificates from CDN servers
    // + connection pooling for maximum throughput
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        client.maxConnectionsPerHost = _maxWorkers * 2;
        client.idleTimeout = const Duration(seconds: 15);
        return client;
      },
    );
  }

  Function(double progress, int completedSegments, int totalSegments,
      int downloadedBytes, int bytesPerSecond)? onProgress;
  Function(String error)? onError;
  Function(String mp4Path)? onComplete;
  VoidCallback? onConversionStarted;
  /// Fired when CDN links are expired (403/404) and playlist refresh failed.
  /// Distinct from onError â€” signals that re-extraction from embed URL is needed.
  Function(String error)? onLinkExpired;

  // â”€â”€ State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  bool _isCancelled = false;
  bool _isPaused = false;
  bool _isNetworkPaused = false;
  bool _completedSuccessfully = false;
  int _completedSegments = 0;
  int _totalSegments = 0;
  int _downloadedBytes = 0;

  // â”€â”€ CDN Refresh State â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  int _playlistRefreshCount = 0;
  static const int _maxPlaylistRefreshes = 2;
  String? _videoPlaylistUrl;
  String? _audioPlaylistUrl;
  String? _subtitlePlaylistUrl;
  String? _saveDirectory;

  // â”€â”€ Speed tracking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  int _bytesPerSecond = 0;
  int _lastSpeedBytes = 0;
  int _lastSpeedTime = 0;
  int _lastProgressTime = 0;

  StreamSubscription? _connectivitySub;

  void cancel() {
    _isCancelled = true;
    _connectivitySub?.cancel();
  }

  void pause() => _isPaused = true;

  void resume() {
    _isPaused = false;
    _isNetworkPaused = false;
  }

  bool get isPaused => _isPaused || _isNetworkPaused;
  bool get isCancelled => _isCancelled;

  // â”€â”€ Connectivity Monitor â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _startConnectivityMonitor() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);

      if (!hasConnection && !_isNetworkPaused) {
        debugPrint('âš¡ Network lost â€” auto-pausing download');
        _isNetworkPaused = true;
      } else if (hasConnection && _isNetworkPaused) {
        debugPrint('âš¡ Network restored â€” auto-resuming in 2s');
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!_isCancelled) {
            _isNetworkPaused = false;
          }
        });
      }
    });
  }

  // â”€â”€ URL Resolution â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _resolveUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    final base = Uri.parse(baseUrl);
    if (relativeUrl.startsWith('/')) {
      return '${base.scheme}://${base.host}$relativeUrl';
    }
    return base.resolve(relativeUrl).toString();
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  //  MAIN ENTRY POINT
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Download HLS segments and convert to MP4.
  ///
  /// [videoM3u8Url] â€” video variant playlist URL
  /// [audioM3u8Url] â€” optional separate audio playlist URL (null if audio is muxed in video)
  /// [saveDirectory] â€” temp directory for .ts segments
  /// [outputMp4Path] â€” final .mp4 output path
  Future<void> startDownload({
    required String videoM3u8Url,
    String? audioM3u8Url,
    String? subtitleM3u8Url,
    required String saveDirectory,
    required String outputMp4Path,
  }) async {
    _isCancelled = false;
    _isPaused = false;
    _isNetworkPaused = false;
    _completedSuccessfully = false;
    _completedSegments = 0;
    _totalSegments = 0;
    _downloadedBytes = 0;
    _playlistRefreshCount = 0;
    _videoPlaylistUrl = videoM3u8Url;
    _audioPlaylistUrl = audioM3u8Url;
    _subtitlePlaylistUrl = subtitleM3u8Url;
    _saveDirectory = saveDirectory;

    _startConnectivityMonitor();

    try {
      final dir = Directory(saveDirectory);
      if (!await dir.exists()) await dir.create(recursive: true);

      // â”€â”€ Phase 1: Parse playlists & build segment queues â”€â”€
      debugPrint('ðŸ“¦ Parsing video playlist: $videoM3u8Url');
      final videoSegments =
          await _parseMediaPlaylist(videoM3u8Url, saveDirectory, 'v');

      List<_SegmentTask> audioSegments = [];
      if (audioM3u8Url != null && audioM3u8Url.isNotEmpty) {
        debugPrint('ðŸ“¦ Parsing audio playlist: $audioM3u8Url');
        audioSegments =
            await _parseMediaPlaylist(audioM3u8Url, saveDirectory, 'a');
      }

      List<_SegmentTask> subtitleSegments = [];
      if (subtitleM3u8Url != null && subtitleM3u8Url.isNotEmpty) {
        debugPrint('ðŸ“¦ Parsing subtitle playlist: $subtitleM3u8Url');
        subtitleSegments =
            await _parseMediaPlaylist(subtitleM3u8Url, saveDirectory, 's');
      }

      final allSegments = [
        ...videoSegments,
        ...audioSegments,
        ...subtitleSegments
      ];
      _totalSegments = allSegments.length;

      if (_totalSegments == 0) {
        throw Exception('No segments found to download.');
      }

      debugPrint(
          'ðŸ“¦ HLS: ${videoSegments.length} video + ${audioSegments.length} audio + ${subtitleSegments.length} sub = $_totalSegments total segments');

      // â”€â”€ Phase 2: Download all segments (3 parallel) â”€â”€â”€â”€
      await _downloadAllSegments(allSegments);

      if (_isCancelled) throw Exception('Download cancelled');

      // â”€â”€ Phase 3: Mux to .mp4 with FFmpeg â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      onConversionStarted?.call();
      debugPrint('ðŸ”§ Converting to MP4...');
      await _muxToMp4(
          videoSegments, audioSegments, subtitleSegments, saveDirectory, outputMp4Path);

      if (_isCancelled) throw Exception('Download cancelled');

      onComplete?.call(outputMp4Path);
      _completedSuccessfully = true;
    } catch (e, stack) {
      _connectivitySub?.cancel();
      if (!_isCancelled) {
        debugPrint('âŒ Download error: $e');
        debugPrint('StackTrace: $stack');

        // Check if this was a CDN expiry error (403/404 during playlist fetch)
        // This catches expired URLs during Phase 1 (playlist parsing) which
        // would otherwise fire onError instead of onLinkExpired
        if (e is DioException &&
            (e.response?.statusCode == 403 || e.response?.statusCode == 404)) {
          debugPrint('ðŸ”— Playlist URL expired (HTTP ${e.response?.statusCode}) â€” signaling re-extraction');
          _isCancelled = true; // Prevent segment cleanup
          onLinkExpired?.call('Playlist URL expired (HTTP ${e.response?.statusCode})');
          return;
        }

        onError?.call(ErrorSanitizer.sanitize(e));
      }
    } finally {
      // CRITICAL: Only delete segments after SUCCESSFUL completion.
      // Never delete on error or cancellation â€” segments are needed for resume.
      if (_completedSuccessfully) {
        try {
          final segDir = Directory(saveDirectory);
          if (await segDir.exists()) {
            await segDir.delete(recursive: true);
          }
        } catch (e) {
          debugPrint('âš  Cleanup warning: $e');
        }
      }
      _connectivitySub?.cancel();
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  //  PHASE 1: Parse media playlist â†’ segment list
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /// Parse a media playlist (NOT master) and return segment tasks.
  /// [prefix] is 'v' for video, 'a' for audio â€” to keep file names distinct.
  Future<List<_SegmentTask>> _parseMediaPlaylist(
    String playlistUrl,
    String saveDir,
    String prefix,
  ) async {
    String content = await _fetchContent(playlistUrl);
    final lines = content.split('\n');
    final segments = <_SegmentTask>[];

    // If this is somehow a master playlist, find the first variant and use it
    if (content.contains('#EXT-X-STREAM-INF')) {
      debugPrint(
          'âš  Got master playlist instead of media â€” extracting first variant');
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          if (i + 1 < lines.length && !lines[i + 1].trim().startsWith('#')) {
            final variantUrl = _resolveUrl(playlistUrl, lines[i + 1].trim());
            return _parseMediaPlaylist(variantUrl, saveDir, prefix);
          }
        }
      }
    }

    int segIndex = 0;
    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Handle encryption keys
      if (line.startsWith('#EXT-X-KEY:')) {
        final keyMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (keyMatch != null) {
          String keyUrl = _resolveUrl(playlistUrl, keyMatch.group(1)!);
          segments.add(_SegmentTask(
            url: keyUrl,
            localPath: p.join(saveDir, '${prefix}_key_$segIndex.bin'),
          ));
        }
        continue;
      }

      // Handle EXT-X-MAP (initialization segment for fMP4)
      if (line.startsWith('#EXT-X-MAP:')) {
        final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (uriMatch != null) {
          String mapUrl = _resolveUrl(playlistUrl, uriMatch.group(1)!);
          segments.add(_SegmentTask(
            url: mapUrl,
            localPath: p.join(saveDir, '${prefix}_init_$segIndex.mp4'),
            isInitSegment: true,
          ));
        }
        continue;
      }

      // Skip all other tags
      if (line.startsWith('#')) continue;

      // This is a segment URL
      String segmentUrl = _resolveUrl(playlistUrl, line);
      String ext = _extractSegmentExt(segmentUrl);
      segments.add(_SegmentTask(
        url: segmentUrl,
        localPath: p.join(saveDir,
            '${prefix}_seg_${segIndex.toString().padLeft(5, '0')}.$ext'),
        isTsSegment: true,
      ));
      segIndex++;
    }

    return segments;
  }

  String _extractSegmentExt(String url) {
    String cleanUrl = url.contains('?') ? url.split('?').first : url;
    String ext = cleanUrl.split('.').last;
    if (ext.length > 4) ext = 'ts';
    return ext;
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  //  PHASE 2: Download all segments with 3 parallel workers
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  Future<void> _downloadAllSegments(List<_SegmentTask> segments) async {
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        while (isPaused && !_isCancelled) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        if (_isCancelled) return;

        final myIndex = nextIndex;
        if (myIndex >= segments.length) return;
        nextIndex++;

        final seg = segments[myIndex];

        // Skip already-completed segments (for resume)
        final file = File(seg.localPath);
        if (await file.exists() && await file.length() > 0) {
          _completedSegments++;
          _downloadedBytes += await file.length();
          _reportProgress();
          continue;
        }

        await _downloadSegmentWithRetry(seg);
      }
    }

    final workers = <Future<void>>[];
    for (int i = 0; i < _maxWorkers; i++) {
      workers.add(worker());
    }
    await Future.wait(workers);
  }

  Future<void> _downloadSegmentWithRetry(_SegmentTask seg) async {
    for (int attempt = 0; attempt < _maxRetries; attempt++) {
      if (_isCancelled) return;

      if (attempt > 0) {
        final delayMs =
            _retryDelaysMs[attempt.clamp(0, _retryDelaysMs.length - 1)];
        debugPrint(
            'ðŸ”„ Retry ${attempt + 1}/$_maxRetries for ${p.basename(seg.localPath)} after ${delayMs}ms');
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      while (isPaused && !_isCancelled) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_isCancelled) return;

      try {
        await _downloadFileWithResume(seg.url, seg.localPath);
        _completedSegments++;
        _reportProgress();
        return;
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        debugPrint(
            'âš  ${p.basename(seg.localPath)} attempt ${attempt + 1} failed (HTTP $statusCode): $e');

        // CDN token expired â€” try refreshing the playlist
        if ((statusCode == 404 || statusCode == 403) &&
            _playlistRefreshCount < _maxPlaylistRefreshes &&
            attempt < _maxRetries - 1) {
          final newUrl = await _refreshSegmentUrl(seg);
          if (newUrl != null) {
            seg = _SegmentTask(
              url: newUrl,
              localPath: seg.localPath,
              isTsSegment: seg.isTsSegment,
            );
            // Don't count this as a retry â€” continue loop with fresh URL
            continue;
          }
        }

        if (attempt == _maxRetries - 1) {
          // If it was a 403/404 and all refreshes exhausted, signal link expired
          if ((statusCode == 403 || statusCode == 404) &&
              _playlistRefreshCount >= _maxPlaylistRefreshes) {
            _isCancelled = true;
            onLinkExpired?.call(
                'CDN link expired (HTTP $statusCode) â€” re-extraction needed');
            return;
          }
          throw Exception(
              'Download failed after $_maxRetries attempts');
        }
      } catch (e) {
        debugPrint(
            'âš  ${p.basename(seg.localPath)} attempt ${attempt + 1} failed: $e');
        if (attempt == _maxRetries - 1) {
          throw Exception(
              'Download failed after $_maxRetries attempts');
        }
      }
    }
  }

  /// Re-fetch the M3U8 playlist to get fresh CDN URLs when a 404/403 occurs.
  /// Returns a new URL for the failed segment, or null if refresh failed.
  Future<String?> _refreshSegmentUrl(_SegmentTask failedSeg) async {
    _playlistRefreshCount++;
    debugPrint(
        'ðŸ”„ Refreshing playlist (attempt $_playlistRefreshCount/$_maxPlaylistRefreshes) for expired CDN URL');

    try {
      // Determine which playlist this segment belongs to based on prefix
      final baseName = p.basename(failedSeg.localPath);
      String? playlistUrl;
      String prefix;

      if (baseName.startsWith('a_')) {
        playlistUrl = _audioPlaylistUrl;
        prefix = 'a';
      } else if (baseName.startsWith('s_')) {
        playlistUrl = _subtitlePlaylistUrl;
        prefix = 's';
      } else {
        playlistUrl = _videoPlaylistUrl;
        prefix = 'v';
      }

      if (playlistUrl == null || _saveDirectory == null) return null;

      final freshSegments =
          await _parseMediaPlaylist(playlistUrl, _saveDirectory!, prefix);

      // Find the matching segment by index (local path pattern)
      // Extract segment index from the local path
      final indexMatch = RegExp(r'_seg_(\d+)\.').firstMatch(baseName);
      if (indexMatch != null) {
        final segIndex = int.parse(indexMatch.group(1)!);
        // Find the segment in the fresh list with matching index
        final tsSegments =
            freshSegments.where((s) => s.isTsSegment).toList();
        if (segIndex < tsSegments.length) {
          final freshUrl = tsSegments[segIndex].url;
          debugPrint('âœ… Got fresh CDN URL for segment $segIndex');
          return freshUrl;
        }
      }

      debugPrint('âš  Could not match segment index in refreshed playlist');
      return null;
    } catch (e) {
      debugPrint('âŒ Playlist refresh failed: $e');
      return null;
    }
  }

  Future<void> _downloadFileWithResume(String url, String savePath) async {
    final file = File(savePath);
    int existingBytes = 0;

    if (await file.exists()) {
      existingBytes = await file.length();
    }

    if (existingBytes > 0) {
      // â”€â”€ RESUME PATH: Use streaming to append from byte offset â”€â”€
      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Range': 'bytes=$existingBytes-'},
        ),
      );

      final sink = file.openWrite(mode: FileMode.append);
      try {
        await for (final chunk in response.data!.stream) {
          if (_isCancelled) break;
          sink.add(chunk);
          _downloadedBytes += chunk.length;
        }
      } finally {
        await sink.close();
      }
    } else {
      // â”€â”€ FAST PATH: Bulk download entire segment in native code â”€â”€
      // ResponseType.bytes downloads in native I/O without per-chunk
      // Dart event loop overhead, then writes in a single syscall.
      // This is dramatically faster than streaming for parallel workers.
      final response = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );

      if (_isCancelled) return;

      final bytes = response.data!;
      await file.writeAsBytes(bytes, flush: false);
      _downloadedBytes += bytes.length;
    }

    // Report progress once per segment completion
    _reportProgress();
  }

  void _reportProgress() {
    if (_totalSegments > 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      // Debounce: max 2 progress updates per second to reduce IPC overhead
      if (now - _lastProgressTime < 500) return;
      _lastProgressTime = now;

      final progress = _completedSegments / _totalSegments;
      _updateSpeed();
      onProgress?.call(progress, _completedSegments, _totalSegments,
          _downloadedBytes, _bytesPerSecond);
    }
  }

  void _updateSpeed() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastSpeedTime == 0) {
      _lastSpeedTime = now;
      _lastSpeedBytes = _downloadedBytes;
      return;
    }
    final elapsed = now - _lastSpeedTime;
    if (elapsed >= 1000) {
      final bytesDelta = _downloadedBytes - _lastSpeedBytes;
      final instantSpeed = (bytesDelta * 1000 ~/ elapsed);
      // EMA smoothing: 30% new + 70% old â€” dampens spikes for stable display
      _bytesPerSecond = _bytesPerSecond == 0
          ? instantSpeed
          : (0.3 * instantSpeed + 0.7 * _bytesPerSecond).toInt();
      _lastSpeedTime = now;
      _lastSpeedBytes = _downloadedBytes;
    }
  }

  // ═══════════════════════════════════════════════════════
  //  PHASE 3: Mux video + audio → single .mp4
  //
  //  Uses Android's native MediaExtractor + MediaMuxer APIs:
  //  - Guaranteed A/V sync (native PTS/DTS handling)
  //  - Stream-copy only (no re-encoding, ~5-10x faster)
  //  - Zero APK overhead (built into Android)
  // ═══════════════════════════════════════════════════════
  Future<void> _muxToMp4(
    List<_SegmentTask> videoSegments,
    List<_SegmentTask> audioSegments,
    List<_SegmentTask> subtitleSegments,
    String saveDir,
    String outputMp4Path,
  ) async {
    final dir = Directory(saveDir);
    if (!await dir.exists()) throw Exception('Segment directory not found');

    debugPrint('🔧 Native MediaMuxer: muxing segments from $saveDir');

    try {
      final result = await NativeMuxer.muxToMp4(
        segmentDir: saveDir,
        outputPath: outputMp4Path,
      );

      final sz = await File(result).length();
      debugPrint('✅ MP4 created (native): ${(sz / (1024 * 1024)).toStringAsFixed(1)} MB');
    } catch (e) {
      debugPrint('❌ Native muxer failed: $e');
      throw Exception('MP4 conversion failed: $e');
    }
  }


  // -- Helpers ------------------------------------------------
  Future<String> _fetchContent(String url) async {
    try {
      final response = await _dio.get(url);
      return response.data.toString();
    } catch (e) {
      debugPrint('Failed to fetch: $url -> $e');
      rethrow;
    }
  }

}

/// Internal model for a segment download task.
class _SegmentTask {
  final String url;
  final String localPath;
  final bool isTsSegment;
  final bool isInitSegment;

  _SegmentTask({
    required this.url,
    required this.localPath,
    this.isTsSegment = false,
    this.isInitSegment = false,
  });
}
