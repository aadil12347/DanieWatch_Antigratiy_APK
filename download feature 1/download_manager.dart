import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_full/statistics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../services/hls_downloader_service.dart';
import '../../services/m3u8_parser.dart';
import '../../services/download_notification_service.dart';

/// Port name for isolate communication
const String _downloadPortName = 'downloader_send_port';

/// Maximum auto-retry attempts for FFmpeg downloads
const int _kMaxRetryAttempts = 5;

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(_downloadPortName);
  send?.send([id, status, progress]);
}

enum DownloadStatus { pending, downloading, paused, completed, failed, canceled }

class DownloadItem {
  final String id;
  final String url;
  final String title;
  final int season;
  final int episode;
  final String? posterUrl;
  final String fileExtension;
  DownloadStatus status;
  double progress;
  int totalBytes;
  int downloadedBytes;
  String? localPath;
  String? taskId;
  DateTime createdAt;
  DateTime? completedAt;
  String? error;

  // ── FFmpeg download fields ──
  final String? videoStreamUrl;
  final String? audioStreamUrl;
  final String? qualityLabel;
  final String? audioLabel;
  final bool isFfmpegDownload;

  DownloadItem({
    required this.id,
    required this.url,
    required this.title,
    required this.season,
    required this.episode,
    this.posterUrl,
    this.fileExtension = '.mp4',
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.localPath,
    this.taskId,
    DateTime? createdAt,
    this.completedAt,
    this.error,
    this.videoStreamUrl,
    this.audioStreamUrl,
    this.qualityLabel,
    this.audioLabel,
    this.isFfmpegDownload = false,
  }) : createdAt = createdAt ?? DateTime.now();

  String get displayName {
    if (season > 0 && episode > 0) {
      final s = season.toString().padLeft(2, '0');
      final e = episode.toString().padLeft(2, '0');
      return 'S$s E$e $title';
    }
    return title;
  }

  /// Full filename with the original extension preserved
  String get fileName {
    final ext = fileExtension.startsWith('.') ? fileExtension : '.$fileExtension';
    if (season > 0 && episode > 0) {
      return '$title S${season.toString().padLeft(2, '0')} E${episode.toString().padLeft(2, '0')}$ext';
    }
    return '$title$ext';
  }

  /// Display tag for the download card (e.g. "720p · Hindi")
  String get qualityTag {
    final parts = <String>[];
    if (qualityLabel != null) parts.add(qualityLabel!);
    if (audioLabel != null) parts.add(audioLabel!);
    return parts.join(' · ');
  }

  String get formattedSize {
    if (totalBytes == 0) return 'Unknown';
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedProgress => formattedDownloadedBytes;

  String get formattedDownloadedBytes {
    if (downloadedBytes == 0) return '0.0 MB';
    return '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get statusLabel {
    switch (status) {
      case DownloadStatus.pending:     return 'Queued';
      case DownloadStatus.downloading: return formattedDownloadedBytes;
      case DownloadStatus.completed:   return 'Ready';
      case DownloadStatus.failed:      return 'Failed';
      case DownloadStatus.canceled:    return 'Cancelled';
      case DownloadStatus.paused:      return 'Paused';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'title': title,
    'season': season,
    'episode': episode,
    'posterUrl': posterUrl,
    'fileExtension': fileExtension,
    'status': status.index,
    'progress': progress,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'localPath': localPath,
    'taskId': taskId,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'error': error,
    'videoStreamUrl': videoStreamUrl,
    'audioStreamUrl': audioStreamUrl,
    'qualityLabel': qualityLabel,
    'audioLabel': audioLabel,
    'isFfmpegDownload': isFfmpegDownload,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
    id: json['id'],
    url: json['url'],
    title: json['title'],
    season: json['season'],
    episode: json['episode'],
    posterUrl: json['posterUrl'],
    fileExtension: json['fileExtension'] ?? '.mp4',
    status: DownloadStatus.values[json['status']],
    progress: (json['progress'] as num).toDouble(),
    totalBytes: json['totalBytes'],
    downloadedBytes: json['downloadedBytes'],
    localPath: json['localPath'],
    taskId: json['taskId'],
    createdAt: DateTime.parse(json['createdAt']),
    completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
    error: json['error'],
    videoStreamUrl: json['videoStreamUrl'],
    audioStreamUrl: json['audioStreamUrl'],
    qualityLabel: json['qualityLabel'],
    audioLabel: json['audioLabel'],
    isFfmpegDownload: json['isFfmpegDownload'] ?? false,
  );
}

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const String _downloadsKey = 'download_items';

  final List<DownloadItem> _downloads = [];
  final ReceivePort _port = ReceivePort();
  final Map<String, HlsDownloaderService> _activeHlsDownloads = {};
  final DownloadNotificationService _notifService = DownloadNotificationService();

  /// Maps download item id → active FFmpegSession (for per-item cancel)
  final Map<String, FFmpegSession> _activeFfmpegSessions = {};

  List<DownloadItem> get downloads => List.unmodifiable(_downloads);

  List<DownloadItem> get downloadingItems =>
      _downloads.where((d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.pending).toList();

  List<DownloadItem> get completedItems =>
      _downloads.where((d) => d.status == DownloadStatus.completed).toList();

  List<DownloadItem> get failedItems =>
      _downloads.where((d) => d.status == DownloadStatus.failed).toList();

  Function(DownloadItem)? onDownloadUpdate;
  Function(DownloadItem)? onDownloadComplete;

  Future<void> initialize() async {
    if (kIsWeb) return;
    await FlutterDownloader.initialize();
    await _notifService.init();
    await _loadDownloads();

    // Reset interrupted downloads
    for (var d in _downloads) {
      if (d.status == DownloadStatus.downloading) {
        if (d.isFfmpegDownload) {
          // Will auto-retry on next startFfmpegDownload call;
          // mark as failed with friendly message.
          d.status = DownloadStatus.failed;
          d.error = 'App restart — tap retry';
          d.progress = 0;
        } else if (d.fileExtension == '.m3u8') {
          d.status = DownloadStatus.paused;
        }
      }
    }
    await _saveDownloads();

    _unbindPort();
    IsolateNameServer.registerPortWithName(_port.sendPort, _downloadPortName);

    _port.listen((dynamic data) {
      final taskId = data[0] as String;
      final status  = data[1] as int;
      final progress = data[2] as int;
      _handleDownloadProgress(taskId, status, progress);
    });

    await FlutterDownloader.registerCallback(downloadCallback);
  }

  void _unbindPort() {
    IsolateNameServer.removePortNameMapping(_downloadPortName);
  }

  void _handleDownloadProgress(String taskId, int status, int progress) {
    final item = _findByTaskId(taskId);
    if (item == null) {
      debugPrint('Download item not found for taskId: $taskId');
      return;
    }

    item.progress = progress / 100.0;
    item.downloadedBytes = (item.totalBytes * item.progress).toInt();

    if (status == DownloadTaskStatus.complete.index) {
      item.status = DownloadStatus.completed;
      item.completedAt = DateTime.now();
      _notifService.showComplete(id: item.id.hashCode, title: item.displayName);
      onDownloadComplete?.call(item);
    } else if (status == DownloadTaskStatus.failed.index) {
      item.status = DownloadStatus.failed;
      item.error = 'Download failed';
      _notifService.showFailed(id: item.id.hashCode, title: item.displayName);
    } else if (status == DownloadTaskStatus.canceled.index) {
      item.status = DownloadStatus.canceled;
      _notifService.cancel(item.id.hashCode);
    } else if (status == DownloadTaskStatus.running.index) {
      item.status = DownloadStatus.downloading;
      _notifService.showProgress(
        id: item.id.hashCode,
        title: item.displayName,
        progress: progress,
      );
    } else if (status == DownloadTaskStatus.paused.index) {
      item.status = DownloadStatus.paused;
    }

    onDownloadUpdate?.call(item);
    _saveDownloads();
  }

  DownloadItem? _findByTaskId(String taskId) {
    for (final d in _downloads) {
      if (d.taskId == taskId) return d;
    }
    return null;
  }

  static String extractExtension(String url) {
    try {
      String path = url.split('?').first.split('#').first;
      final lastSegment = path.split('/').last;
      final dotIndex = lastSegment.lastIndexOf('.');
      if (dotIndex != -1 && dotIndex < lastSegment.length - 1) {
        final ext = lastSegment.substring(dotIndex).toLowerCase();
        const validExts = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.ts', '.m3u8'];
        if (validExts.contains(ext)) return ext;
      }
    } catch (_) {}
    return '.mp4';
  }

  Future<bool> requestPermissions() async {
    if (kIsWeb) return true;
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        final manageStatus = await Permission.manageExternalStorage.request();
        return manageStatus.isGranted;
      }
      return status.isGranted;
    }
    return true;
  }

  Future<Directory> getDownloadDirectory() async {
    if (kIsWeb) throw UnsupportedError('Downloads not supported on web');
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download/DanieWatch');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }
    return await getApplicationDocumentsDirectory();
  }

  // ═══════════════════════════════════════════════════════════
  //  FFMPEG-BASED HLS DOWNLOAD  ─  NEVER-STOP EDITION
  // ═══════════════════════════════════════════════════════════

  Future<DownloadItem?> startFfmpegDownload({
    required String m3u8Url,
    required String title,
    required int season,
    required int episode,
    String? posterUrl,
    StreamVariant? variant,
    AudioTrack? audioTrack,
  }) async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) return null;

    final qualityLbl = variant?.badgeLabel;
    final audioLbl   = audioTrack?.displayName;
    final videoUrl   = variant?.url ?? m3u8Url;
    final audioUrl   = audioTrack?.url;

    final dir = await getDownloadDirectory();
    final safeTitle = _buildSafeTitle(title, season, episode, qualityLbl);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${dir.path}/${safeTitle}_$ts.mp4';

    final item = DownloadItem(
      id: ts.toString(),
      url: m3u8Url,
      title: title,
      season: season,
      episode: episode,
      posterUrl: posterUrl,
      fileExtension: '.mp4',
      status: DownloadStatus.downloading,
      videoStreamUrl: videoUrl,
      audioStreamUrl: audioUrl,
      qualityLabel: qualityLbl,
      audioLabel: audioLbl,
      localPath: outputPath,
      isFfmpegDownload: true,
    );

    _downloads.insert(0, item);
    await _saveDownloads();
    onDownloadUpdate?.call(item);

    _notifService.showProgress(
      id: item.id.hashCode,
      title: item.displayName,
      progress: 0,
      body: '${item.qualityTag.isNotEmpty ? "${item.qualityTag} · " : ""}Starting…',
    );

    // Start with attempt 1 — will auto-retry up to _kMaxRetryAttempts
    _runFfmpegWithRetry(item, attempt: 1);
    return item;
  }

  String _buildSafeTitle(String title, int season, int episode, String? quality) {
    final parts = <String>[title];
    if (season > 0 && episode > 0) {
      parts.add('S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}');
    }
    if (quality != null) parts.add(quality.replaceAll(' ', ''));
    final joined = parts.join('_');
    return joined
        .replaceAll(RegExp(r'[<>:"/\\|?* ]'), '_')
        .substring(0, joined.length.clamp(0, 80));
  }

  // ─── Build FFmpeg Command ────────────────────────────────────────────────
  // KEY FIX: reconnect flags keep download alive through network hiccups.
  //   -reconnect 1              → reconnect on disconnect
  //   -reconnect_streamed 1     → reconnect even for streamed content
  //   -reconnect_delay_max 30   → wait up to 30s before giving up on reconnect
  //   -reconnect_at_eof 1       → reconnect if server closes early
  //   -timeout 60000000         → 60s socket timeout (in microseconds)
  //   -analyzeduration 20M      → give more time to analyze stream headers
  //   -probesize 20M            → larger probe buffer — avoids "Invalid data"
  // ────────────────────────────────────────────────────────────────────────
  String _buildFfmpegCommand(DownloadItem item) {
    final videoUrl = item.videoStreamUrl ?? item.url;
    final audioUrl = item.audioStreamUrl;
    final out      = item.localPath!;

    const reconnect =
        '-reconnect 1 '
        '-reconnect_streamed 1 '
        '-reconnect_delay_max 30 '
        '-reconnect_at_eof 1 '
        '-timeout 60000000 '          // 60s per socket op
        '-analyzeduration 20000000 '  // 20s stream analysis
        '-probesize 20000000';         // 20MB probe buffer

    const headers =
        '-headers "User-Agent: Mozilla/5.0 (Linux; Android 13) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 '
        'Mobile Safari/537.36\\r\\nAccept: */*\\r\\n"';

    if (audioUrl != null && audioUrl.isNotEmpty) {
      return '$reconnect $headers -i "$videoUrl" '
          '$reconnect $headers -i "$audioUrl" '
          '-map 0:v:0 '
          '-map 1:a:0 '
          '-c:v copy '
          '-c:a copy '
          '-bsf:a aac_adtstoasc '
          '-movflags +faststart '
          '-y "$out"';
    } else {
      return '$reconnect $headers -i "$videoUrl" '
          '-c copy '
          '-bsf:a aac_adtstoasc '
          '-movflags +faststart '
          '-y "$out"';
    }
  }

  // ─── Run FFmpeg with Auto-Retry ──────────────────────────────────────────
  Future<void> _runFfmpegWithRetry(DownloadItem item, {required int attempt}) async {
    // Item may have been cancelled while we were waiting between retries
    if (item.status == DownloadStatus.canceled ||
        item.status == DownloadStatus.completed) return;

    if (attempt > 1) {
      debugPrint('⟳ FFmpeg retry $attempt/$_kMaxRetryAttempts for "${item.displayName}"');
      _notifService.showProgress(
        id: item.id.hashCode,
        title: item.displayName,
        progress: (item.progress * 100).toInt(),
        body: 'Reconnecting… (attempt $attempt/$_kMaxRetryAttempts)',
      );
    }

    item.status = DownloadStatus.downloading;
    item.error  = null;

    final command = _buildFfmpegCommand(item);
    debugPrint('▶ FFmpeg[$attempt]: $command');

    // Enable per-item statistics (cleared per session automatically)
    FFmpegKitConfig.enableStatisticsCallback((Statistics stats) {
      _onFfmpegProgress(item, stats);
    });

    // Execute & store session so we can cancel it later
    final session = await FFmpegKit.executeAsync(command);
    _activeFfmpegSessions[item.id] = session;

    // Wait for completion
    final returnCode = await session.getReturnCode();
    _activeFfmpegSessions.remove(item.id);

    // ── Success ──────────────────────────────────────────────
    if (ReturnCode.isSuccess(returnCode)) {
      final file = File(item.localPath!);
      item.totalBytes      = await file.length().catchError((_) => 0);
      item.downloadedBytes = item.totalBytes;
      item.status          = DownloadStatus.completed;
      item.progress        = 1.0;
      item.completedAt     = DateTime.now();
      _notifService.showComplete(id: item.id.hashCode, title: item.displayName);
      onDownloadComplete?.call(item);
      await _saveDownloads();
      onDownloadUpdate?.call(item);
      return;
    }

    // ── Cancelled by user ─────────────────────────────────────
    if (ReturnCode.isCancel(returnCode) ||
        item.status == DownloadStatus.canceled) {
      item.status = DownloadStatus.canceled;
      _notifService.cancel(item.id.hashCode);
      await _saveDownloads();
      onDownloadUpdate?.call(item);
      return;
    }

    // ── Error → decide whether to retry ──────────────────────
    final logs = await session.getAllLogsAsString() ?? '';
    final errorMsg = _parseFfmpegError(logs);
    debugPrint('✗ FFmpeg[$attempt] error: $errorMsg\n$logs');

    // Permanent errors — no point retrying
    final isPermanent = logs.contains('403') ||
        logs.contains('404') ||
        logs.contains('Invalid data found');

    if (!isPermanent && attempt < _kMaxRetryAttempts) {
      // Exponential back-off: 3s, 6s, 12s, 24s …
      final waitSecs = 3 * attempt;
      debugPrint('↻ Waiting ${waitSecs}s before retry…');
      await Future.delayed(Duration(seconds: waitSecs));
      return _runFfmpegWithRetry(item, attempt: attempt + 1);
    }

    // All retries exhausted or permanent error
    item.status = DownloadStatus.failed;
    item.error  = errorMsg;
    _notifService.showFailed(
      id: item.id.hashCode,
      title: item.displayName,
      error: item.error,
    );
    await _saveDownloads();
    onDownloadUpdate?.call(item);
  }

  // ─── Progress callback ───────────────────────────────────────────────────
  int _lastProgressUpdate = 0;
  int _lastPct = -1;

  void _onFfmpegProgress(DownloadItem item, Statistics stats) {
    if (item.status != DownloadStatus.downloading) return;

    final processedKb = stats.getSize();
    if (processedKb <= 0) return;

    final estimated = (processedKb / (500 * 1024)).clamp(0.0, 0.95);
    item.progress        = estimated;
    item.downloadedBytes = processedKb;

    final pct = (estimated * 100).toInt();
    final now = DateTime.now().millisecondsSinceEpoch;

    if (pct != _lastPct || (now - _lastProgressUpdate) > 1000) {
      _lastPct = pct;
      _lastProgressUpdate = now;

      _notifService.showProgress(
        id: item.id.hashCode,
        title: item.displayName,
        progress: pct,
        body:
            '${item.qualityTag.isNotEmpty ? "${item.qualityTag} · " : ""}'
            'Downloading… ${item.formattedDownloadedBytes}',
      );

      onDownloadUpdate?.call(item);
    }
  }

  // ─── Error parser ─────────────────────────────────────────────────────────
  String _parseFfmpegError(String logs) {
    if (logs.contains('403'))              return 'Access denied (403) — stream expired';
    if (logs.contains('404'))              return 'Stream not found (404)';
    if (logs.contains('Connection timed')) return 'Connection timed out';
    if (logs.contains('Connection reset')) return 'Connection reset by server';
    if (logs.contains('Invalid data'))     return 'Invalid stream format';
    if (logs.contains('moov atom'))        return 'Incomplete download — tap retry';
    if (logs.contains('End of file'))      return 'Stream ended early — tap retry';
    return 'Download failed — tap retry';
  }

  // ─── Cancel a specific FFmpeg download (per-item) ──────────────────────
  Future<void> cancelFfmpegDownload(String id) async {
    final session = _activeFfmpegSessions.remove(id);
    if (session != null) {
      // Cancel only THIS session — doesn't touch other active downloads
      await FFmpegKit.cancel(await session.getSessionId());
    }
    final item = _findById(id);
    if (item != null) {
      item.status = DownloadStatus.canceled;
      _notifService.cancel(item.id.hashCode);
      await _saveDownloads();
      onDownloadUpdate?.call(item);
    }
  }

  /// Retry a failed ffmpeg download (resets attempt counter to 1)
  Future<void> retryFfmpegDownload(String id) async {
    final item = _findById(id);
    if (item == null || !item.isFfmpegDownload) return;

    item.status   = DownloadStatus.downloading;
    item.progress = 0;
    item.error    = null;
    await _saveDownloads();
    onDownloadUpdate?.call(item);

    _notifService.showProgress(
      id: item.id.hashCode,
      title: item.displayName,
      progress: 0,
      body: 'Retrying download…',
    );

    _runFfmpegWithRetry(item, attempt: 1);
  }

  // ═══════════════════════════════════════════════════════════
  //  LEGACY DOWNLOAD METHODS (backward compatibility)
  // ═══════════════════════════════════════════════════════════

  Future<DownloadItem> startDownload({
    required String url,
    required String title,
    required int season,
    required int episode,
    String? posterUrl,
  }) async {
    if (kIsWeb) throw UnsupportedError('Downloads are not supported on web.');
    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Storage permission denied');

    final ext = extractExtension(url);

    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      title: title,
      season: season,
      episode: episode,
      posterUrl: posterUrl,
      fileExtension: ext,
      status: DownloadStatus.downloading,
    );

    _downloads.insert(0, item);
    _saveDownloads();

    try {
      final dir = await getDownloadDirectory();
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: dir.path,
        fileName: item.fileName,
        showNotification: true,
        saveInPublicStorage: true,
      );

      item.taskId    = taskId;
      item.localPath = '${dir.path}/${item.fileName}';
      _saveDownloads();
      onDownloadUpdate?.call(item);
    } catch (e) {
      item.status = DownloadStatus.failed;
      item.error  = e.toString();
      _saveDownloads();
      onDownloadUpdate?.call(item);
    }

    return item;
  }

  Future<DownloadItem> startHlsDownload({
    required String url,
    required String title,
    required int season,
    required int episode,
    String? posterUrl,
  }) async {
    if (kIsWeb) throw UnsupportedError('Downloads are not supported on web.');
    final hasPermission = await requestPermissions();
    if (!hasPermission) throw Exception('Storage permission denied');

    final item = DownloadItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: url,
      title: title,
      season: season,
      episode: episode,
      posterUrl: posterUrl,
      fileExtension: '.m3u8',
      status: DownloadStatus.downloading,
    );

    _downloads.insert(0, item);
    _saveDownloads();
    _startHlsTask(item);
    return item;
  }

  Future<void> _startHlsTask(DownloadItem item) async {
    final dir = await getDownloadDirectory();
    final folderName = item.displayName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final saveDirectory = '${dir.path}/$folderName';

    item.localPath = '$saveDirectory/local_playlist.m3u8';

    final service = HlsDownloaderService();
    _activeHlsDownloads[item.id] = service;

    service.onProgress = (progress, downloaded, total) {
      item.progress        = progress;
      item.downloadedBytes = downloaded;
      item.totalBytes      = total;
      item.status          = DownloadStatus.downloading;
      onDownloadUpdate?.call(item);
      _saveDownloads();
    };

    service.onError = (error) {
      item.status = DownloadStatus.failed;
      item.error  = error;
      _activeHlsDownloads.remove(item.id);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    };

    service.onComplete = (localPath) {
      item.status      = DownloadStatus.completed;
      item.localPath   = localPath;
      item.completedAt = DateTime.now();
      _activeHlsDownloads.remove(item.id);
      onDownloadComplete?.call(item);
      _saveDownloads();
    };

    service.startDownload(
      m3u8Url: item.url,
      saveDirectory: saveDirectory,
    );
  }

  Future<void> pauseDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;

    if (item.isFfmpegDownload) return; // FFmpeg can't be paused, only cancelled

    if (item.fileExtension == '.m3u8') {
      _activeHlsDownloads[item.id]?.pause();
      item.status = DownloadStatus.paused;
      _saveDownloads();
      onDownloadUpdate?.call(item);
      return;
    }

    if (item.taskId != null) {
      await FlutterDownloader.pause(taskId: item.taskId!);
      item.status = DownloadStatus.paused;
      _saveDownloads();
      onDownloadUpdate?.call(item);
    }
  }

  Future<void> resumeDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;

    if (item.isFfmpegDownload && item.status == DownloadStatus.failed) {
      retryFfmpegDownload(id);
      return;
    }

    if (item.fileExtension == '.m3u8') {
      if (_activeHlsDownloads.containsKey(item.id)) {
        _activeHlsDownloads[item.id]?.resume();
      } else {
        _startHlsTask(item);
      }
      item.status = DownloadStatus.downloading;
      _saveDownloads();
      onDownloadUpdate?.call(item);
      return;
    }

    if (item.taskId != null) {
      final taskId = await FlutterDownloader.resume(taskId: item.taskId!);
      item.taskId  = taskId;
      item.status  = DownloadStatus.downloading;
      _saveDownloads();
      onDownloadUpdate?.call(item);
    }
  }

  Future<void> cancelDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;

    if (item.isFfmpegDownload) {
      await cancelFfmpegDownload(id);
      return;
    }

    if (item.fileExtension == '.m3u8') {
      _activeHlsDownloads[item.id]?.cancel();
      _activeHlsDownloads.remove(id);
    } else if (item.taskId != null) {
      await FlutterDownloader.cancel(taskId: item.taskId!);
    }

    item.status = DownloadStatus.canceled;
    _notifService.cancel(item.id.hashCode);
    _saveDownloads();
    onDownloadUpdate?.call(item);
  }

  Future<void> deleteDownload(String id) async {
    final item = _findById(id);
    if (item == null) return;

    _notifService.cancel(item.id.hashCode);

    if (item.isFfmpegDownload) {
      if (item.localPath != null && !kIsWeb) {
        final file = File(item.localPath!);
        if (await file.exists()) await file.delete();
      }
    } else if (item.fileExtension == '.m3u8') {
      _activeHlsDownloads[item.id]?.cancel();
      _activeHlsDownloads.remove(id);

      if (item.localPath != null && !kIsWeb) {
        final parentDir = File(item.localPath!).parent;
        if (await parentDir.exists()) await parentDir.delete(recursive: true);
      }
    } else {
      if (item.localPath != null && !kIsWeb) {
        final file = File(item.localPath!);
        if (await file.exists()) await file.delete();
      }
    }

    _downloads.removeWhere((d) => d.id == id);
    _saveDownloads();
  }

  Future<void> clearCompleted() async {
    _downloads.removeWhere((d) => d.status == DownloadStatus.completed);
    _saveDownloads();
  }

  DownloadItem? _findById(String id) {
    for (final d in _downloads) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> _loadDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data  = prefs.getString(_downloadsKey);
      if (data != null) {
        final List<dynamic> jsonList = jsonDecode(data);
        _downloads.clear();
        _downloads.addAll(jsonList.map((j) => DownloadItem.fromJson(j)));
      }
    } catch (e) {
      debugPrint('Error loading downloads: $e');
    }
  }

  Future<void> _saveDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _downloadsKey,
        jsonEncode(_downloads.map((d) => d.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Error saving downloads: $e');
    }
  }

  DownloadItem? getDownloadByUrl(String url) {
    for (final d in _downloads) {
      if (d.url == url) return d;
    }
    return null;
  }
}
