import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../services/hls_downloader_service.dart';
import '../../services/m3u8_parser.dart';
import '../../services/download_notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Port name for isolate communication
const String _downloadPortName = 'downloader_send_port';

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName(_downloadPortName);
  send?.send([id, status, progress]);
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // Handle background notification actions
  // This runs in a separate isolate. For now, we'll just log it.
  // Full background support would require IPC to the main isolate.
  debugPrint(
      'Notification background action: ${response.actionId} for payload: ${response.payload}');
}

enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  canceled,
  converting
}

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

  // ── Quality/audio fields ──
  final String? videoStreamUrl;
  final String? audioStreamUrl;
  final String? qualityLabel;
  final String? audioLabel;

  // ── Segment download tracking ──
  int totalSegments;
  int completedSegments;
  String? segmentDirectory;
  int downloadSpeed; // bytes per second

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
    this.totalSegments = 0,
    this.completedSegments = 0,
    this.segmentDirectory,
    this.downloadSpeed = 0,
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
    final ext =
        fileExtension.startsWith('.') ? fileExtension : '.$fileExtension';
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
    if (totalBytes < 1024 * 1024) {
      return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedProgress {
    // Show MB downloaded
    return formattedDownloadedBytes;
  }

  String get formattedDownloadedBytes {
    if (downloadedBytes == 0) return '0.0 MB';
    return '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get segmentProgressLabel {
    if (totalSegments > 0) {
      final pct = (progress * 100).toInt().clamp(0, 100);
      return '$pct%';
    }
    return '';
  }

  String get formattedSpeed {
    if (downloadSpeed <= 0) return '';
    if (downloadSpeed < 1024) return '$downloadSpeed B/s';
    if (downloadSpeed < 1024 * 1024) {
      return '${(downloadSpeed / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(downloadSpeed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get statusLabel {
    switch (status) {
      case DownloadStatus.pending:
        return 'Queued';
      case DownloadStatus.downloading:
        return '$formattedDownloadedBytes · $segmentProgressLabel';
      case DownloadStatus.completed:
        return 'Ready';
      case DownloadStatus.failed:
        return 'Failed';
      case DownloadStatus.canceled:
        return 'Cancelled';
      case DownloadStatus.paused:
        return 'Paused';
      case DownloadStatus.converting:
        return 'Converting…';
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
        'totalSegments': totalSegments,
        'completedSegments': completedSegments,
        'segmentDirectory': segmentDirectory,
        'downloadSpeed': downloadSpeed,
      };

  factory DownloadItem.fromJson(Map<String, dynamic> json) => DownloadItem(
        id: json['id'],
        url: json['url'],
        title: json['title'],
        season: json['season'],
        episode: json['episode'],
        posterUrl: json['posterUrl'],
        fileExtension: json['fileExtension'] ?? '.mp4',
        status: DownloadStatus
            .values[json['status'].clamp(0, DownloadStatus.values.length - 1)],
        progress: (json['progress'] as num).toDouble(),
        totalBytes: json['totalBytes'],
        downloadedBytes: json['downloadedBytes'],
        localPath: json['localPath'],
        taskId: json['taskId'],
        createdAt: DateTime.parse(json['createdAt']),
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'])
            : null,
        error: json['error'],
        videoStreamUrl: json['videoStreamUrl'],
        audioStreamUrl: json['audioStreamUrl'],
        qualityLabel: json['qualityLabel'],
        audioLabel: json['audioLabel'],
        totalSegments: json['totalSegments'] ?? 0,
        completedSegments: json['completedSegments'] ?? 0,
        segmentDirectory: json['segmentDirectory'],
        downloadSpeed: json['downloadSpeed'] ?? 0,
      );
}

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const String _downloadsKey = 'download_items';

  final List<DownloadItem> _downloads = [];
  final ReceivePort _port = ReceivePort();
  final Map<String, HlsDownloaderService> _activeHlsDownloads = {};
  final DownloadNotificationService _notifService =
      DownloadNotificationService();

  List<DownloadItem> get downloads => List.unmodifiable(_downloads);

  List<DownloadItem> get downloadingItems => _downloads
      .where((d) =>
          d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.pending ||
          d.status == DownloadStatus.converting)
      .toList();

  List<DownloadItem> get completedItems =>
      _downloads.where((d) => d.status == DownloadStatus.completed).toList();

  List<DownloadItem> get failedItems =>
      _downloads.where((d) => d.status == DownloadStatus.failed).toList();

  final _updateController = StreamController<DownloadItem>.broadcast();
  Stream<DownloadItem> get updateStream => _updateController.stream;

  final _completeController = StreamController<DownloadItem>.broadcast();
  Stream<DownloadItem> get completeStream => _completeController.stream;

  @deprecated
  Function(DownloadItem)? onDownloadUpdate;
  @deprecated
  Function(DownloadItem)? onDownloadComplete;

  Future<void> initialize() async {
    if (kIsWeb) return;
    await FlutterDownloader.initialize();
    await _notifService.init(
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    await _loadDownloads();

    // Reset interrupted downloads to paused (so user can resume)
    for (var d in _downloads) {
      if (d.status == DownloadStatus.downloading ||
          d.status == DownloadStatus.converting) {
        d.status = DownloadStatus.paused;
        d.error = null;
      }
    }
    await _saveDownloads();

    // Wire notification action buttons (Pause/Resume/Cancel from notification bar)
    _notifService.onNotificationAction = (actionId, notifId, payload) {
      // Find item by payload ID (most reliable) or fallback to hashCode
      DownloadItem? item;
      if (payload != null) {
        item = _findById(payload);
      }
      item ??= _downloads.cast<DownloadItem?>().firstWhere(
            (d) => d!.id.hashCode == notifId,
            orElse: () => null,
          );

      if (item == null) return;

      switch (actionId) {
        case 'pause':
          pauseDownload(item.id);
          break;
        case 'resume':
          resumeDownload(item.id);
          break;
        case 'cancel':
          // Cancel directly from notification (no UI modal)
          cancelDownload(item.id);
          break;
      }
    };

    // Register the port for isolate communication (legacy flutter_downloader)
    _unbindPort();
    IsolateNameServer.registerPortWithName(_port.sendPort, _downloadPortName);

    _port.listen((dynamic data) {
      final taskId = data[0] as String;
      final status = data[1] as int;
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
      _notifService.showComplete(
          id: item.id.hashCode, title: item.displayName, payload: item.id);
      onDownloadComplete?.call(item);
    } else if (status == DownloadTaskStatus.failed.index) {
      item.status = DownloadStatus.failed;
      item.error = 'Download failed';
      _notifService.showFailed(
          id: item.id.hashCode, title: item.displayName, payload: item.id);
    } else if (status == DownloadTaskStatus.canceled.index) {
      item.status = DownloadStatus.canceled;
      _notifService.cancel(item.id.hashCode);
    } else if (status == DownloadTaskStatus.running.index) {
      item.status = DownloadStatus.downloading;
      _notifService.showProgress(
        id: item.id.hashCode,
        title: item.displayName,
        progress: progress,
        payload: item.id,
      );
    } else if (status == DownloadTaskStatus.paused.index) {
      item.status = DownloadStatus.paused;
    }

    _updateController.add(item);
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
        const validExts = [
          '.mp4',
          '.mkv',
          '.avi',
          '.mov',
          '.wmv',
          '.flv',
          '.webm',
          '.m4v',
          '.ts',
          '.m3u8'
        ];
        if (validExts.contains(ext)) {
          return ext;
        }
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
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    }
    return await getApplicationDocumentsDirectory();
  }

  // ═══════════════════════════════════════════════════════════
  //  SEGMENT-BASED HLS DOWNLOAD (PRIMARY METHOD)
  // ═══════════════════════════════════════════════════════════

  /// Start a segment-based HLS download with quality selection.
  /// Downloads .ts segments in parallel, then converts to .mp4.
  Future<DownloadItem?> startSegmentDownload({
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
    final audioLbl = audioTrack?.displayName;
    final videoUrl = variant?.url ?? m3u8Url;
    final audioUrl = audioTrack?.url;

    final dir = await getDownloadDirectory();
    final safeTitle = _buildSafeTitle(title, season, episode, qualityLbl);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${dir.path}/${safeTitle}_$ts.mp4';
    final segmentDir = '${dir.path}/.segments_${safeTitle}_$ts';

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
      segmentDirectory: segmentDir,
    );

    _downloads.insert(0, item);
    await _saveDownloads();
    _updateController.add(item);
    onDownloadUpdate?.call(item);

    // Show initial notification
    _notifService.showProgress(
      id: item.id.hashCode,
      title: item.displayName,
      progress: 0,
      body: 'Starting download…',
      payload: item.id,
    );

    _runSegmentDownload(item);
    return item;
  }

  String _buildSafeTitle(
      String title, int season, int episode, String? quality) {
    final parts = <String>[title];
    if (season > 0 && episode > 0) {
      parts.add(
          'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}');
    }
    if (quality != null) parts.add(quality.replaceAll(' ', ''));
    String result = parts.join('_').replaceAll(RegExp(r'[<>:"/\\|?* ]'), '_');
    if (result.length > 80) result = result.substring(0, 80);
    return result;
  }

  /// Run the segment download in the background.
  Future<void> _runSegmentDownload(DownloadItem item) async {
    final service = HlsDownloaderService();
    _activeHlsDownloads[item.id] = service;

    int lastNotifPct = -1;
    int lastNotifTime = 0;

    service.onProgress =
        (progress, completedSegs, totalSegs, downloadedBytes, bytesPerSecond) {
      if (item.status == DownloadStatus.canceled) return;

      // Map segment progress 0.0–1.0 to 0–96%
      item.progress = progress * 0.96;
      item.completedSegments = completedSegs;
      item.totalSegments = totalSegs;
      item.downloadedBytes = downloadedBytes;
      item.downloadSpeed = bytesPerSecond;

      if (item.status != DownloadStatus.paused) {
        item.status = DownloadStatus.downloading;
      }

      final pct = (item.progress * 100).toInt();
      final now = DateTime.now().millisecondsSinceEpoch;

      // Throttle notification updates
      if (pct != lastNotifPct || (now - lastNotifTime) > 1000) {
        lastNotifPct = pct;
        lastNotifTime = now;

        final speedStr = item.formattedSpeed;
        _notifService.showProgress(
          id: item.id.hashCode,
          title: item.displayName,
          progress: pct,
          body: '$pct%${speedStr.isNotEmpty ? " · $speedStr" : ""}',
          payload: item.id,
          isPaused: item.status == DownloadStatus.paused,
        );
      }

      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    };

    service.onConversionStarted = () {
      item.status = DownloadStatus.converting;
      item.progress = 0.97;
      item.downloadSpeed = 0;

      _notifService.showProgress(
        id: item.id.hashCode,
        title: item.displayName,
        progress: 97,
        body: '97% · Finalizing...',
        payload: item.id,
      );

      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    };

    service.onError = (error) {
      item.status = DownloadStatus.failed;
      item.error = _parseError(error);
      _activeHlsDownloads.remove(item.id);

      _notifService.showFailed(
        id: item.id.hashCode,
        title: item.displayName,
        error: item.error,
        payload: item.id,
      );

      _updateController.add(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    };

    service.onComplete = (mp4Path) {
      item.status = DownloadStatus.completed;
      item.localPath = mp4Path;
      item.progress = 1.0;
      item.completedAt = DateTime.now();
      item.segmentDirectory = null;
      _activeHlsDownloads.remove(item.id);

      // Get final file size
      final file = File(mp4Path);
      if (file.existsSync()) {
        item.totalBytes = file.lengthSync();
        item.downloadedBytes = item.totalBytes;
      }

      _notifService.showComplete(
          id: item.id.hashCode, title: item.displayName, payload: item.id);
      _updateController.add(item);
      onDownloadComplete?.call(item);
      onDownloadUpdate?.call(item);
      _saveDownloads();
    };

    service.startDownload(
      videoM3u8Url: item.videoStreamUrl ?? item.url,
      audioM3u8Url: item.audioStreamUrl,
      saveDirectory: item.segmentDirectory!,
      outputMp4Path: item.localPath!,
    );
  }

  String _parseError(String error) {
    if (error.contains('403')) {
      return 'Access denied (403) — stream may have expired';
    }
    if (error.contains('404')) return 'Stream not found (404)';
    if (error.contains('Connection timed')) return 'Connection timed out';
    if (error.contains('Invalid')) return 'Invalid stream format';
    if (error.contains('No segments')) return 'No segments found in stream';
    if (error.contains('MP4 conversion')) {
      return 'Conversion failed — tap retry';
    }
    return 'Download failed — tap retry';
  }

  // ═══════════════════════════════════════════════════════════
  //  PAUSE / RESUME / CANCEL
  // ═══════════════════════════════════════════════════════════

  Future<void> pauseDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;

    // Segment-based download
    if (_activeHlsDownloads.containsKey(item.id)) {
      _activeHlsDownloads[item.id]?.pause();
      item.status = DownloadStatus.paused;
      _saveDownloads();

      // Update notification to show 'Resume'
      _notifService.showProgress(
        id: item.id.hashCode,
        title: item.displayName,
        progress: (item.progress * 100).toInt(),
        body: 'Paused · ${(item.progress * 100).toInt()}%',
        payload: item.id,
        isPaused: true,
      );

      _updateController.add(item);
      onDownloadUpdate?.call(item);
      return;
    }

    // Legacy flutter_downloader
    if (item.taskId != null) {
      await FlutterDownloader.pause(taskId: item.taskId!);
      item.status = DownloadStatus.paused;
      _saveDownloads();
      _updateController.add(item);
      onDownloadUpdate?.call(item);
    }
  }

  Future<void> resumeDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;

    // If there's an active service, just unpause it
    if (_activeHlsDownloads.containsKey(item.id)) {
      _activeHlsDownloads[item.id]?.resume();
      item.status = DownloadStatus.downloading;
      _saveDownloads();

      // Update notification to show 'Pause'
      _notifService.showProgress(
        id: item.id.hashCode,
        title: item.displayName,
        progress: (item.progress * 100).toInt(),
        body: 'Downloading · ${(item.progress * 100).toInt()}%',
        payload: item.id,
        isPaused: false,
      );

      _updateController.add(item);
      onDownloadUpdate?.call(item);
      return;
    }

    // If paused/failed with a segment directory, restart the download service
    // (it will auto-skip already completed segments)
    if (item.segmentDirectory != null && item.localPath != null) {
      item.status = DownloadStatus.downloading;
      item.error = null;
      await _saveDownloads();
      _updateController.add(item);
      onDownloadUpdate?.call(item);

      _notifService.showProgress(
        id: item.id.hashCode,
        title: item.displayName,
        progress: (item.progress * 100).toInt(),
        body: 'Resuming download…',
        payload: item.id,
      );

      _runSegmentDownload(item);
      return;
    }

    // Legacy flutter_downloader
    if (item.taskId != null) {
      final taskId = await FlutterDownloader.resume(taskId: item.taskId!);
      item.taskId = taskId;
      item.status = DownloadStatus.downloading;
      _saveDownloads();
      onDownloadUpdate?.call(item);
    }
  }

  Future<void> cancelDownload(String id) async {
    if (kIsWeb) return;
    final item = _findById(id);
    if (item == null) return;

    // Cancel active segment download
    if (_activeHlsDownloads.containsKey(item.id)) {
      _activeHlsDownloads[item.id]?.cancel();
      _activeHlsDownloads.remove(item.id);
    }

    // Legacy flutter_downloader
    if (item.taskId != null) {
      await FlutterDownloader.cancel(taskId: item.taskId!);
    }

    item.status = DownloadStatus.canceled;
    _notifService.cancel(item.id.hashCode);

    // Clean up segment directory if exists
    if (item.segmentDirectory != null) {
      try {
        final segDir = Directory(item.segmentDirectory!);
        if (await segDir.exists()) await segDir.delete(recursive: true);
      } catch (_) {}
    }

    _saveDownloads();
    _updateController.add(item);
    onDownloadUpdate?.call(item);
    if (item.status == DownloadStatus.completed) {
      _completeController.add(item);
    }
  }

  Future<void> deleteDownload(String id, {bool deleteFile = true}) async {
    final item = _findById(id);
    if (item == null) return;

    _notifService.cancel(item.id.hashCode);

    // Cancel if still active
    if (_activeHlsDownloads.containsKey(item.id)) {
      _activeHlsDownloads[item.id]?.cancel();
      _activeHlsDownloads.remove(item.id);
    }

    if (deleteFile) {
      // Delete the output file
      if (item.localPath != null && !kIsWeb) {
        final file = File(item.localPath!);
        if (await file.exists()) await file.delete();
      }

      // Delete segment directory if exists
      if (item.segmentDirectory != null && !kIsWeb) {
        try {
          final segDir = Directory(item.segmentDirectory!);
          if (await segDir.exists()) await segDir.delete(recursive: true);
        } catch (_) {}
      }
    }

    _downloads.removeWhere((d) => d.id == id);
    _saveDownloads();
  }

  // ═══════════════════════════════════════════════════════════
  //  LEGACY DOWNLOAD METHOD (direct MP4 URLs via flutter_downloader)
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
    if (!hasPermission) {
      throw Exception('Storage permission denied');
    }

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
      final fileName = item.fileName;

      final taskId = await FlutterDownloader.enqueue(
        url: url,
        savedDir: dir.path,
        fileName: fileName,
        showNotification: true,
        saveInPublicStorage: true,
      );

      item.taskId = taskId;
      item.localPath = '${dir.path}/$fileName';
      _saveDownloads();

      onDownloadUpdate?.call(item);
    } catch (e) {
      item.status = DownloadStatus.failed;
      item.error = e.toString();
      _saveDownloads();
      onDownloadUpdate?.call(item);
    }

    return item;
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
      final data = prefs.getString(_downloadsKey);
      if (data != null) {
        final List<dynamic> jsonList = jsonDecode(data);
        _downloads.clear();
        _downloads.addAll(jsonList.map((json) => DownloadItem.fromJson(json)));
      }
    } catch (e) {
      debugPrint('Error loading downloads: $e');
    }
  }

  Future<void> _saveDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonEncode(_downloads.map((d) => d.toJson()).toList());
      await prefs.setString(_downloadsKey, data);
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

  // ─── Delete Confirmation Modal (trigger from Notification) ────────────────
  void _showDeleteConfirmationGlobal(DownloadItem item) {
    final context = rootNavKey.currentContext;
    if (context == null) {
      // App is killed or no context; just cancel fallback
      cancelDownload(item.id);
      return;
    }

    bool deleteFromStorage = true;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Delete Confirmation',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Material(
                color: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.border, width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.red,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Delete Download?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Are you sure you want to delete\n"${item.displayName}"?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textSecondary.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Storage toggle
                      GestureDetector(
                        onTap: () {
                          setModalState(() {
                            deleteFromStorage = !deleteFromStorage;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: deleteFromStorage
                                  ? Colors.red.withValues(alpha: 0.4)
                                  : AppColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                deleteFromStorage
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color: deleteFromStorage
                                    ? Colors.red
                                    : AppColors.textMuted,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Also delete from device storage',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              style: TextButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side:
                                      const BorderSide(color: AppColors.border),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                deleteDownload(
                                  item.id,
                                  deleteFile: deleteFromStorage,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Delete',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
