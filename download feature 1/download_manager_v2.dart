// lib/download_manager.dart  (UPDATED)
// ─────────────────────────────────────────────────────────
// Now supports:
//   • Specific quality variant (e.g. 720p)
//   • Specific audio track (e.g. Hindi)
//   • Audio embedded in video OR separate audio URI
//   • Smart ffmpeg command builder for all cases
// ─────────────────────────────────────────────────────────

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_full/return_code.dart';
import 'package:ffmpeg_kit_flutter_full/statistics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'm3u8_parser.dart';

// ── Download status ───────────────────────────────────────
enum DownloadStatus { queued, downloading, completed, failed, cancelled }

// ── Download item model ───────────────────────────────────
class DownloadItem {
  final String id;
  final String m3u8Url;         // original detected URL (master or media)
  final String? videoStreamUrl; // specific quality variant URL
  final String? audioStreamUrl; // separate audio track URL (if any)
  final String title;
  final String outputPath;
  final String? qualityLabel;   // e.g. "720p HD"
  final String? audioLabel;     // e.g. "🇮🇳 Hindi"
  DownloadStatus status;
  double progress;
  String? errorMessage;
  DateTime createdAt;
  int? fileSizeBytes;

  DownloadItem({
    required this.id,
    required this.m3u8Url,
    required this.title,
    required this.outputPath,
    this.videoStreamUrl,
    this.audioStreamUrl,
    this.qualityLabel,
    this.audioLabel,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.errorMessage,
    DateTime? createdAt,
    this.fileSizeBytes,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'm3u8Url': m3u8Url,
        'videoStreamUrl': videoStreamUrl,
        'audioStreamUrl': audioStreamUrl,
        'title': title,
        'outputPath': outputPath,
        'qualityLabel': qualityLabel,
        'audioLabel': audioLabel,
        'status': status.name,
        'progress': progress,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
        'fileSizeBytes': fileSizeBytes,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: json['id'],
        m3u8Url: json['m3u8Url'],
        videoStreamUrl: json['videoStreamUrl'],
        audioStreamUrl: json['audioStreamUrl'],
        title: json['title'],
        outputPath: json['outputPath'],
        qualityLabel: json['qualityLabel'],
        audioLabel: json['audioLabel'],
        status: DownloadStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => DownloadStatus.failed,
        ),
        progress: (json['progress'] as num).toDouble(),
        errorMessage: json['errorMessage'],
        createdAt: DateTime.parse(json['createdAt']),
        fileSizeBytes: json['fileSizeBytes'],
      );

  bool get isComplete => status == DownloadStatus.completed;
  bool get canPlay => isComplete && File(outputPath).existsSync();

  String get statusLabel {
    switch (status) {
      case DownloadStatus.queued:      return 'Queued';
      case DownloadStatus.downloading: return '${(progress * 100).toInt()}%';
      case DownloadStatus.completed:   return 'Ready';
      case DownloadStatus.failed:      return 'Failed';
      case DownloadStatus.cancelled:   return 'Cancelled';
    }
  }

  // Display tag for the download card (e.g. "720p · Hindi")
  String get qualityTag {
    final parts = <String>[];
    if (qualityLabel != null) parts.add(qualityLabel!);
    if (audioLabel != null) parts.add(audioLabel!);
    return parts.join(' · ');
  }
}

// ── Download Manager (singleton ChangeNotifier) ───────────
class DownloadManager extends ChangeNotifier {
  static final DownloadManager _instance = DownloadManager._internal();
  factory DownloadManager() => _instance;
  DownloadManager._internal();

  final List<DownloadItem> _downloads = [];
  List<DownloadItem> get downloads => List.unmodifiable(_downloads);

  // ── Init ───────────────────────────────────────────────
  Future<void> init() async {
    await _loadFromPrefs();
    for (final item in _downloads) {
      if (item.status == DownloadStatus.downloading) {
        item.status = DownloadStatus.failed;
        item.errorMessage = 'Interrupted — tap retry';
        item.progress = 0;
      }
    }
    await _saveToPrefs();
    notifyListeners();
  }

  // ── Start download from a DownloadSelection ────────────
  Future<DownloadItem?> startDownload({
    required String m3u8Url,
    required String title,
    StreamVariant? variant,
    AudioTrack? audioTrack,
  }) async {
    final granted = await _requestStoragePermission();
    if (!granted) return null;

    final qualityLabel = variant?.badgeLabel;
    final audioLabel   = audioTrack?.displayName;
    final safeTitle    = _buildTitle(title, qualityLabel, audioLabel);
    final outputPath   = await _buildOutputPath(safeTitle);

    // Determine the actual video URL to use
    final videoUrl = variant?.url ?? m3u8Url;

    // Audio URL: use separate URI if provided by the playlist
    // (null means audio is already embedded inside the video stream)
    final audioUrl = audioTrack?.url;

    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      m3u8Url: m3u8Url,
      videoStreamUrl: videoUrl,
      audioStreamUrl: audioUrl,
      title: title,
      outputPath: outputPath,
      qualityLabel: qualityLabel,
      audioLabel: audioLabel,
      status: DownloadStatus.downloading,
    );

    _downloads.insert(0, item);
    await _saveToPrefs();
    notifyListeners();

    _runFfmpeg(item);
    return item;
  }

  // ── Build the ffmpeg command ───────────────────────────
  //
  //  Case 1: Video only (audio embedded)
  //    ffmpeg -i videoUrl -c copy -bsf:a aac_adtstoasc output.mp4
  //
  //  Case 2: Video + separate audio URI
  //    ffmpeg -i videoUrl -i audioUrl
  //           -map 0:v:0        (take video from input 0)
  //           -map 1:a:0        (take audio from input 1)
  //           -c copy -bsf:a aac_adtstoasc output.mp4
  //
  //  Case 3: Multiple audio tracks already embedded (select by index)
  //    ffmpeg -i videoUrl -map 0:v:0 -map 0:a:0 -c copy output.mp4
  //
  String _buildCommand(DownloadItem item) {
    final videoUrl = item.videoStreamUrl ?? item.m3u8Url;
    final audioUrl = item.audioStreamUrl;
    final out = item.outputPath;

    if (audioUrl != null && audioUrl.isNotEmpty) {
      // Separate audio track file → merge with video
      return '-i "$videoUrl" '
          '-i "$audioUrl" '
          '-map 0:v:0 '
          '-map 1:a:0 '
          '-c:v copy '
          '-c:a copy '
          '-bsf:a aac_adtstoasc '
          '-movflags +faststart '
          '-y "$out"';
    } else {
      // Audio already in video stream (most common case)
      return '-i "$videoUrl" '
          '-c copy '
          '-bsf:a aac_adtstoasc '
          '-movflags +faststart '
          '-y "$out"';
    }
  }

  // ── Execute ffmpeg ─────────────────────────────────────
  Future<void> _runFfmpeg(DownloadItem item) async {
    final command = _buildCommand(item);

    FFmpegKitConfig.enableStatisticsCallback((Statistics stats) {
      _onProgress(item, stats);
    });

    debugPrint('▶ FFmpeg: $command');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      final file = File(item.outputPath);
      item.fileSizeBytes = await file.length().catchError((_) => 0);
      item.status = DownloadStatus.completed;
      item.progress = 1.0;
    } else if (ReturnCode.isCancel(returnCode)) {
      item.status = DownloadStatus.cancelled;
    } else {
      final logs = await session.getAllLogsAsString();
      item.status = DownloadStatus.failed;
      item.errorMessage = _parseError(logs ?? '');
      debugPrint('✗ FFmpeg error logs: $logs');
    }

    await _saveToPrefs();
    notifyListeners();
  }

  // ── Progress ───────────────────────────────────────────
  void _onProgress(DownloadItem item, Statistics stats) {
    if (item.status != DownloadStatus.downloading) return;
    final processedKb = stats.getSize();
    if (processedKb > 0) {
      final estimated = (processedKb / (500 * 1024)).clamp(0.0, 0.95);
      item.progress = estimated;
      notifyListeners();
    }
  }

  // ── Cancel ────────────────────────────────────────────
  Future<void> cancelDownload(String id) async {
    await FFmpegKit.cancel();
    final item = _downloads.firstWhere((d) => d.id == id);
    item.status = DownloadStatus.cancelled;
    await _saveToPrefs();
    notifyListeners();
  }

  // ── Retry ─────────────────────────────────────────────
  Future<void> retryDownload(String id) async {
    final item = _downloads.firstWhere((d) => d.id == id);
    item.status = DownloadStatus.downloading;
    item.progress = 0;
    item.errorMessage = null;
    await _saveToPrefs();
    notifyListeners();
    _runFfmpeg(item);
  }

  // ── Delete ────────────────────────────────────────────
  Future<void> deleteDownload(String id) async {
    final item = _downloads.firstWhere((d) => d.id == id);
    try {
      final file = File(item.outputPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
    _downloads.remove(item);
    await _saveToPrefs();
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────
  String _buildTitle(String title, String? quality, String? audio) {
    final parts = [title];
    if (quality != null) parts.add(quality.replaceAll(' ', ''));
    return parts.join('_');
  }

  Future<String> _buildOutputPath(String title) async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Movies/AppDownloads');
    } else {
      dir = await getApplicationDocumentsDirectory();
    }
    await dir.create(recursive: true);
    final safe = title
        .replaceAll(RegExp(r'[<>:"/\\|?* ]'), '_')
        .substring(0, title.length.clamp(0, 60));
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}/${safe}_$ts.mp4';
  }

  Future<bool> _requestStoragePermission() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.videos.request();
    if (status.isGranted) return true;
    final storage = await Permission.storage.request();
    return storage.isGranted;
  }

  String _parseError(String logs) {
    if (logs.contains('403'))              return 'Access denied (403) — stream may have expired';
    if (logs.contains('404'))              return 'Stream not found (404)';
    if (logs.contains('Connection timed')) return 'Connection timed out';
    if (logs.contains('Invalid data'))     return 'Invalid stream format';
    if (logs.contains('moov atom'))        return 'Incomplete download — retry';
    return 'Download failed — tap retry';
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'downloads', _downloads.map((d) => jsonEncode(d.toJson())).toList());
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList('downloads') ?? [];
    _downloads.clear();
    for (final s in raw) {
      try {
        _downloads.add(DownloadItem.fromJson(jsonDecode(s)));
      } catch (_) {}
    }
  }

  String get totalStorageUsed {
    final total =
        _downloads.fold<int>(0, (sum, d) => sum + (d.fileSizeBytes ?? 0));
    if (total < 1024 * 1024) return '${(total / 1024).toStringAsFixed(1)} KB';
    if (total < 1024 * 1024 * 1024) {
      return '${(total / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(total / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
