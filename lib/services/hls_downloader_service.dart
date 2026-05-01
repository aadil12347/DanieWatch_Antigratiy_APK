import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import '../core/utils/error_sanitizer.dart';

/// Robust HLS segment downloader with:
///  - 3 parallel workers
///  - Per-segment retry with exponential backoff
///  - HTTP Range resume for partial segments
///  - connectivity_plus auto-pause/resume on network changes
///  - Separate video + audio stream support
///  - FFmpeg mux to .mp4 at the end + cleanup
class HlsDownloaderService {
  // ── Configuration ──────────────────────────────────────
  static const int _maxWorkers = 5;
  static const int _maxRetries = 3;
  static const List<int> _retryDelaysMs = [0, 2000, 5000];

  late final Dio _dio;

  HlsDownloaderService() {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept': '*/*',
        },
      ),
    );
    // Bypass expired/invalid SSL certificates from CDN servers
    _dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        return client;
      },
    );
  }

  // ── Callbacks ──────────────────────────────────────────
  Function(double progress, int completedSegments, int totalSegments,
      int downloadedBytes, int bytesPerSecond)? onProgress;
  Function(String error)? onError;
  Function(String mp4Path)? onComplete;
  VoidCallback? onConversionStarted;

  // ── State ──────────────────────────────────────────────
  bool _isCancelled = false;
  bool _isPaused = false;
  bool _isNetworkPaused = false;
  int _completedSegments = 0;
  int _totalSegments = 0;
  int _downloadedBytes = 0;

  // ── CDN Refresh State ──────────────────────────────────
  int _playlistRefreshCount = 0;
  static const int _maxPlaylistRefreshes = 2;
  String? _videoPlaylistUrl;
  String? _audioPlaylistUrl;
  String? _subtitlePlaylistUrl;
  String? _saveDirectory;

  // ── Speed tracking ─────────────────────────────────────
  int _bytesPerSecond = 0;
  int _lastSpeedBytes = 0;
  int _lastSpeedTime = 0;

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

  // ── Connectivity Monitor ───────────────────────────────
  void _startConnectivityMonitor() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);

      if (!hasConnection && !_isNetworkPaused) {
        debugPrint('⚡ Network lost — auto-pausing download');
        _isNetworkPaused = true;
      } else if (hasConnection && _isNetworkPaused) {
        debugPrint('⚡ Network restored — auto-resuming in 2s');
        Future.delayed(const Duration(seconds: 2), () {
          if (!_isCancelled) {
            _isNetworkPaused = false;
          }
        });
      }
    });
  }

  // ── URL Resolution ─────────────────────────────────────
  String _resolveUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    final base = Uri.parse(baseUrl);
    if (relativeUrl.startsWith('/')) {
      return '${base.scheme}://${base.host}$relativeUrl';
    }
    return base.resolve(relativeUrl).toString();
  }

  // ══════════════════════════════════════════════════════════
  //  MAIN ENTRY POINT
  // ══════════════════════════════════════════════════════════

  /// Download HLS segments and convert to MP4.
  ///
  /// [videoM3u8Url] — video variant playlist URL
  /// [audioM3u8Url] — optional separate audio playlist URL (null if audio is muxed in video)
  /// [saveDirectory] — temp directory for .ts segments
  /// [outputMp4Path] — final .mp4 output path
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

      // ── Phase 1: Parse playlists & build segment queues ──
      debugPrint('📦 Parsing video playlist: $videoM3u8Url');
      final videoSegments =
          await _parseMediaPlaylist(videoM3u8Url, saveDirectory, 'v');

      List<_SegmentTask> audioSegments = [];
      if (audioM3u8Url != null && audioM3u8Url.isNotEmpty) {
        debugPrint('📦 Parsing audio playlist: $audioM3u8Url');
        audioSegments =
            await _parseMediaPlaylist(audioM3u8Url, saveDirectory, 'a');
      }

      List<_SegmentTask> subtitleSegments = [];
      if (subtitleM3u8Url != null && subtitleM3u8Url.isNotEmpty) {
        debugPrint('📦 Parsing subtitle playlist: $subtitleM3u8Url');
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
          '📦 HLS: ${videoSegments.length} video + ${audioSegments.length} audio + ${subtitleSegments.length} sub = $_totalSegments total segments');

      // ── Phase 2: Download all segments (3 parallel) ────
      await _downloadAllSegments(allSegments);

      if (_isCancelled) throw Exception('Download cancelled');

      // ── Phase 3: Mux to .mp4 with FFmpeg ──────────────
      onConversionStarted?.call();
      debugPrint('🔧 Converting to MP4...');
      await _muxToMp4(
          videoSegments, audioSegments, subtitleSegments, saveDirectory, outputMp4Path);

      if (_isCancelled) throw Exception('Download cancelled');

      onComplete?.call(outputMp4Path);
    } catch (e, stack) {
      _connectivitySub?.cancel();
      if (!_isCancelled) {
        debugPrint('❌ Download error: $e');
        debugPrint('StackTrace: $stack');
        onError?.call(ErrorSanitizer.sanitize(e));
      }
    } finally {
      // Always try to cleanup segments if we are NOT in a state that allows resume
      // For now, let's just ensure cleanup on completion or fatal error
      if (!_isCancelled) {
         try {
          final segDir = Directory(saveDirectory);
          if (await segDir.exists()) {
            await segDir.delete(recursive: true);
          }
        } catch (e) {
          debugPrint('⚠ Cleanup warning: $e');
        }
      }
      _connectivitySub?.cancel();
    }
  }

  // ══════════════════════════════════════════════════════════
  //  PHASE 1: Parse media playlist → segment list
  // ══════════════════════════════════════════════════════════

  /// Parse a media playlist (NOT master) and return segment tasks.
  /// [prefix] is 'v' for video, 'a' for audio — to keep file names distinct.
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
          '⚠ Got master playlist instead of media — extracting first variant');
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

  // ══════════════════════════════════════════════════════════
  //  PHASE 2: Download all segments with 3 parallel workers
  // ══════════════════════════════════════════════════════════
  Future<void> _downloadAllSegments(List<_SegmentTask> segments) async {
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        while (isPaused && !_isCancelled) {
          await Future.delayed(const Duration(milliseconds: 300));
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
            '🔄 Retry ${attempt + 1}/$_maxRetries for ${p.basename(seg.localPath)} after ${delayMs}ms');
        await Future.delayed(Duration(milliseconds: delayMs));
      }

      while (isPaused && !_isCancelled) {
        await Future.delayed(const Duration(milliseconds: 300));
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
            '⚠ ${p.basename(seg.localPath)} attempt ${attempt + 1} failed (HTTP $statusCode): $e');

        // CDN token expired — try refreshing the playlist
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
            // Don't count this as a retry — continue loop with fresh URL
            continue;
          }
        }

        if (attempt == _maxRetries - 1) {
          throw Exception(
              'Download failed after $_maxRetries attempts');
        }
      } catch (e) {
        debugPrint(
            '⚠ ${p.basename(seg.localPath)} attempt ${attempt + 1} failed: $e');
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
        '🔄 Refreshing playlist (attempt $_playlistRefreshCount/$_maxPlaylistRefreshes) for expired CDN URL');

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
          debugPrint('✅ Got fresh CDN URL for segment $segIndex');
          return freshUrl;
        }
      }

      debugPrint('⚠ Could not match segment index in refreshed playlist');
      return null;
    } catch (e) {
      debugPrint('❌ Playlist refresh failed: $e');
      return null;
    }
  }

  Future<void> _downloadFileWithResume(String url, String savePath) async {
    final file = File(savePath);
    int existingBytes = 0;

    if (await file.exists()) {
      existingBytes = await file.length();
    }

    final response = await _dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        headers: existingBytes > 0 ? {'Range': 'bytes=$existingBytes-'} : null,
      ),
    );

    final fileMode = existingBytes > 0 ? FileMode.append : FileMode.write;
    final raf = file.openSync(mode: fileMode);

    try {
      await for (final chunk in response.data!.stream) {
        if (_isCancelled) {
          raf.closeSync();
          return;
        }
        raf.writeFromSync(chunk);
        _downloadedBytes += chunk.length;
      }
    } finally {
      raf.closeSync();
    }
  }

  void _reportProgress() {
    if (_totalSegments > 0) {
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
      _bytesPerSecond = (bytesDelta * 1000 ~/ elapsed);
      _lastSpeedTime = now;
      _lastSpeedBytes = _downloadedBytes;
    }
  }

  // ══════════════════════════════════════════════════════════
  //  PHASE 3: Mux video + audio → single .mp4
  //
  //  Strategy: BINARY CONCATENATION + FFmpeg REMUX
  //
  //  Why this works (and why the old concat demuxer didn't):
  //  - Online HLS players read segment bytes SEQUENTIALLY,
  //    producing a single continuous byte stream. The PTS
  //    timestamps inside each MPEG-TS packet are already
  //    perfectly sequential — the player just feeds bytes.
  //  - FFmpeg's concat demuxer (-f concat) opens each file
  //    INDIVIDUALLY and recalculates timestamps, introducing
  //    drift between video and audio streams.
  //  - Binary concatenation (raw byte append) reproduces
  //    EXACTLY what the online player does. The combined
  //    file has identical timestamps to the live stream.
  //  - FFmpeg is only used for the final remux (container
  //    conversion to MP4), which is a trivial copy operation.
  // ══════════════════════════════════════════════════════════
  Future<void> _muxToMp4(
    List<_SegmentTask> videoSegments,
    List<_SegmentTask> audioSegments,
    List<_SegmentTask> subtitleSegments,
    String saveDir,
    String outputMp4Path,
  ) async {
    final videoMedia = videoSegments.where((s) => s.isTsSegment).toList();
    if (videoMedia.isEmpty) throw Exception('No video segments to convert');

    final videoInits = videoSegments.where((s) => s.isInitSegment).toList();
    final audioMedia = audioSegments.where((s) => s.isTsSegment).toList();
    final audioInits = audioSegments.where((s) => s.isInitSegment).toList();
    final subMedia = subtitleSegments.where((s) => s.isTsSegment).toList();
    final subInits = subtitleSegments.where((s) => s.isInitSegment).toList();
    final hasSeparateAudio = audioMedia.isNotEmpty;

    // ── Helper: Binary-concat segments into a single file ──
    // This is the exact same thing an HLS player does internally:
    // read segment bytes one after another into a continuous stream.
    Future<String> binaryConcat(
      List<_SegmentTask> initSegs,
      List<_SegmentTask> mediaSegs,
      String name,
    ) async {
      final outPath = p.join(saveDir, '${name}_combined.ts');
      final sink = File(outPath).openWrite();

      // Prepend init segment(s) for fMP4 streams
      for (final seg in initSegs) {
        final f = File(seg.localPath);
        if (await f.exists()) {
          sink.add(await f.readAsBytes());
        }
      }

      // Append all media segments in order
      for (final seg in mediaSegs) {
        final f = File(seg.localPath);
        if (await f.exists()) {
          sink.add(await f.readAsBytes());
        }
      }

      await sink.flush();
      await sink.close();

      final size = await File(outPath).length();
      debugPrint('📦 Binary concat $name: ${mediaSegs.length} segments → ${(size / (1024 * 1024)).toStringAsFixed(1)} MB');
      return outPath;
    }

    // ── Step 1: Binary-concat all streams ──────────────────
    final videoCombined = await binaryConcat(videoInits, videoMedia, 'video');

    String? audioCombined;
    if (hasSeparateAudio) {
      audioCombined = await binaryConcat(audioInits, audioMedia, 'audio');
    }

    String? subCombined;
    if (subMedia.isNotEmpty) {
      subCombined = await binaryConcat(subInits, subMedia, 'sub');
    }

    // ── Step 2: FFmpeg remux (simple container conversion) ─
    final List<String> inputs = ['-i "$videoCombined"'];
    final List<String> maps = ['-map 0:v'];
    int inputIdx = 1;

    if (hasSeparateAudio) {
      inputs.add('-i "$audioCombined"');
      maps.add('-map $inputIdx:a');
      inputIdx++;
    } else {
      maps.add('-map 0:a?');
    }

    if (subCombined != null) {
      inputs.add('-i "$subCombined"');
      maps.add('-map $inputIdx:s');
      inputIdx++;
    }

    final codecArgs = subCombined != null ? '-c:s mov_text' : '';

    // ── Attempt 1: Stream-copy remux ──────────────────────
    final copyCommand =
        '-fflags +genpts+igndts '
        '${inputs.join(' ')} ${maps.join(' ')} '
        '-c:v copy -c:a copy $codecArgs '
        '-avoid_negative_ts make_zero '
        '-movflags +faststart '
        '-shortest -y "$outputMp4Path"';

    debugPrint('▶ FFmpeg (binary-concat remux): $copyCommand');
    final copySession = await FFmpegKit.execute(copyCommand);
    final copyRc = await copySession.getReturnCode();

    if (ReturnCode.isSuccess(copyRc)) {
      final outFile = File(outputMp4Path);
      final outSize = await outFile.exists() ? await outFile.length() : 0;
      if (outSize > 1024 * 100) {
        debugPrint('✅ MP4 created (copy): $outputMp4Path (${(outSize / (1024 * 1024)).toStringAsFixed(1)} MB)');
        _cleanupIntermediateFiles([videoCombined, audioCombined, subCombined]);
        return;
      }
      debugPrint('⚠ Output too small ($outSize bytes) — trying audio re-encode');
    } else {
      final logs = await copySession.getAllLogsAsString();
      debugPrint('⚠ Copy remux failed — trying audio re-encode. Logs: $logs');
    }

    // ── Attempt 2: Re-encode audio as fallback ────────────
    final reencodeCommand =
        '-fflags +genpts+igndts '
        '${inputs.join(' ')} ${maps.join(' ')} '
        '-c:v copy -c:a aac -b:a 192k '
        '-af "aresample=async=1:first_pts=0" '
        '$codecArgs '
        '-avoid_negative_ts make_zero '
        '-movflags +faststart '
        '-shortest -y "$outputMp4Path"';

    debugPrint('▶ FFmpeg (audio re-encode fallback): $reencodeCommand');
    final reencodeSession = await FFmpegKit.execute(reencodeCommand);
    final reencodeRc = await reencodeSession.getReturnCode();
    if (!ReturnCode.isSuccess(reencodeRc)) {
      final logs = await reencodeSession.getAllLogsAsString();
      debugPrint('✗ FFmpeg re-encode also failed: $logs');
      _cleanupIntermediateFiles([videoCombined, audioCombined, subCombined]);
      throw Exception('MP4 conversion failed');
    }

    _cleanupIntermediateFiles([videoCombined, audioCombined, subCombined]);
    debugPrint('✅ MP4 created: $outputMp4Path');
  }

  /// Cleanup intermediate binary-concat files
  void _cleanupIntermediateFiles(List<String?> paths) {
    for (final path in paths) {
      if (path == null) continue;
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  // ── Helpers ────────────────────────────────────────────
  Future<String> _fetchContent(String url) async {
    try {
      final response = await _dio.get(url);
      return response.data.toString();
    } catch (e) {
      debugPrint('❌ Failed to fetch: $url → $e');
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
