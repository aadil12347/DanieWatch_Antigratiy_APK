import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

class HlsDownloaderService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
        'Accept': '*/*',
      },
    ),
  );

  Function(double progress, int downloadedParts, int totalParts)? onProgress;
  Function(String error)? onError;
  Function(String localPath)? onComplete;

  bool _isCancelled = false;
  bool _isPaused = false;

  void cancel() => _isCancelled = true;
  void pause() => _isPaused = true;
  void resume() => _isPaused = false;

  String _resolveUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.startsWith('http')) return relativeUrl;
    return Uri.parse(baseUrl).resolve(relativeUrl).toString();
  }

  Future<void> startDownload({
    required String m3u8Url,
    required String saveDirectory,
  }) async {
    _isCancelled = false;
    _isPaused = false;

    try {
      final dir = Directory(saveDirectory);
      if (!await dir.exists()) await dir.create(recursive: true);

      String masterContent = await _fetchContent(m3u8Url);

      // If it's a direct chunklist (not a master), wrap it in a pseudo-master
      bool isMaster =
          masterContent.contains('#EXT-X-STREAM-INF') ||
          masterContent.contains('#EXT-X-MEDIA');

      List<String> segmentDownloadQueue = []; // URLs to download
      List<String> segmentLocalPaths = []; // Where to save them

      String localMasterPath = path.join(saveDirectory, 'master.m3u8');

      if (isMaster) {
        // --- PHASE 1: Parse Master Playlist & Find Sub-Playlists ---
        final lines = masterContent.split('\n');
        final newMasterLines = <String>[];
        int playlistCounter = 0;
        int globalSegmentCounter = 0;

        for (int i = 0; i < lines.length; i++) {
          String line = lines[i];
          if (line.trim().isEmpty) continue;

          // Handle Audio/Subtitle Tracks (EXT-X-MEDIA)
          if (line.startsWith('#EXT-X-MEDIA:')) {
            final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
            if (uriMatch != null) {
              String subUrl = _resolveUrl(m3u8Url, uriMatch.group(1)!);
              String localSubName = 'playlist_$playlistCounter.m3u8';
              playlistCounter++;

              // Fetch and process sub-playlist
              globalSegmentCounter = await _processSubPlaylist(
                subUrl,
                saveDirectory,
                localSubName,
                globalSegmentCounter,
                segmentDownloadQueue,
                segmentLocalPaths,
              );

              newMasterLines.add(
                line.replaceFirst(uriMatch.group(0)!, 'URI="$localSubName"'),
              );
              continue;
            }
          }

          // Handle Video Variants (EXT-X-STREAM-INF)
          if (line.startsWith('#EXT-X-STREAM-INF:')) {
            newMasterLines.add(line);
            if (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
              i++; // Move to the URL line
              String subUrl = _resolveUrl(m3u8Url, lines[i].trim());
              String localSubName = 'playlist_$playlistCounter.m3u8';
              playlistCounter++;

              globalSegmentCounter = await _processSubPlaylist(
                subUrl,
                saveDirectory,
                localSubName,
                globalSegmentCounter,
                segmentDownloadQueue,
                segmentLocalPaths,
              );

              newMasterLines.add(localSubName);
            }
            continue;
          }

          newMasterLines.add(line);
        }
        await File(localMasterPath).writeAsString(newMasterLines.join('\n'));
      } else {
        // It's already a single stream, treat it as the only sub-playlist
        await _processSubPlaylist(
          m3u8Url,
          saveDirectory,
          'master.m3u8',
          0,
          segmentDownloadQueue,
          segmentLocalPaths,
        );
      }

      // --- PHASE 2: Download All Segments ---
      int totalSegments = segmentDownloadQueue.length;
      if (totalSegments == 0) throw Exception('No segments found to download.');

      for (int i = 0; i < totalSegments; i++) {
        while (_isPaused && !_isCancelled) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (_isCancelled) throw Exception('Download cancelled');

        final file = File(segmentLocalPaths[i]);
        if (!await file.exists() || await file.length() == 0) {
          await _downloadFile(segmentDownloadQueue[i], segmentLocalPaths[i]);
        }
        onProgress?.call((i + 1) / totalSegments, i + 1, totalSegments);
      }

      if (_isCancelled) throw Exception('Download cancelled');
      onComplete?.call(localMasterPath);
    } catch (e) {
      if (!_isCancelled) onError?.call(e.toString());
    }
  }

  Future<int> _processSubPlaylist(
    String subUrl,
    String saveDir,
    String localName,
    int globalSegmentCounter,
    List<String> downloadQueue,
    List<String> pathQueue,
  ) async {
    String content = await _fetchContent(subUrl);
    final lines = content.split('\n');
    final newLines = <String>[];

    for (String line in lines) {
      if (line.trim().isEmpty) continue;

      if (line.startsWith('#EXT-X-KEY:')) {
        final keyMatch = RegExp(r'URI="([^"]+)"').firstMatch(line);
        if (keyMatch != null) {
          String keyUrl = _resolveUrl(subUrl, keyMatch.group(1)!);
          String keyName = 'key_$globalSegmentCounter.bin';
          downloadQueue.add(keyUrl);
          pathQueue.add(path.join(saveDir, keyName));
          newLines.add(line.replaceFirst(keyMatch.group(0)!, 'URI="$keyName"'));
          globalSegmentCounter++;
        } else {
          newLines.add(line);
        }
      } else if (!line.startsWith('#')) {
        // This is a TS segment
        String segmentUrl = _resolveUrl(subUrl, line.trim());
        String ext = segmentUrl.contains('?')
            ? segmentUrl.split('?').first.split('.').last
            : segmentUrl.split('.').last;
        if (ext.length > 4) ext = 'ts';

        String segName = 'seg_$globalSegmentCounter.$ext';
        downloadQueue.add(segmentUrl);
        pathQueue.add(path.join(saveDir, segName));
        newLines.add(segName);
        globalSegmentCounter++;
      } else {
        newLines.add(line);
      }
    }

    await File(
      path.join(saveDir, localName),
    ).writeAsString(newLines.join('\n'));
    return globalSegmentCounter;
  }

  Future<String> _fetchContent(String url) async {
    final response = await _dio.get(url);
    return response.data.toString();
  }

  Future<void> _downloadFile(String url, String savePath) async {
    await _dio.download(url, savePath);
  }
}
