import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

class HlsDownloaderService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
  ));

  Function(double progress, int downloadedParts, int totalParts)? onProgress;
  Function(String error)? onError;
  Function(String localPath)? onComplete;

  bool _isCancelled = false;
  bool _isPaused = false;

  void cancel() {
    _isCancelled = true;
  }

  void pause() {
    _isPaused = true;
  }

  void resume() {
    _isPaused = false;
  }

  /// Parses a URL against a base URL
  String _resolveUrl(String baseUrl, String relativeUrl) {
    if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    final uri = Uri.parse(baseUrl);
    return uri.resolve(relativeUrl).toString();
  }

  Future<void> startDownload({
    required String m3u8Url,
    required String saveDirectory,
  }) async {
    _isCancelled = false;
    _isPaused = false;

    try {
      final dir = Directory(saveDirectory);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      String currentUrl = m3u8Url;
      String m3u8Content = await _fetchContent(currentUrl);

      // Check if master playlist
      if (m3u8Content.contains('#EXT-X-STREAM-INF')) {
        currentUrl = _getBestVariantUrl(m3u8Content, currentUrl);
        m3u8Content = await _fetchContent(currentUrl);
      }

      final segments = _extractSegments(m3u8Content, currentUrl);
      if (segments.isEmpty) {
        throw Exception('No video segments found in stream');
      }

      // We will create a local m3u8 file
      final localM3u8Path = path.join(saveDirectory, 'local_playlist.m3u8');
      final localM3u8File = File(localM3u8Path);
      
      // Parse the m3u8 content and replace remote URLs with local filenames
      final newM3u8Lines = <String>[];
      final lines = m3u8Content.split('\n');
      
      int segmentIndex = 0;
      int totalSegments = segments.length;

      for (String line in lines) {
        if (line.trim().isEmpty) continue;
        
        if (line.startsWith('#EXT-X-KEY:')) {
          // Handle encryption key if present
          final keyRegex = RegExp(r'URI="([^"]+)"');
          final match = keyRegex.firstMatch(line);
          if (match != null) {
            final keyUrl = _resolveUrl(currentUrl, match.group(1)!);
            final keyFilename = 'key.bin';
            await _downloadFile(keyUrl, path.join(saveDirectory, keyFilename));
            // Replace URI with local filename
            final newLine = line.replaceFirst(match.group(0)!, 'URI="$keyFilename"');
            newM3u8Lines.add(newLine);
          } else {
            newM3u8Lines.add(line);
          }
        } else if (!line.startsWith('#')) {
          // This is a segment URL
          final segmentExt = line.contains('?') ? line.split('?').first.split('.').last : line.split('.').last;
          final ext = segmentExt.length > 4 ? 'ts' : segmentExt; // fallback to ts
          final segmentFilename = 'segment_$segmentIndex.$ext';
          
          newM3u8Lines.add(segmentFilename);
          segmentIndex++;
        } else {
          newM3u8Lines.add(line);
        }
      }

      // Download all segments sequentially
      for (int i = 0; i < totalSegments; i++) {
        while (_isPaused && !_isCancelled) {
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (_isCancelled) {
          throw Exception('Download cancelled by user');
        }

        final segmentUrl = segments[i];
        final segmentExt = segmentUrl.contains('?') ? segmentUrl.split('?').first.split('.').last : segmentUrl.split('.').last;
        final ext = segmentExt.length > 4 ? 'ts' : segmentExt;
        final segmentFilename = 'segment_$i.$ext';
        final segmentPath = path.join(saveDirectory, segmentFilename);
        
        // Skip if already downloaded completely (simple check by existence, we could improve to size check)
        final file = File(segmentPath);
        if (!await file.exists() || await file.length() == 0) {
           await _downloadFile(segmentUrl, segmentPath);
        }

        onProgress?.call((i + 1) / totalSegments, i + 1, totalSegments);
      }

      if (_isCancelled) {
        throw Exception('Download cancelled by user');
      }

      await localM3u8File.writeAsString(newM3u8Lines.join('\n'));
      
      onComplete?.call(localM3u8Path);

    } catch (e) {
      if (!_isCancelled) {
        onError?.call(e.toString());
      }
    }
  }

  Future<String> _fetchContent(String url) async {
    try {
      final response = await _dio.get(url);
      return response.data.toString();
    } catch (e) {
      throw Exception('Failed to fetch playlist: $e');
    }
  }

  Future<void> _downloadFile(String url, String savePath) async {
    try {
      await _dio.download(url, savePath);
    } catch (e) {
      throw Exception('Failed to download segment $url: $e');
    }
  }

  String _getBestVariantUrl(String masterContent, String baseUrl) {
    final lines = masterContent.split('\n');
    int bestBandwidth = -1;
    String bestUrl = '';
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
        int bandwidth = 0;
        if (bandwidthMatch != null) {
          bandwidth = int.tryParse(bandwidthMatch.group(1)!) ?? 0;
        }
        
        if (i + 1 < lines.length && !lines[i+1].startsWith('#')) {
          final urlLine = lines[i+1].trim();
          if (bandwidth > bestBandwidth) {
            bestBandwidth = bandwidth;
            bestUrl = urlLine;
          }
        }
      }
    }
    
    if (bestUrl.isNotEmpty) {
      return _resolveUrl(baseUrl, bestUrl);
    }
    
    // Fallback: finding first non-comment line following EXT-X-STREAM-INF
    for (int i = 0; i < lines.length; i++) {
        if (lines[i].startsWith('#EXT-X-STREAM-INF:') && i + 1 < lines.length && !lines[i+1].startsWith('#')) {
            return _resolveUrl(baseUrl, lines[i+1].trim());
        }
    }

    throw Exception('Could not parse variant from master playlist');
  }

  List<String> _extractSegments(String playlistContent, String baseUrl) {
    final segments = <String>[];
    final lines = playlistContent.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (!trimmed.startsWith('#')) {
        segments.add(_resolveUrl(baseUrl, trimmed));
      }
    }
    return segments;
  }
}
