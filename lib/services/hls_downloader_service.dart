import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';

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

  final Dio _dio = Dio(
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

      // ── Phase 4: Cleanup segment folder ────────────────
      try {
        final segDir = Directory(saveDirectory);
        if (await segDir.exists()) {
          await segDir.delete(recursive: true);
        }
      } catch (e) {
        debugPrint('⚠ Cleanup warning: $e');
      }

      _connectivitySub?.cancel();
      onComplete?.call(outputMp4Path);
    } catch (e) {
      _connectivitySub?.cancel();
      if (!_isCancelled) {
        debugPrint('❌ Download error: $e');
        onError?.call(e.toString());
      }
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

      // Handle EXT-X-MAP (initialization segment)
      if (line.startsWith('#EXT-X-MAP:')) {
        final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (uriMatch != null) {
          String mapUrl = _resolveUrl(playlistUrl, uriMatch.group(1)!);
          segments.add(_SegmentTask(
            url: mapUrl,
            localPath: p.join(saveDir, '${prefix}_init_$segIndex.mp4'),
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
      } catch (e) {
        debugPrint(
            '⚠ ${p.basename(seg.localPath)} attempt ${attempt + 1} failed: $e');
        if (attempt == _maxRetries - 1) {
          throw Exception(
              'Failed to download ${p.basename(seg.localPath)} after $_maxRetries attempts: $e');
        }
      }
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
  // ══════════════════════════════════════════════════════════
  Future<void> _muxToMp4(
    List<_SegmentTask> videoSegments,
    List<_SegmentTask> audioSegments,
    List<_SegmentTask> subtitleSegments,
    String saveDir,
    String outputMp4Path,
  ) async {
    final videoTs = videoSegments.where((s) => s.isTsSegment).toList();
    if (videoTs.isEmpty) throw Exception('No video segments to convert');

    // Build video concat file
    final videoListPath = p.join(saveDir, 'video_list.txt');
    await File(videoListPath).writeAsString(
      videoTs
          .map((s) =>
              "file '${s.localPath.replaceAll('\\', '/').replaceAll("'", "'\\''")}'")
          .join('\n'),
    );

    final audioTs = audioSegments.where((s) => s.isTsSegment).toList();
    final subSegments = subtitleSegments.where((s) => s.isTsSegment).toList();
    
    final List<String> inputs = [];
    final List<String> maps = [];
    
    // 1. Video
    inputs.add('-f concat -safe 0 -i "$videoListPath"');
    maps.add('-map 0:v');

    // 2. Audio (Optional)
    if (audioTs.isNotEmpty) {
      final audioListPath = p.join(saveDir, 'audio_list.txt');
      await File(audioListPath).writeAsString(
        audioTs
            .map((s) =>
                "file '${s.localPath.replaceAll('\\', '/').replaceAll("'", "'\\''")}'")
            .join('\n'),
      );
      inputs.add('-f concat -safe 0 -i "$audioListPath"');
      maps.add('-map ${inputs.length - 1}:a');
    } else {
      // If no separate audio, use audio from video stream
      maps.add('-map 0:a?');
    }

    // 3. Subtitles (Optional)
    if (subSegments.isNotEmpty) {
       final subListPath = p.join(saveDir, 'sub_list.txt');
       await File(subListPath).writeAsString(
        subSegments
            .map((s) =>
                "file '${s.localPath.replaceAll('\\', '/').replaceAll("'", "'\\''")}'")
            .join('\n'),
      );
      inputs.add('-f concat -safe 0 -i "$subListPath"');
      maps.add('-map ${inputs.length - 1}:s');
    }

    // Construct final command
    // -c:s mov_text is essential for subtitles in MP4 container
    final String command = '${inputs.join(' ')} ${maps.join(' ')} -c:v copy -c:a copy -c:s mov_text -y "$outputMp4Path"';

    debugPrint('▶ FFmpeg: $command');
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      final logs = await session.getAllLogsAsString();
      debugPrint('✗ FFmpeg failed: $logs');
      throw Exception('MP4 conversion failed');
    }

    debugPrint('✅ MP4 created: $outputMp4Path');
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

  _SegmentTask({
    required this.url,
    required this.localPath,
    this.isTsSegment = false,
  });
}
