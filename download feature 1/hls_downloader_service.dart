import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

/// Number of segments downloaded at the same time.
/// Higher = faster but uses more memory/connections.
/// 5 is the sweet spot for most mobile networks.
const int _kConcurrency = 5;

/// Per-segment retry attempts before giving up.
const int _kSegmentRetries = 4;

class HlsDownloaderService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
      },
    ),
  );

  Function(double progress, int downloadedParts, int totalParts)? onProgress;
  Function(String error)? onError;
  Function(String localPath)? onComplete;

  bool _isCancelled = false;
  bool _isPaused    = false;

  /// Completed segment count — thread-safe via single isolate
  int _completedSegments = 0;

  void cancel() => _isCancelled = true;
  void pause()  => _isPaused    = true;
  void resume() => _isPaused    = false;

  String _resolveUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    return Uri.parse(baseUrl).resolve(relativeUrl).toString();
  }

  Future<void> startDownload({
    required String m3u8Url,
    required String saveDirectory,
  }) async {
    _isCancelled        = false;
    _isPaused           = false;
    _completedSegments  = 0;

    try {
      final dir = Directory(saveDirectory);
      if (!await dir.exists()) await dir.create(recursive: true);

      final masterContent = await _fetchContent(m3u8Url);

      final bool isMaster = masterContent.contains('#EXT-X-STREAM-INF') ||
          masterContent.contains('#EXT-X-MEDIA');

      // Build two parallel lists:
      //   segmentDownloadQueue → remote URLs to fetch
      //   segmentLocalPaths   → where to save them
      final List<String> segmentDownloadQueue = [];
      final List<String> segmentLocalPaths    = [];

      final localMasterPath = path.join(saveDirectory, 'master.m3u8');

      if (isMaster) {
        // ── PHASE 1: Parse master playlist ────────────────────────────────
        final lines          = masterContent.split('\n');
        final newMasterLines = <String>[];
        int playlistCounter      = 0;
        int globalSegmentCounter = 0;

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trim().isEmpty) continue;

          // Audio / subtitle tracks
          if (line.startsWith('#EXT-X-MEDIA:')) {
            final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
            if (uriMatch != null) {
              final subUrl      = _resolveUrl(m3u8Url, uriMatch.group(1)!);
              final localSubName = 'playlist_$playlistCounter.m3u8';
              playlistCounter++;

              globalSegmentCounter = await _processSubPlaylist(
                subUrl, saveDirectory, localSubName,
                globalSegmentCounter, segmentDownloadQueue, segmentLocalPaths,
              );

              newMasterLines.add(
                line.replaceFirst(uriMatch.group(0)!, 'URI="$localSubName"'),
              );
              continue;
            }
          }

          // Video variants
          if (line.startsWith('#EXT-X-STREAM-INF:')) {
            newMasterLines.add(line);
            if (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
              i++;
              final subUrl       = _resolveUrl(m3u8Url, lines[i].trim());
              final localSubName = 'playlist_$playlistCounter.m3u8';
              playlistCounter++;

              globalSegmentCounter = await _processSubPlaylist(
                subUrl, saveDirectory, localSubName,
                globalSegmentCounter, segmentDownloadQueue, segmentLocalPaths,
              );

              newMasterLines.add(localSubName);
            }
            continue;
          }

          newMasterLines.add(line);
        }

        await File(localMasterPath).writeAsString(newMasterLines.join('\n'));
      } else {
        // Single-stream playlist
        await _processSubPlaylist(
          m3u8Url, saveDirectory, 'master.m3u8',
          0, segmentDownloadQueue, segmentLocalPaths,
        );
      }

      // ── PHASE 2: Download ALL segments in parallel ─────────────────────
      final total = segmentDownloadQueue.length;
      if (total == 0) throw Exception('No segments found to download.');

      _completedSegments = 0;

      // Split into chunks of _kConcurrency and process each chunk together.
      for (int offset = 0; offset < total; offset += _kConcurrency) {
        // Respect pause / cancel between chunks
        while (_isPaused && !_isCancelled) {
          await Future.delayed(const Duration(milliseconds: 400));
        }
        if (_isCancelled) throw Exception('Download cancelled');

        final end   = (offset + _kConcurrency).clamp(0, total);
        final chunk = List.generate(
          end - offset,
          (j) => _downloadSegmentWithRetry(
            segmentDownloadQueue[offset + j],
            segmentLocalPaths[offset + j],
            onDone: () {
              _completedSegments++;
              onProgress?.call(
                _completedSegments / total,
                _completedSegments,
                total,
              );
            },
          ),
        );

        // Run this chunk concurrently — wait for ALL to finish before next
        await Future.wait(chunk);
        if (_isCancelled) throw Exception('Download cancelled');
      }

      if (_isCancelled) throw Exception('Download cancelled');
      onComplete?.call(localMasterPath);
    } catch (e) {
      if (!_isCancelled) onError?.call(e.toString());
    }
  }

  // ─── Download a single segment with retry ──────────────────────────────
  Future<void> _downloadSegmentWithRetry(
    String url,
    String savePath, {
    required VoidCallback onDone,
  }) async {
    // Skip if already downloaded (resume support)
    final file = File(savePath);
    if (await file.exists() && await file.length() > 0) {
      onDone();
      return;
    }

    for (int attempt = 1; attempt <= _kSegmentRetries; attempt++) {
      if (_isCancelled) return;

      try {
        await _downloadFile(url, savePath);
        onDone();
        return; // success
      } catch (e) {
        if (_isCancelled) return;
        if (attempt == _kSegmentRetries) rethrow;

        // Exponential back-off: 1s, 2s, 4s
        final waitMs = 1000 * (1 << (attempt - 1));
        await Future.delayed(Duration(milliseconds: waitMs));
      }
    }
  }

  // ─── Parse a sub-playlist and enqueue its segments ─────────────────────
  Future<int> _processSubPlaylist(
    String subUrl,
    String saveDir,
    String localName,
    int globalSegmentCounter,
    List<String> downloadQueue,
    List<String> pathQueue,
  ) async {
    final content  = await _fetchContent(subUrl);
    final lines    = content.split('\n');
    final newLines = <String>[];

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      // Encryption key
      if (line.startsWith('#EXT-X-KEY:')) {
        final keyMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (keyMatch != null) {
          final keyUrl  = _resolveUrl(subUrl, keyMatch.group(1)!);
          final keyName = 'key_$globalSegmentCounter.bin';
          downloadQueue.add(keyUrl);
          pathQueue.add(path.join(saveDir, keyName));
          newLines.add(
            line.replaceFirst(keyMatch.group(0)!, 'URI="$keyName"'),
          );
          globalSegmentCounter++;
        } else {
          newLines.add(line);
        }
        continue;
      }

      // Segment line (not a directive)
      if (!line.startsWith('#')) {
        final segmentUrl = _resolveUrl(subUrl, line.trim());
        String ext = segmentUrl.contains('?')
            ? segmentUrl.split('?').first.split('.').last
            : segmentUrl.split('.').last;
        if (ext.length > 4) ext = 'ts';

        final segName = 'seg_$globalSegmentCounter.$ext';
        downloadQueue.add(segmentUrl);
        pathQueue.add(path.join(saveDir, segName));
        newLines.add(segName);
        globalSegmentCounter++;
        continue;
      }

      newLines.add(line);
    }

    await File(path.join(saveDir, localName)).writeAsString(newLines.join('\n'));
    return globalSegmentCounter;
  }

  // ─── Fetch text content (m3u8 / key) ──────────────────────────────────
  Future<String> _fetchContent(String url) async {
    for (int attempt = 1; attempt <= _kSegmentRetries; attempt++) {
      try {
        final response = await _dio.get<String>(
          url,
          options: Options(responseType: ResponseType.plain),
        );
        return response.data ?? '';
      } catch (e) {
        if (attempt == _kSegmentRetries) rethrow;
        await Future.delayed(Duration(seconds: attempt));
      }
    }
    return '';
  }

  // ─── Binary download (TS segments / keys) ─────────────────────────────
  Future<void> _downloadFile(String url, String savePath) async {
    await _dio.download(
      url,
      savePath,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        },
        receiveTimeout: const Duration(seconds: 60),
      ),
      deleteOnError: true,
    );
  }
}

// Convenience typedef so callers don't need to import Flutter
typedef VoidCallback = void Function();
